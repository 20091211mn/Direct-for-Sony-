import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Build number injected by CI (--dart-define=BUILD_NUMBER=...). 0 = local build.
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

/// GitHub repository that publishes the releases (must be public).
const String kRepo = '20091211mn/Direct-for-Sony-';

/// SideStore / AltStore source published by the iOS workflow.
const String kSourceUrl =
    'https://github.com/$kRepo/releases/download/ios-latest/altstore.json';

/// Name of the Android APK attached to every release.
const String kApkName = 'ps4-sender.apk';

/// Bullet lines of release notes ("- feature", "* feature", "• feature").
/// Falls back to the non-empty lines when there are no bullets.
List<String> parseFeatures(String notes) {
  final lines = notes
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !RegExp(r'^Build \d+$').hasMatch(l))
      .toList();
  final bullets = lines
      .where((l) => l.startsWith('-') || l.startsWith('*') || l.startsWith('•'))
      .map((l) => l.replaceFirst(RegExp(r'^[-*•]\s*'), '').trim())
      .where((l) => l.isNotEmpty)
      .toList();
  return bullets.isNotEmpty ? bullets : lines;
}

class UpdateInfo {
  UpdateInfo({
    required this.tag,
    required this.build,
    required this.notes,
    required this.pageUrl,
    this.apkUrl,
    this.ipaUrl,
  });

  final String tag;
  final int build;
  final String notes;
  final String pageUrl;
  final String? apkUrl;
  final String? ipaUrl;

  List<String> get features => parseFeatures(notes);
}

/// What the native side found out about a downloaded APK.
class ApkCheck {
  ApkCheck({this.archiveVersion, this.installedVersion, this.sameSignature});

  final int? archiveVersion;
  final int? installedVersion;

  /// null = unknown (old Android versions cannot tell).
  final bool? sameSignature;
}

/// Result of the last update attempt, found at the next start.
class UpdateOutcome {
  UpdateOutcome(
      {required this.success, required this.tag, required this.features});

  final bool success;
  final String tag;
  final List<String> features;
}

class Updater {
  static const _ch = MethodChannel('ps4sender/updater');

  static Future<String> _get(String url) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(Uri.parse(url));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'ps4-sender');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) throw Exception('not_found');
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return body;
    } finally {
      c.close(force: true);
    }
  }

  /// The newest published version for this platform, or null when this build
  /// is already the latest. Throws when the check fails ("not_found" = private repo).
  static Future<UpdateInfo?> check() async {
    final best = Platform.isIOS ? await _latestIos() : await _latestAndroid();
    if (best == null || best.build <= kBuildNumber) return null;
    return best;
  }

  /// Same as [check] but hides a build the user already failed to install
  /// (so the banner does not come back again and again).
  static Future<UpdateInfo?> checkQuiet() async {
    final u = await check();
    if (u == null) return null;
    try {
      final p = await SharedPreferences.getInstance();
      if (u.build <= (p.getInt('snoozed_build') ?? 0)) return null;
    } catch (_) {}
    return u;
  }

  static Future<UpdateInfo?> _latestAndroid() async {
    final list = jsonDecode(await _get(
        'https://api.github.com/repos/$kRepo/releases?per_page=15')) as List;
    UpdateInfo? best;
    for (final r in list) {
      final m = r as Map;
      if (m['draft'] == true || m['prerelease'] == true) continue;
      final tag = (m['tag_name'] ?? '') as String;
      final build = int.tryParse(tag.split('.').last) ?? 0;
      String? apk;
      for (final a in (m['assets'] as List? ?? const [])) {
        if ((a as Map)['name'] == kApkName) {
          apk = (a['browser_download_url'] ?? '') as String;
        }
      }
      if (apk == null || apk.isEmpty) continue; // release without an APK
      if (best == null || build > best.build) {
        best = UpdateInfo(
          tag: tag,
          build: build,
          notes: ((m['body'] ?? '') as String).trim(),
          pageUrl: (m['html_url'] ?? '') as String,
          apkUrl: apk,
        );
      }
    }
    return best;
  }

  /// On iPhone the version comes from the SideStore source (iOS builds only),
  /// not from the Android releases, which are published far more often.
  static Future<UpdateInfo?> _latestIos() async {
    final j = jsonDecode(await _get(kSourceUrl)) as Map<String, dynamic>;
    final apps = j['apps'] as List? ?? const [];
    if (apps.isEmpty) return null;
    final app = apps.first as Map;
    final versions = app['versions'] as List? ?? const [];
    if (versions.isEmpty) return null;
    final v = versions.first as Map;
    final build = int.tryParse('${v['buildVersion'] ?? ''}') ?? 0;
    return UpdateInfo(
      tag: 'v${v['version'] ?? build}',
      build: build,
      notes: ((v['localizedDescription'] ?? '') as String).trim(),
      pageUrl: 'https://github.com/$kRepo/releases',
      ipaUrl: (v['downloadURL'] ?? '') as String,
    );
  }

  // ------------------------------------------------------------- install

  /// Downloads the APK into the app cache and reports progress (0..1).
  static Future<String> download(
      String url, void Function(double progress) onProgress) async {
    final dir = await _ch.invokeMethod<String>('cacheDir');
    final file = File('$dir/update.apk');
    if (await file.exists()) await file.delete();
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await c.getUrl(Uri.parse(url)); // follows redirects
      final res = await req.close();
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in res) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
      return file.path;
    } finally {
      c.close(force: true);
    }
  }

  /// Compares the downloaded APK with the installed app (version and signature)
  /// so a doomed update is explained instead of failing silently.
  static Future<ApkCheck> inspect(String path) async {
    try {
      final m =
          await _ch.invokeMapMethod<String, dynamic>('inspect', {'path': path});
      if (m == null) return ApkCheck();
      return ApkCheck(
        archiveVersion: (m['archiveVersion'] as num?)?.toInt(),
        installedVersion: (m['installedVersion'] as num?)?.toInt(),
        sameSignature: m['sameSignature'] as bool?,
      );
    } catch (_) {
      return ApkCheck();
    }
  }

  /// Opens the system installer. Returns "started" or "needs_permission".
  static Future<String?> install(String path) =>
      _ch.invokeMethod<String>('install', {'path': path});

  // ------------------------------------------------------- update bookkeeping

  /// Remembers that the user started installing [u].
  static Future<void> markPending(UpdateInfo u) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('pending_build', u.build);
      await p.setInt('pending_time', DateTime.now().millisecondsSinceEpoch);
      await p.setString('pending_tag', u.tag);
      await p.setString('pending_notes', u.features.join('\n'));
    } catch (_) {}
  }

  /// Hides [build] from the automatic banner (the manual check still shows it).
  static Future<void> snooze(int build) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('snoozed_build', build);
    } catch (_) {}
  }

  /// Call once at startup: did the last update attempt work?
  static Future<UpdateOutcome?> reconcile() async {
    try {
      final p = await SharedPreferences.getInstance();
      final pending = p.getInt('pending_build');
      if (pending == null) return null;
      final tag = p.getString('pending_tag') ?? 'v1.0.$pending';
      final notes = p.getString('pending_notes') ?? '';
      final age = DateTime.now().millisecondsSinceEpoch -
          (p.getInt('pending_time') ?? 0);
      if (kBuildNumber >= pending) {
        await _clearPending(p);
        return UpdateOutcome(
            success: true, tag: tag, features: parseFeatures(notes));
      }
      if (age > 60 * 1000) {
        await _clearPending(p);
        await p.setInt('snoozed_build', pending);
        return UpdateOutcome(success: false, tag: tag, features: const []);
      }
    } catch (_) {}
    return null;
  }

  static Future<void> _clearPending(SharedPreferences p) async {
    await p.remove('pending_build');
    await p.remove('pending_time');
    await p.remove('pending_tag');
    await p.remove('pending_notes');
  }
}
