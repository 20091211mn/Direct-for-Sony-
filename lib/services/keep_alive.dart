import 'package:flutter/services.dart';

/// Android foreground service (wake + Wi-Fi locks) so the phone keeps serving the
/// PS4 while the app is in background, plus the progress notification.
/// On iPhone these calls do nothing (no such service exists there).
class ForegroundKeeper {
  static const _ch = MethodChannel('ps4sender/keepalive');

  static Future<void> start() async {
    try {
      await _ch.invokeMethod('start');
    } catch (_) {}
  }

  static Future<void> stop() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }

  /// Updates the ongoing notification (percentage bar + text).
  static Future<void> progress(int pct, String text) async {
    try {
      await _ch.invokeMethod('progress', {'pct': pct, 'text': text});
    } catch (_) {}
  }

  /// Posts a normal "finished" notification.
  static Future<void> finished(String text) async {
    try {
      await _ch.invokeMethod('done', {'text': text});
    } catch (_) {}
  }
}
