import 'dart:convert';
import 'dart:io';

import '../services/native_files.dart';
import '../services/store_catalog.dart';

class GithubError implements Exception {
  GithubError(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => 'GitHub $status: $message';
}

/// Minimal GitHub REST client used by the admin app. The token needs the
/// "repo" permission on the store repository.
class GithubApi {
  GithubApi(this.token, this.repo);

  final String token;
  final String repo; // owner/name

  static const catalogPath = 'store/catalog.json';
  static const filesTag = 'store-files';

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'ps4-store-admin',
      };

  Future<({int status, String body})> _send(String method, String url,
      {Object? json}) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await c.openUrl(method, Uri.parse(url));
      _headers.forEach((k, v) => req.headers.set(k, v));
      if (json != null) {
        final data = utf8.encode(jsonEncode(json));
        req.headers.set('Content-Type', 'application/json');
        req.contentLength = data.length;
        req.add(data);
      }
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      return (status: res.statusCode, body: body);
    } finally {
      c.close(force: true);
    }
  }

  void _check(({int status, String body}) r, List<int> ok) {
    if (ok.contains(r.status)) return;
    var msg = r.body;
    try {
      msg = (jsonDecode(r.body) as Map)['message']?.toString() ?? r.body;
    } catch (_) {}
    throw GithubError(r.status, msg);
  }

  /// Checks the token and that it can write to the repository.
  Future<void> verify() async {
    final r = await _send('GET', 'https://api.github.com/repos/$repo');
    _check(r, [200]);
    final perms = (jsonDecode(r.body) as Map)['permissions'] as Map?;
    if (perms == null || perms['push'] != true) {
      throw GithubError(403, 'The token cannot write to $repo');
    }
  }

  Future<({String? text, String? sha})> getFile(String path) async {
    final r = await _send(
        'GET', 'https://api.github.com/repos/$repo/contents/$path?ref=main');
    if (r.status == 404) return (text: null, sha: null);
    _check(r, [200]);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final b64 = ((j['content'] ?? '') as String).replaceAll('\n', '');
    return (text: utf8.decode(base64.decode(b64)), sha: j['sha'] as String?);
  }

  Future<String?> sha(String path) async {
    final r = await _send(
        'GET', 'https://api.github.com/repos/$repo/contents/$path?ref=main');
    if (r.status == 404) return null;
    _check(r, [200]);
    return (jsonDecode(r.body) as Map)['sha'] as String?;
  }

  Future<void> putFile(String path, List<int> bytes, String message,
      {String? sha}) async {
    final r = await _send(
      'PUT',
      'https://api.github.com/repos/$repo/contents/$path',
      json: {
        'message': message,
        'content': base64.encode(bytes),
        'branch': 'main',
        if (sha != null) 'sha': sha,
      },
    );
    _check(r, [200, 201]);
  }

  // ---------------------------------------------------------------- catalog

  Future<List<StoreItem>> loadItems() async {
    final f = await getFile(catalogPath);
    if (f.text == null) return [];
    return StoreCatalog.parse(f.text!).items;
  }

  /// Applies [change] to the catalog and commits it (retries on conflicts).
  Future<void> _updateCatalog(
      List<StoreItem> Function(List<StoreItem> items) change,
      String message) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      final f = await getFile(catalogPath);
      final items = f.text == null ? <StoreItem>[] : StoreCatalog.parse(f.text!).items;
      final out = StoreCatalog(change(items)).encode();
      try {
        await putFile(catalogPath, utf8.encode(out), message, sha: f.sha);
        return;
      } on GithubError catch (e) {
        if ((e.status == 409 || e.status == 422) && attempt < 2) continue;
        rethrow;
      }
    }
  }

  Future<void> upsertItem(StoreItem item) => _updateCatalog((items) {
        final i = items.indexWhere((e) => e.id == item.id);
        if (i >= 0) {
          items[i] = item;
        } else {
          items.insert(0, item);
        }
        return items;
      }, 'store: ${item.title}');

  Future<void> removeItem(StoreItem item) async {
    await _updateCatalog(
        (items) => items.where((e) => e.id != item.id).toList(),
        'store: remove ${item.title}');
    // Also delete the uploaded file when it lives in our "store-files" release.
    final marker = '/releases/download/$filesTag/';
    final at = item.url.indexOf(marker);
    if (at >= 0) {
      try {
        final name = Uri.decodeComponent(item.url.substring(at + marker.length));
        final id = await ensureRelease();
        await deleteAsset(id, name);
      } catch (_) {}
    }
  }

  // --------------------------------------------------------- release assets

  Future<int> ensureRelease() async {
    var r = await _send(
        'GET', 'https://api.github.com/repos/$repo/releases/tags/$filesTag');
    if (r.status == 404) {
      r = await _send('POST', 'https://api.github.com/repos/$repo/releases',
          json: {
            'tag_name': filesTag,
            'name': 'Store files',
            'prerelease': true,
            'target_commitish': 'main',
            'body': 'Files published with the store admin app.',
          });
      _check(r, [201]);
    } else {
      _check(r, [200]);
    }
    return (jsonDecode(r.body) as Map)['id'] as int;
  }

  Future<void> deleteAsset(int releaseId, String name) async {
    final r = await _send('GET',
        'https://api.github.com/repos/$repo/releases/$releaseId/assets?per_page=100');
    _check(r, [200]);
    for (final a in jsonDecode(r.body) as List) {
      final m = a as Map;
      if (m['name'] == name) {
        await _send('DELETE',
            'https://api.github.com/repos/$repo/releases/assets/${m['id']}');
      }
    }
  }

  /// Streams [data] (exactly [size] bytes) to the release and returns the download URL.
  Future<String> uploadAsset(int releaseId, String name, int size,
      Stream<List<int>> data, void Function(int sent) onProgress) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = Uri.parse(
          'https://uploads.github.com/repos/$repo/releases/$releaseId/assets'
          '?name=${Uri.encodeQueryComponent(name)}');
      final req = await c.postUrl(uri);
      _headers.forEach((k, v) => req.headers.set(k, v));
      req.headers.set('Content-Type', 'application/octet-stream');
      req.contentLength = size;
      var sent = 0;
      await req.addStream(data.map((chunk) {
        sent += chunk.length;
        onProgress(sent);
        return chunk;
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 201) {
        var msg = body;
        try {
          msg = (jsonDecode(body) as Map)['message']?.toString() ?? body;
        } catch (_) {}
        throw GithubError(res.statusCode, msg);
      }
      return (jsonDecode(body) as Map)['browser_download_url'] as String;
    } finally {
      c.close(force: true);
    }
  }
}

/// Reads a picked Android file (content URI) in 1 MiB blocks.
Stream<List<int>> contentStream(String uri, int size) async* {
  var pos = 0;
  while (pos < size) {
    final n = size - pos < 1024 * 1024 ? size - pos : 1024 * 1024;
    final b = await NativeFiles.read(uri, pos, n);
    if (b.isEmpty) break;
    pos += b.length;
    yield b;
  }
}
