import 'package:flutter/services.dart';

/// Android: the periodic background check that shows a system notification when
/// the admin publishes news or a new update, plus tools to diagnose it.
/// On iPhone these calls do nothing (iOS cannot poll in the background).
class NotifyBridge {
  static const _ch = MethodChannel('ps4sender/notify');

  static Future<void> schedule(String repo, bool ar) async {
    try {
      await _ch.invokeMethod('schedule', {'repo': repo, 'ar': ar});
    } catch (_) {}
  }

  /// {allowed, scheduled, lastRun (ms), lastResult} or null.
  static Future<Map<String, dynamic>?> status() async {
    try {
      return await _ch.invokeMapMethod<String, dynamic>('status');
    } catch (_) {
      return null;
    }
  }

  /// Runs the check right now. Returns "ok: N new" or "error: ...".
  static Future<String?> checkNow() async {
    try {
      return await _ch.invokeMethod<String>('checkNow');
    } catch (e) {
      return 'error: $e';
    }
  }

  /// Shows a test notification. False when the system does not allow it.
  static Future<bool> test() async {
    try {
      return (await _ch.invokeMethod<bool>('test')) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openSettings() async {
    try {
      await _ch.invokeMethod('openSettings');
    } catch (_) {}
  }
}
