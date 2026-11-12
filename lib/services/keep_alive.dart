import 'package:flutter/services.dart';

/// Starts/stops the Android foreground service (with wake + Wi-Fi locks)
/// so the phone keeps serving the PS4 while the app is in background.
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
}
