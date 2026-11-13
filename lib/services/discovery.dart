import 'dart:io';

/// Finds a PS4 with GoldHEN BinLoader enabled on the local network.
class Discovery {
  static const _ports = [9090, 9021, 9020];

  static Future<bool> _open(String ip, int port, Duration timeout) async {
    try {
      final s = await Socket.connect(ip, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True when BinLoader answers on one of its known ports.
  static Future<bool> test(String ip) async {
    for (final p in _ports) {
      if (await _open(ip, p, const Duration(seconds: 2))) return true;
    }
    return false;
  }

  /// Scans the phone's /24 network for hosts with port 9090 open.
  static Future<List<String>> scan(String phoneIp) async {
    final parts = phoneIp.split('.');
    if (parts.length != 4) return [];
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}.';
    final hosts = <String>[
      for (var i = 1; i < 255; i++)
        if ('$prefix$i' != phoneIp) '$prefix$i',
    ];
    final found = <String>[];
    for (var i = 0; i < hosts.length; i += 64) {
      final batch = hosts.skip(i).take(64);
      await Future.wait(batch.map((h) async {
        if (await _open(h, 9090, const Duration(milliseconds: 700))) {
          found.add(h);
        }
      }));
    }
    found.sort();
    return found;
  }
}
