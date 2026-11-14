import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'updater.dart' show kRepo;

/// Public catalog published by the admin app (store/catalog.json in the repository).
const String kStoreCatalogUrl =
    'https://raw.githubusercontent.com/$kRepo/main/store/catalog.json';

class StoreItem {
  StoreItem({
    required this.id,
    required this.title,
    required this.url,
    this.category = '',
    this.description = '',
    this.version = '',
    this.size = 0,
    this.icon = '',
    this.added = '',
  });

  final String id;
  final String title;
  final String url;
  final String category;
  final String description;
  final String version;
  final int size;
  final String icon;
  final String added;

  factory StoreItem.fromJson(Map<String, dynamic> j) => StoreItem(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        url: (j['url'] ?? '') as String,
        category: (j['category'] ?? '') as String,
        description: (j['description'] ?? '') as String,
        version: (j['version'] ?? '') as String,
        size: ((j['size'] ?? 0) as num).toInt(),
        icon: (j['icon'] ?? '') as String,
        added: (j['added'] ?? '') as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'description': description,
        'version': version,
        'size': size,
        'icon': icon,
        'url': url,
        'added': added,
      };
}

class StoreCatalog {
  StoreCatalog(this.items, {this.exists = true});

  final List<StoreItem> items;

  /// False when no catalog has been published yet.
  final bool exists;

  factory StoreCatalog.parse(String text) {
    final j = jsonDecode(text) as Map<String, dynamic>;
    final list = (j['items'] as List? ?? const [])
        .map((e) => StoreItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return StoreCatalog(list);
  }

  String encode() => const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'updated': DateTime.now().toUtc().toIso8601String(),
        'items': items.map((e) => e.toJson()).toList(),
      });
}

class StoreService {
  static const _cacheKey = 'store_cache';

  /// Downloads the catalog. Falls back to the last saved copy when offline.
  static Future<StoreCatalog> fetch() async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(
          '$kStoreCatalogUrl?t=${DateTime.now().millisecondsSinceEpoch}');
      final req = await c.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'ps4-sender');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return StoreCatalog([], exists: false);
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}');
      final cat = StoreCatalog.parse(body);
      try {
        (await SharedPreferences.getInstance()).setString(_cacheKey, body);
      } catch (_) {}
      return cat;
    } catch (e) {
      try {
        final cached =
            (await SharedPreferences.getInstance()).getString(_cacheKey);
        if (cached != null) return StoreCatalog.parse(cached);
      } catch (_) {}
      rethrow;
    } finally {
      c.close(force: true);
    }
  }
}
