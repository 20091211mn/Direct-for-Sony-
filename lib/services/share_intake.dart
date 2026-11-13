import 'package:flutter/services.dart';

/// Android: receives links and files sent with the system "Share" menu.
class ShareIntake {
  static const _ch = MethodChannel('ps4sender/share');

  /// Called when something is shared while the app is already running.
  static void listen(Future<void> Function(Map<dynamic, dynamic> data) onShare) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is Map) {
        await onShare(call.arguments as Map<dynamic, dynamic>);
      }
    });
  }

  /// What the app was launched with (null when launched normally).
  static Future<Map<dynamic, dynamic>?> initial() async {
    try {
      return await _ch.invokeMethod<Map<dynamic, dynamic>>('initial');
    } catch (_) {
      return null;
    }
  }
}
