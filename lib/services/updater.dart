import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Build number injected by CI (--dart-define=BUILD_NUMBER=...). 0 = local build.
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

/// GitHub repository that publishes the releases (must be public).
const String kRepo = '20091211mn/Direct-for-Sony-';

/// SideStore / AltStore source published by the iOS workflow.
const String kSourceUrl =
    'https://github.com/$kRepo/releases/download/ios-latest/altstore.json';

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
}

class Updater {
  static const _ch = MethodChannel('ps4sender/updater');

  /// Returns the newer release, or null when this build is the latest.
  /// Throws when the check fails (message "not_found" = private/missing repo).
  static Future<UpdateInfo?> check() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(
          Uri.parse('https://api.github.com/repos/$kRepo/releases/latest'));
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'ps4-sender');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) throw Exception('not_found');
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');

      final j = jsonDecode(body) as Map<String, dynamic>;
      final tag = (j['tag_name'] ?? '') as String;
      final build = int.tryParse(tag.split('.').last) ?? 0;
      if (build <= kBuildNumber) return null;

      String? apk, ipa;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = ((a as Map)['name'] ?? '') as String;
        final url = (a['browser_download_url'] ?? '') as String;
        if (name.endsWith('.apk')) apk = url;
        if (name.endsWith('.ipa')) ipa = url;
      }
      return UpdateInfo(
        tag: tag,
        build: build,
        notes: ((j['body'] ?? '') as String).trim(),
        pageUrl: (j['html_url'] ?? '') as String,
        apkUrl: apk,
        ipaUrl: ipa,
      );
    } finally {
      c.close(force: true);
    }
  }

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

  /// Opens the system installer. Returns "started" or "needs_permission".
  static Future<String?> install(String path) =>
      _ch.invokeMethod<String>('install', {'path': path});
}
