// Protocol ported from DirectPackageInstaller (marcussacana, GPL-3.0):
//   Host/PayloadService.cs, Host/PS4Server.cs (RegisterJSON), Payload/info.c
//
// Flow (GoldHEN BinLoader only, no Remote Package Installer):
//  1. Listen on a local TCP port ("info socket") and an HTTP port (manifest).
//  2. Connect to PS4:9090 (BinLoader), patch the payload with our IP:port
//     and send it. The payload runs on the PS4.
//  3. The payload connects back to the info socket. We send the package
//     info (URL of our manifest, name, content id, type, size, icon).
//  4. The PS4 downloads http://PHONE:PORT/json/0.json, which points to the
//     real PKG URL, and queues the download.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'pkg_info.dart';

typedef Log = void Function(String message);

class Ps4Sender {
  static const _binLoaderPorts = [9090, 9021, 9020];

  /// Returns the phone's LAN IPv4 (Wi-Fi), or null.
  static Future<String?> localIp() async {
    final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in ifaces) {
      for (final a in i.addresses) {
        final s = a.address;
        if (s.startsWith('192.168.') ||
            s.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(s)) {
          return s;
        }
      }
    }
    return null;
  }

  static Future<void> send({
    required String ps4Ip,
    required String phoneIp,
    required PkgInfo pkg,
    required Log log,
  }) async {
    ServerSocket? info;
    HttpServer? http;
    try {
      // --- 1. manifest HTTP server -------------------------------------
      http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final manifest = jsonEncode({
        'originalFileSize': pkg.size,
        // TODO: the original sends the PKG header digest here. Zeros are
        // used until verified on a real console.
        'packageDigest': '',
        'numberOfSplitFiles': 1,
        'pieces': [
          {
            'url': pkg.url,
            'fileOffset': 0,
            'fileSize': pkg.size,
            'hashValue': '0000000000000000000000000000000000000000',
          }
        ],
      });
      http.listen((req) async {
        log('PS4 requested ${req.uri.path}');
        if (req.uri.path.startsWith('/json/')) {
          req.response.headers.contentType = ContentType.json;
          req.response.write(manifest);
        } else {
          req.response.statusCode = 404;
        }
        await req.response.close();
      });
      final manifestUrl = 'http://$phoneIp:${http.port}/json/0.json';
      log('Manifest: $manifestUrl');

      // --- 2. info socket (the payload connects back here) --------------
      info = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final queue = StreamController<Socket>();
      info.listen(queue.add);
      final incoming = StreamIterator<Socket>(queue.stream);

      // --- 3. send payload to BinLoader ---------------------------------
      await _sendPayload(ps4Ip, phoneIp, info.port, log);

      // --- 4. wait for the payload, send package info -------------------
      log('Waiting for the PS4 payload...');
      Socket client = await _next(incoming, const Duration(seconds: 15));
      client.add(_infoBuffer(manifestUrl, pkg));
      await client.flush();
      await client.close();
      log('Package info sent');

      // The payload loops asking for more packages. Send "0" to make it
      // exit cleanly after this one.
      try {
        final again = await _next(incoming, const Duration(seconds: 10));
        again.add(Uint8List(4));
        await again.flush();
        await again.close();
      } catch (_) {}

      // Give the PS4 time to fetch the manifest.
      await Future<void>.delayed(const Duration(seconds: 5));
      log('Done. Check the PS4 notifications / Downloads.');
    } finally {
      await info?.close();
      await http?.close(force: true);
    }
  }

  static Future<Socket> _next(StreamIterator<Socket> it, Duration t) async {
    final ok = await it.moveNext().timeout(t);
    if (!ok) throw Exception('Connection closed');
    return it.current;
  }

  static Future<void> _sendPayload(
      String ps4Ip, String phoneIp, int port, Log log) async {
    final payload =
        (await rootBundle.load('assets/payload.bin')).buffer.asUint8List().toList();
    Uint8List data = Uint8List.fromList(payload);

    // Marker: 6 bytes 0xB4. First 4 = IP, next 2 = port (big endian).
    var off = -1;
    for (var i = 0; i <= data.length - 6; i++) {
      var ok = true;
      for (var j = 0; j < 6; j++) {
        if (data[i + j] != 0xB4) {
          ok = false;
          break;
        }
      }
      if (ok) {
        off = i;
        break;
      }
    }
    if (off < 0) throw Exception('Payload marker not found');

    final ip = phoneIp.split('.').map(int.parse).toList();
    for (var i = 0; i < 4; i++) {
      data[off + i] = ip[i];
    }
    data[off + 4] = (port >> 8) & 0xFF;
    data[off + 5] = port & 0xFF;

    for (var attempt = 0; attempt < 2; attempt++) {
      for (final p in _binLoaderPorts) {
        try {
          final s = await Socket.connect(ps4Ip, p,
              timeout: const Duration(seconds: 3));
          s.setOption(SocketOption.tcpNoDelay, true);
          s.add(data);
          await s.flush();
          await s.close();
          log('Payload sent to $ps4Ip:$p');
          return;
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw Exception(
        'Could not reach BinLoader on the PS4 (ports 9090/9021/9020).\n'
        'Enable GoldHEN > Servers > BinLoader and check the IP.');
  }

  /// Wire format read by Payload/info.c (all integers little-endian):
  /// u32 1 | (u32 len + bytes) url, name, id, type | u64 size | u32 iconLen + icon
  static Uint8List _infoBuffer(String manifestUrl, PkgInfo pkg) {
    final b = BytesBuilder();
    void u32(int v) =>
        b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
    void str(String s) {
      final bytes = utf8.encode(s);
      u32(bytes.length);
      b.add(bytes);
    }

    u32(1);
    str(manifestUrl);
    str(pkg.title);
    str(pkg.contentId);
    str(pkg.bgftType);
    b.add((ByteData(8)..setUint64(0, pkg.size, Endian.little))
        .buffer
        .asUint8List());
    final icon = pkg.icon;
    if (icon == null || icon.isEmpty) {
      u32(0);
    } else {
      u32(icon.length);
      b.add(icon);
    }
    return b.takeBytes();
  }
}
