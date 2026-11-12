import 'package:flutter/material.dart';

import 'services/keep_alive.dart';
import 'services/pkg_info.dart';
import 'services/ps4_sender.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PS4 Sender',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6BFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ps4 = TextEditingController();
  final _url = TextEditingController();
  final _logs = <String>[];

  PkgInfo? _pkg;
  String? _phoneIp;
  bool _busy = false;
  bool _proxy = true;

  @override
  void initState() {
    super.initState();
    Ps4Sender.localIp().then((ip) => setState(() => _phoneIp = ip));
  }

  void _log(String m) => setState(() => _logs.add(m));

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _pkg = null;
    });
    try {
      final pkg = await PkgReader.read(_url.text.trim());
      setState(() => _pkg = pkg);
      _log('Loaded: ${pkg.title} (${pkg.contentId})');
    } catch (e) {
      _log('Load failed: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _install() async {
    final pkg = _pkg;
    final phone = _phoneIp;
    if (pkg == null) return;
    if (phone == null) {
      _log('No Wi-Fi IP found. Connect to the same network as the PS4.');
      return;
    }
    setState(() => _busy = true);
    await ForegroundKeeper.start();
    try {
      await Ps4Sender.send(
        ps4Ip: _ps4.text.trim(),
        phoneIp: phone,
        pkg: pkg,
        proxy: _proxy,
        log: _log,
      );
    } catch (e) {
      _log('Install failed: $e');
    } finally {
      await ForegroundKeeper.stop();
      setState(() => _busy = false);
    }
  }

  String _fmtSize(int b) {
    const u = ['B', 'KB', 'MB', 'GB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 2)} ${u[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pkg = _pkg;
    return Scaffold(
      appBar: AppBar(title: const Text('PS4 Sender')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Phone IP: ${_phoneIp ?? 'not found'}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: _ps4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PS4 IP',
                hintText: '192.168.1.20',
                prefixIcon: Icon(Icons.sports_esports),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Direct PKG URL',
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Proxy download via phone'),
              subtitle: const Text(
                  'Needed for HTTPS links and redirects. Keep the app open.'),
              value: _proxy,
              onChanged: _busy ? null : (v) => setState(() => _proxy = v),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.search),
                  label: const Text('Load'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_busy || pkg == null) ? null : _install,
                  icon: const Icon(Icons.download),
                  label: const Text('Install'),
                ),
              ),
            ]),
            if (_busy) const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
            if (pkg != null) ...[
              const SizedBox(height: 16),
              Card(
                color: cs.surfaceContainerHigh,
                child: ListTile(
                  leading: pkg.icon == null
                      ? const Icon(Icons.inventory_2, size: 40)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(pkg.icon!, width: 56, height: 56),
                        ),
                  title: Text(pkg.title),
                  subtitle: Text(
                      '${pkg.contentId}\n${pkg.bgftType} · ${_fmtSize(pkg.size)}'),
                  isThreeLine: true,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text('Log', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _logs.isEmpty ? '—' : _logs.join('\n'),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
