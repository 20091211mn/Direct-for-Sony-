import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'updater.dart' show kRepo;

/// Notices published by the admin app (store/announcements.json).
const String kAnnouncementsUrl =
    'https://raw.githubusercontent.com/$kRepo/main/store/announcements.json';

class Announcement {
  Announcement({
    required this.id,
    required this.title,
    this.type = 'news',
    this.body = '',
    this.features = const [],
    this.date = '',
    this.build = 0,
  });

  final String id;

  /// "news" or "update".
  final String type;
  final String title;
  final String body;
  final List<String> features;
  final String date;

  /// For "update" notices: the build number the notice is about.
  final int build;

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: (j['id'] ?? '') as String,
        type: (j['type'] ?? 'news') as String,
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        features: ((j['features'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        date: (j['date'] ?? '') as String,
        build: ((j['build'] ?? 0) as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'body': body,
        'features': features,
        'date': date,
        'build': build,
      };

  static List<Announcement> parseList(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    return ((j['items'] as List?) ?? const [])
        .map((e) => Announcement.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static String encodeList(List<Announcement> items) =>
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'updated': DateTime.now().toUtc().toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
      });
}

class AnnouncementService {
  static const _cacheKey = 'announcements_cache';
  static const _readKey = 'announcements_read';

  /// Downloads the notices (newest first). Uses the saved copy when offline.
  static Future<List<Announcement>> fetch() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await c.getUrl(Uri.parse(
          '$kAnnouncementsUrl?t=${DateTime.now().millisecondsSinceEpoch}'));
      req.headers.set(HttpHeaders.userAgentHeader, 'ps4-sender');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return [];
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final list = Announcement.parseList(body);
      try {
        (await SharedPreferences.getInstance()).setString(_cacheKey, body);
      } catch (_) {}
      return list;
    } catch (e) {
      try {
        final cached =
            (await SharedPreferences.getInstance()).getString(_cacheKey);
        if (cached != null) return Announcement.parseList(cached);
      } catch (_) {}
      return [];
    } finally {
      c.close(force: true);
    }
  }

  static Future<Set<String>> readIds() async {
    try {
      final p = await SharedPreferences.getInstance();
      return (p.getStringList(_readKey) ?? const <String>[]).toSet();
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveReadIds(Set<String> ids) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_readKey, ids.toList());
    } catch (_) {}
  }
}
