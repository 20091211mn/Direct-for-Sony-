import 'package:flutter/services.dart';

/// Android: schedules the periodic background check that shows a system
/// notification when the admin publishes news or a new update.
/// On iPhone this does nothing (iOS cannot poll in the background).
class NotifyBridge {
  static const _ch = MethodChannel('ps4sender/notify');

  static Future<void> schedule(String repo, bool ar) async {
    try {
      await _ch.invokeMethod('schedule', {'repo': repo, 'ar': ar});
    } catch (_) {}
  }
}
