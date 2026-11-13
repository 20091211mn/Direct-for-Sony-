import 'dart:typed_data';

import 'package:flutter/services.dart';

class PickedFile {
  PickedFile(this.uri, this.name, this.size);
  final String uri;
  final String name;
  final int size;
}

/// Android only: picks files with the system document picker and reads them in
/// place through the ContentResolver (no copy into the app cache).
class NativeFiles {
  static const _ch = MethodChannel('ps4sender/files');

  static Future<List<PickedFile>> pick() async {
    final res = await _ch.invokeMethod<List<dynamic>>('pick') ?? const [];
    return res.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return PickedFile(
        m['uri'] as String,
        (m['name'] ?? 'file') as String,
        ((m['size'] ?? 0) as num).toInt(),
      );
    }).toList();
  }

  static Future<Uint8List> read(String uri, int offset, int length) async {
    final r = await _ch.invokeMethod<Uint8List>(
        'read', {'uri': uri, 'offset': offset, 'length': length});
    return r ?? Uint8List(0);
  }

  static Future<void> release() async {
    try {
      await _ch.invokeMethod('release');
    } catch (_) {}
  }
}
