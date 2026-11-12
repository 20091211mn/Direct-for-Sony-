// Protocol ported from DirectPackageInstaller (marcussacana, GPL-3.0):
//   Host/PayloadService.cs, Host/PS4Server.cs (RegisterJSON), Payload/info.c
//
// Flow (GoldHEN BinLoader only, no Remote Package Installer):
//  1. Listen on a local TCP port ("info socket") and an HTTP port.
//  2. Connect to PS4:9090 (BinLoader), patch the payload with our IP:port
//     and send it. The payload runs on the PS4.
//  3. The payload connects back to the info socket. We send the package
//     info (URL of our manifest, name, content id, type, size, icon).
//  4. The PS4 downloads http://PHONE:PORT/json/0.json and then the package,
//     either from the phone (/proxy/ for links, /file/ for local files)
//     or directly from the original link.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import 'pkg_info.dart';

typedef Log = void Function(String message);

/// Lets the UI stop a running transfer.
class SendController {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

class _Stats {
  int served = 0;
  int active = 0;
  DateTime last = DateTime.now();
}

class _Chunk {
  _Chunk(this.data, this.error);
  final Uint8List? data;
  final Object? error;
}

class _Range {
  _Range(this.start, this.end, this.partial);
  final int start;
  final int end;
  final bool partial;
}

int _proxyLogged = 0;

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
    bool proxy = true,
    bool fast = true,
    void Function(int served)? onProgress,
    SendController? controller,
  }) async {
    ServerSocket? info;
    HttpServer? http;
    Timer? ticker;
    final stats = _Stats();
    final ctl = controller ?? SendController();
    _proxyLogged = 0;
    try {
      // --- 1. HTTP server: manifest + proxy/file ------------------------
      http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final isFile = pkg.localPath != null;
      final base = 'http://$phoneIp:${http.port}';
      final String pieceUrl;
      if (isFile) {
        pieceUrl = '$base/file/0.pkg';
      } else if (proxy) {
        pieceUrl = '$base/proxy/?b64='
            '${base64Url.encode(utf8.encode(pkg.url!)).replaceAll('=', '')}';
      } else {
        pieceUrl = pkg.url!;
      }
      final useServer = isFile || proxy;

      // Fast mode: the phone fetches the package with several parallel Range
      // requests (like the original "Segmented Downloads") and relays it.
      final Uri? fastUri =
          (proxy && !isFile && fast) ? await _probe(pkg.url!) : null;
      if (proxy && !isFile && fast) {
        log(fastUri != null
            ? 'Fast mode: parallel connections'
            : 'Fast mode unavailable (server ignores ranges), using normal mode');
      }

      final manifest = jsonEncode({
        'originalFileSize': pkg.size,
        // Same as the original tool: PKG header digest as upper-case hex.
        'packageDigest': pkg.digest,
        'numberOfSplitFiles': 1,
        'pieces': [
          {
            'url': pieceUrl,
            'fileOffset': 0,
            'fileSize': pkg.size,
            'hashValue': '0000000000000000000000000000000000000000',
          }
        ],
      });

      http.listen((req) async {
        stats.last = DateTime.now();
        final path = req.uri.path;
        if (path.startsWith('/proxy') && !isFile) {
          if (_proxyLogged++ < 6) {
            log('PS4 ${req.method} /proxy '
                '${req.headers.value(HttpHeaders.rangeHeader) ?? ''}');
          }
          final before = stats.served;
          stats.active++;
          try {
            final fu = fastUri;
            if (fu != null) {
              await _proxyFast(req, fu, pkg.size, stats, log);
            } else {
              await _proxy(req, stats, log);
            }
          } finally {
            stats.active--;
            stats.last = DateTime.now();
          }
          if (_proxyLogged <= 6) {
            log('Proxy served ${stats.served - before} bytes');
          }
        } else if (path.startsWith('/file/') && isFile) {
          if (_proxyLogged++ < 6) {
            log('PS4 ${req.method} /file '
                '${req.headers.value(HttpHeaders.rangeHeader) ?? ''}');
          }
          stats.active++;
          try {
            await _serveFile(req, pkg.localPath!, stats, log);
          } finally {
            stats.active--;
            stats.last = DateTime.now();
          }
        } else if (path.startsWith('/json/')) {
          log('PS4 ${req.method} ${req.uri.path}'
              '${req.headers.value(HttpHeaders.rangeHeader) ?? ''}');
          await _serveBytes(req, utf8.encode(manifest), 'application/json');
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      final manifestUrl = '$base/json/0.json';
      log('Manifest: $manifestUrl');

      ticker = Timer.periodic(const Duration(milliseconds: 500),
          (_) => onProgress?.call(stats.served));

      // --- 2. info socket (the payload connects back here) --------------
      info = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final queue = StreamController<Socket>();
      info.listen(queue.add);
      final incoming = StreamIterator<Socket>(queue.stream);

      // --- 3. send payload to BinLoader ---------------------------------
      await _sendPayload(ps4Ip, phoneIp, info.port, log);

      // --- 4. wait for the payload, send package info -------------------
      log('Waiting for the PS4 payload...');
      final client = await _next(incoming, const Duration(seconds: 15));
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

      if (!useServer) {
        // Direct mode: the PS4 downloads by itself; just let it fetch the manifest.
        await Future<void>.delayed(const Duration(seconds: 5));
      } else {
        log('Serving the package. Keep this app open until it ends.');
        while (!ctl.cancelled) {
          final idle = DateTime.now().difference(stats.last).inSeconds;
          final done = stats.served >= pkg.size;
          final limit = done ? 10 : (stats.served == 0 ? 120 : 60);
          if ((stats.active == 0 && idle >= limit) || idle >= 300) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        onProgress?.call(stats.served);
        log(ctl.cancelled
            ? 'Stopped by user'
            : 'Transferred ${stats.served ~/ (1024 * 1024)} MB');
      }
      log('Done. Check the PS4 notifications / Downloads.');
    } finally {
      ticker?.cancel();
      await info?.close();
      await http?.close(force: true);
    }
  }

  // ---------------------------------------------------------------------
  // HTTP helpers

  static _Range? _parseRange(String? header, int length) {
    var start = 0;
    var end = length - 1;
    var partial = false;
    final m =
        header == null ? null : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(header);
    if (m != null) {
      final a = m.group(1)!, b = m.group(2)!;
      if (a.isEmpty && b.isNotEmpty) {
        start = length - int.parse(b);
        if (start < 0) start = 0;
      } else if (a.isNotEmpty) {
        start = int.parse(a);
        if (b.isNotEmpty) end = int.parse(b);
      }
      if (end > length - 1) end = length - 1;
      partial = true;
    }
    if (start > end) return null;
    return _Range(start, end, partial);
  }

  /// Relays the request to the origin (following redirects/HTTPS) and
  /// streams the answer back, keeping Range support.
  static Future<void> _proxy(HttpRequest req, _Stats st, Log log) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = false;
    try {
      // The PS4 appends its own "?..." parameters to the URL, so read only
      // the URL-safe base64 characters right after "b64=".
      final m = RegExp(r'b64=([A-Za-z0-9_\-]+)').firstMatch(req.uri.query);
      if (m == null) throw Exception('missing url');
      final target =
          utf8.decode(base64Url.decode(base64Url.normalize(m.group(1)!)));
      final uri = Uri.parse(target);
      final up = req.method == 'HEAD'
          ? await client.headUrl(uri)
          : await client.getUrl(uri);
      final range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null) up.headers.set(HttpHeaders.rangeHeader, range);
      final res = await up.close();
      req.response.statusCode = res.statusCode;
      for (final h in const [
        HttpHeaders.contentRangeHeader,
        HttpHeaders.contentTypeHeader,
      ]) {
        final v = res.headers.value(h);
        if (v != null) req.response.headers.set(h, v);
      }
      req.response.headers
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.connectionHeader, 'keep-alive');
      if (res.contentLength >= 0) {
        req.response.contentLength = res.contentLength;
      }
      if (req.method == 'HEAD') {
        await res.drain<void>();
      } else {
        // addStream waits for the PS4 to consume data (no unbounded buffering).
        await req.response.addStream(res.map((chunk) {
          st.served += chunk.length;
          st.last = DateTime.now();
          return chunk;
        }));
      }
    } catch (e) {
      log('Proxy error: $e');
      try {
        req.response.statusCode = 502;
      } catch (_) {}
    } finally {
      try {
        await req.response.close();
      } catch (_) {}
      client.close(force: true);
    }
  }

  /// Checks that the server honours Range requests. Returns the final URL
  /// (after redirects) or null when ranges are not supported.
  static Future<Uri?> _probe(String url) async {
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      var u = Uri.parse(url);
      final req = await c.getUrl(u);
      req.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
      final res = await req.close();
      for (final r in res.redirects) {
        u = u.resolveUri(r.location);
      }
      final ok = res.statusCode == 206;
      await res.drain<void>();
      return ok ? u : null;
    } catch (_) {
      return null;
    } finally {
      c.close(force: true);
    }
  }

  static Future<_Chunk> _fetchChunk(
      HttpClient c, Uri uri, int from, int to) async {
    final want = to - from + 1;
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final req = await c.getUrl(uri);
        req.headers.set(HttpHeaders.rangeHeader, 'bytes=$from-$to');
        final res = await req.close();
        if (res.statusCode != 206) {
          await res.drain<void>();
          throw Exception('HTTP ${res.statusCode} (range not honoured)');
        }
        final b = BytesBuilder(copy: false);
        await for (final d in res) {
          b.add(d);
        }
        final out = b.takeBytes();
        if (out.length != want) {
          throw Exception('short read ${out.length}/$want');
        }
        return _Chunk(out, null);
      } catch (e) {
        last = e;
        await Future<void>.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return _Chunk(null, last ?? Exception('chunk failed'));
  }

  /// Streams bytes [start, end] of [uri] using up to [parallel] concurrent
  /// Range requests of [chunk] bytes, delivered in order. Memory is bounded
  /// by about parallel * chunk bytes.
  static Stream<List<int>> _parallelRange(Uri uri, int start, int end,
      {int chunk = 4 * 1024 * 1024, int parallel = 4}) async* {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..autoUncompress = false
      ..maxConnectionsPerHost = parallel + 1;
    try {
      final total = end - start + 1;
      final n = (total + chunk - 1) ~/ chunk;
      final inflight = <int, Future<_Chunk>>{};
      var launched = 0;
      for (var i = 0; i < n; i++) {
        while (launched < n && launched < i + parallel) {
          final from = start + launched * chunk;
          final to = math.min(from + chunk - 1, end);
          inflight[launched] = _fetchChunk(client, uri, from, to);
          launched++;
        }
        final c = await inflight.remove(i)!;
        if (c.error != null) throw c.error!;
        final data = c.data!;
        const piece = 256 * 1024;
        for (var o = 0; o < data.length; o += piece) {
          yield Uint8List.sublistView(
              data, o, math.min(o + piece, data.length));
        }
      }
    } finally {
      client.close(force: true);
    }
  }

  /// Serves the package to the PS4 using [_parallelRange].
  static Future<void> _proxyFast(
      HttpRequest req, Uri uri, int size, _Stats st, Log log) async {
    final r = req.response;
    try {
      final range =
          _parseRange(req.headers.value(HttpHeaders.rangeHeader), size);
      if (range == null) {
        r.statusCode = 416;
        r.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$size');
        r.contentLength = 0;
        return;
      }
      r.statusCode = range.partial ? 206 : 200;
      r.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.connectionHeader, 'keep-alive');
      if (range.partial) {
        r.headers.set(HttpHeaders.contentRangeHeader,
            'bytes ${range.start}-${range.end}/$size');
      }
      r.contentLength = range.end - range.start + 1;
      r.bufferOutput = false;
      if (req.method != 'HEAD') {
        await r.addStream(
            _parallelRange(uri, range.start, range.end).map((c) {
          st.served += c.length;
          st.last = DateTime.now();
          return c;
        }));
      }
    } catch (e) {
      log('Fast proxy error: $e');
      try {
        r.statusCode = 502;
      } catch (_) {}
    } finally {
      try {
        await r.close();
      } catch (_) {}
    }
  }

  /// Reads a file range in 1 MiB blocks (fewer, bigger writes than openRead).
  static Stream<List<int>> _fileChunks(String path, int start, int end) async* {
    final raf = await File(path).open();
    try {
      var pos = start;
      while (pos <= end) {
        final n = math.min(1024 * 1024, end - pos + 1);
        await raf.setPosition(pos);
        final b = await raf.read(n);
        if (b.isEmpty) break;
        pos += b.length;
        yield b;
      }
    } finally {
      await raf.close();
    }
  }

  /// Serves a local file with Content-Length and Range support.
  static Future<void> _serveFile(
      HttpRequest req, String path, _Stats st, Log log) async {
    final r = req.response;
    try {
      final file = File(path);
      final len = await file.length();
      final range = _parseRange(req.headers.value(HttpHeaders.rangeHeader), len);
      if (range == null) {
        r.statusCode = 416;
        r.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$len');
        r.contentLength = 0;
        return;
      }
      r.statusCode = range.partial ? 206 : 200;
      r.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/octet-stream')
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set(HttpHeaders.connectionHeader, 'keep-alive');
      if (range.partial) {
        r.headers.set(HttpHeaders.contentRangeHeader,
            'bytes ${range.start}-${range.end}/$len');
      }
      r.contentLength = range.end - range.start + 1;
      r.bufferOutput = false;
      if (req.method != 'HEAD') {
        await r.addStream(_fileChunks(path, range.start, range.end).map((c) {
          st.served += c.length;
          st.last = DateTime.now();
          return c;
        }));
      }
    } catch (e) {
      log('File serve error: $e');
      try {
        r.statusCode = 500;
      } catch (_) {}
    } finally {
      try {
        await r.close();
      } catch (_) {}
    }
  }

  /// Serves bytes with an explicit Content-Length (no chunked encoding,
  /// which the PS4 downloader may not handle) and basic Range support.
  static Future<void> _serveBytes(
      HttpRequest req, List<int> data, String type) async {
    final r = req.response;
    final range =
        _parseRange(req.headers.value(HttpHeaders.rangeHeader), data.length);
    if (range == null) {
      r.statusCode = 416;
      r.headers.set(HttpHeaders.contentRangeHeader, 'bytes */${data.length}');
      r.contentLength = 0;
      await r.close();
      return;
    }
    r.statusCode = range.partial ? 206 : 200;
    r.headers
      ..set(HttpHeaders.contentTypeHeader, type)
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.connectionHeader, 'keep-alive');
    if (range.partial) {
      r.headers.set(HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.end}/${data.length}');
    }
    r.contentLength = range.end - range.start + 1;
    if (req.method != 'HEAD') {
      r.add(data.sublist(range.start, range.end + 1));
    }
    await r.close();
  }

  // ---------------------------------------------------------------------
  // PS4 side

  static Future<Socket> _next(StreamIterator<Socket> it, Duration t) async {
    final ok = await it.moveNext().timeout(t);
    if (!ok) throw Exception('Connection closed');
    return it.current;
  }

  static Future<void> _sendPayload(
      String ps4Ip, String phoneIp, int port, Log log) async {
    final data = Uint8List.fromList(
        (await rootBundle.load('assets/payload.bin')).buffer.asUint8List());

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
    void u32(int v) => b.add(
        (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
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
