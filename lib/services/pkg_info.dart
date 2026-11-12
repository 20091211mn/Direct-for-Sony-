import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Basic info read from a PS4 PKG (remote link or local file).
class PkgInfo {
  PkgInfo({
    required this.size,
    required this.title,
    required this.contentId,
    required this.category,
    required this.digest,
    this.url,
    this.localPath,
    this.icon,
  });

  /// Direct link (null when the package is a local file).
  final String? url;

  /// Path of the picked file (null when the package is a link).
  final String? localPath;
  final int size;
  final String title;
  final String contentId;
  final String category; // e.g. gd, gp, ac

  /// PKG header digest (32 bytes at 0xFE0) as upper-case hex.
  final String digest;
  final Uint8List? icon;

  /// Same rule the original tool uses: "PS4" + CATEGORY upper-case.
  String get bgftType => 'PS4${category.toUpperCase()}';
}

abstract class _ByteSource {
  Future<int> size();
  Future<Uint8List> read(int from, int toInclusive);
  Future<void> close();
}

class _HttpSource implements _ByteSource {
  _HttpSource(this.url);

  final String url;
  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);
  int? _size;

  Future<HttpClientResponse> _range(int from, int to) async {
    final req = await _client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
    return req.close();
  }

  @override
  Future<int> size() async {
    if (_size != null) return _size!;
    final probe = await _range(0, 0);
    final cr = probe.headers.value('content-range');
    int? size;
    if (cr != null && cr.contains('/')) {
      size = int.tryParse(cr.split('/').last);
    }
    size ??= probe.contentLength > 0 ? probe.contentLength : null;
    await probe.drain<void>();
    if (size == null) throw Exception('Server did not report the file size');
    return _size = size;
  }

  @override
  Future<Uint8List> read(int from, int toInclusive) async {
    final res = await _range(from, toInclusive);
    if (res.statusCode != 206 && res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}');
    }
    final want = toInclusive - from + 1;
    final b = BytesBuilder();
    await for (final chunk in res) {
      b.add(chunk);
      if (b.length > want) break; // server ignored Range
    }
    final all = b.takeBytes();
    return all.length > want ? Uint8List.sublistView(all, 0, want) : all;
  }

  @override
  Future<void> close() async => _client.close(force: true);
}

class _FileSource implements _ByteSource {
  _FileSource(this.path);

  final String path;
  RandomAccessFile? _raf;

  @override
  Future<int> size() => File(path).length();

  @override
  Future<Uint8List> read(int from, int toInclusive) async {
    final raf = _raf ??= await File(path).open();
    await raf.setPosition(from);
    return raf.read(toInclusive - from + 1);
  }

  @override
  Future<void> close() async => _raf?.close();
}

class PkgReader {
  static const _entryParamSfo = 0x1000;
  static const _entryIcon0 = 0x1200;

  static Future<PkgInfo> readUrl(String url) =>
      _read(_HttpSource(url), url: url);

  static Future<PkgInfo> readFile(String path) =>
      _read(_FileSource(path), localPath: path);

  static Future<PkgInfo> _read(_ByteSource src,
      {String? url, String? localPath}) async {
    try {
      final size = await src.size();

      final head = await src.read(0, 0xFFFF);
      final bd = ByteData.sublistView(head);
      if (head.length < 0x40 || bd.getUint32(0, Endian.big) != 0x7F434E54) {
        throw Exception('Not a PS4 PKG (bad magic)');
      }
      final count = bd.getUint32(0x10, Endian.big);
      final tableOff = bd.getUint32(0x18, Endian.big);

      int? sfoOff, sfoLen, iconOff, iconLen;
      for (var i = 0; i < count; i++) {
        final o = tableOff + i * 32;
        if (o + 32 > head.length) break;
        final id = bd.getUint32(o, Endian.big);
        final off = bd.getUint32(o + 16, Endian.big);
        final len = bd.getUint32(o + 20, Endian.big);
        if (id == _entryParamSfo) {
          sfoOff = off;
          sfoLen = len;
        } else if (id == _entryIcon0) {
          iconOff = off;
          iconLen = len;
        }
      }
      if (sfoOff == null || sfoLen == null) {
        throw Exception('PARAM.SFO not found in PKG');
      }

      final sfo = _parseSfo(await src.read(sfoOff, sfoOff + sfoLen - 1));
      Uint8List? icon;
      if (iconOff != null &&
          iconLen != null &&
          iconLen > 0 &&
          iconLen < 2 * 1024 * 1024) {
        icon = await src.read(iconOff, iconOff + iconLen - 1);
      }

      // Final header digest: 32 bytes at 0xFE0 (header ends at 0x1000).
      var digest = '0' * 64;
      if (head.length >= 0x1000) {
        digest = head
            .sublist(0xFE0, 0x1000)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join()
            .toUpperCase();
      }

      return PkgInfo(
        url: url,
        localPath: localPath,
        size: size,
        title: sfo['TITLE'] ?? 'Unknown',
        contentId: sfo['CONTENT_ID'] ?? '',
        category: sfo['CATEGORY'] ?? 'gd',
        digest: digest,
        icon: icon,
      );
    } finally {
      await src.close();
    }
  }

  /// Minimal PARAM.SFO parser (little-endian).
  static Map<String, String> _parseSfo(Uint8List d) {
    final bd = ByteData.sublistView(d);
    if (bd.getUint32(0, Endian.little) != 0x46535000) return {};
    final keyTable = bd.getUint32(8, Endian.little);
    final dataTable = bd.getUint32(12, Endian.little);
    final n = bd.getUint32(16, Endian.little);
    final out = <String, String>{};
    for (var i = 0; i < n; i++) {
      final e = 20 + i * 16;
      final keyOff = bd.getUint16(e, Endian.little);
      final fmt = bd.getUint16(e + 2, Endian.little);
      final len = bd.getUint32(e + 4, Endian.little);
      final dOff = bd.getUint32(e + 12, Endian.little);

      final k = keyTable + keyOff;
      final kEnd = d.indexOf(0, k);
      final key = ascii.decode(d.sublist(k, kEnd), allowInvalid: true);

      final start = dataTable + dOff;
      if (fmt == 0x0204 || fmt == 0x0004) {
        final raw = d.sublist(start, start + len);
        final z = raw.indexOf(0);
        out[key] = utf8.decode(z >= 0 ? raw.sublist(0, z) : raw,
            allowMalformed: true);
      } else if (fmt == 0x0404) {
        out[key] = bd.getUint32(start, Endian.little).toRadixString(16);
      }
    }
    return out;
  }
}
