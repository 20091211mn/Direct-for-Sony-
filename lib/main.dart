import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/keep_alive.dart';
import 'services/pkg_info.dart';
import 'services/progress.dart';
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

enum Source { link, file }

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ps4 = TextEditingController();
  final _url = TextEditingController();
  final _logs = <String>[];

  Source _source = Source.link;
  PkgInfo? _pkg;
  String? _phoneIp;
  bool _loading = false;
  bool _sending = false;
  bool _proxy = true;
  bool _ar = true;
  int _served = 0;
  SpeedMeter _meter = SpeedMeter();
  SendController? _ctl;

  String t(String en, String ar) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    Ps4Sender.localIp().then((ip) {
      if (mounted) setState(() => _phoneIp = ip);
    });
    _clearPickerCache();
  }

  @override
  void dispose() {
    _ps4.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _clearPickerCache() async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
  }

  void _log(String m) {
    if (mounted) setState(() => _logs.add(m));
  }

  Future<void> _readInfo(Future<PkgInfo> Function() read) async {
    setState(() {
      _loading = true;
      _pkg = null;
      _served = 0;
    });
    try {
      final pkg = await read();
      if (mounted) setState(() => _pkg = pkg);
      _log('Loaded: ${pkg.title} (${pkg.contentId})');
      _log('Size: ${pkg.size} bytes, digest: ${pkg.digest.substring(0, 16)}...');
    } catch (e) {
      _log('Load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    await _readInfo(() => PkgReader.readUrl(url));
  }

  Future<void> _pick() async {
    try {
      await _clearPickerCache();
      final res = await FilePicker.platform.pickFiles(type: FileType.any);
      final path = res?.files.single.path;
      if (path == null) return;
      await _readInfo(() => PkgReader.readFile(path));
    } catch (e) {
      _log('Pick failed: $e');
    }
  }

  Future<void> _install() async {
    final pkg = _pkg;
    final phone = _phoneIp;
    final ps4 = _ps4.text.trim();
    if (pkg == null) return;
    if (phone == null) {
      _log('No Wi-Fi IP found. Connect to the same network as the PS4.');
      return;
    }
    if (ps4.isEmpty) {
      _log('Enter the PS4 IP first.');
      return;
    }
    final ctl = SendController();
    _ctl = ctl;
    _meter = SpeedMeter();
    setState(() {
      _sending = true;
      _served = 0;
    });
    await ForegroundKeeper.start();
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      await Ps4Sender.send(
        ps4Ip: ps4,
        phoneIp: phone,
        pkg: pkg,
        proxy: _proxy,
        controller: ctl,
        log: _log,
        onProgress: (n) {
          _meter.add(n);
          if (mounted) setState(() => _served = n);
        },
      );
    } catch (e) {
      _log('Install failed: $e');
    } finally {
      await ForegroundKeeper.stop();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      if (mounted) setState(() => _sending = false);
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

  String _fmtEta(Duration d) {
    if (d.inSeconds < 60) {
      return t('Less than a minute left', 'متبقي أقل من دقيقة');
    }
    final m = (d.inSeconds / 60).ceil();
    if (m < 60) return t('About $m min left', 'متبقي حوالي $m دقيقة');
    final h = m ~/ 60;
    final mm = m % 60;
    return t('About $h h $mm min left', 'متبقي حوالي $h ساعة و$mm دقيقة');
  }

  Widget _progressCard(PkgInfo pkg, ColorScheme cs) {
    final total = pkg.size;
    final direct = pkg.localPath == null && !_proxy;
    if (direct) {
      return Card(
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(t(
              'The PS4 downloads directly from the link, so no progress is available here.',
              'الـ PS4 يحمّل مباشرة من الرابط، لذلك لا يمكن عرض النسبة هنا.')),
        ),
      );
    }
    final done = math.min(_served, total);
    final frac = total == 0 ? 0.0 : done / total;
    final eta = _meter.eta(total, done);
    final speed = _meter.bytesPerSecond;
    final String etaText;
    if (done >= total && total > 0) {
      etaText = t('Transfer complete', 'اكتمل النقل');
    } else if (eta == null) {
      etaText = t('Calculating time left…', 'جارٍ حساب الوقت المتبقي…');
    } else {
      etaText = _fmtEta(eta);
    }
    return Card(
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${(frac * 100).toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: frac,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 8),
            Text('${_fmtSize(done)} / ${_fmtSize(total)}'),
            if (speed > 0)
              Text('${t('Speed', 'السرعة')}: ${_fmtSize(speed.round())}/s'),
            const SizedBox(height: 4),
            Text(etaText,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pkg = _pkg;
    final busy = _loading || _sending;
    return Directionality(
      textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PS4 Sender'),
          actions: [
            TextButton(
              onPressed: () => setState(() => _ar = !_ar),
              child: Text(_ar ? 'EN' : 'ع'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${t('Phone IP', 'IP الجوال')}: ${_phoneIp ?? t('not found', 'غير موجود')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ps4,
                enabled: !_sending,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: t('PS4 IP', 'عنوان الـ PS4'),
                  hintText: '192.168.1.20',
                  prefixIcon: const Icon(Icons.sports_esports),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<Source>(
                segments: [
                  ButtonSegment(
                    value: Source.link,
                    icon: const Icon(Icons.link),
                    label: Text(t('Link', 'رابط')),
                  ),
                  ButtonSegment(
                    value: Source.file,
                    icon: const Icon(Icons.folder_open),
                    label: Text(t('File', 'ملف')),
                  ),
                ],
                selected: {_source},
                onSelectionChanged: busy
                    ? null
                    : (s) => setState(() {
                          _source = s.first;
                          _pkg = null;
                          _served = 0;
                        }),
              ),
              const SizedBox(height: 12),
              if (_source == Source.link) ...[
                TextField(
                  controller: _url,
                  enabled: !_sending,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: t('Direct PKG URL', 'رابط PKG مباشر'),
                    prefixIcon: const Icon(Icons.link),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('Proxy download via phone',
                      'التحميل عبر الجوال (Proxy)')),
                  subtitle: Text(t(
                      'Needed for HTTPS links and redirects. Also enables progress.',
                      'مطلوب لروابط HTTPS والتحويلات، ويُظهر نسبة التقدم.')),
                  value: _proxy,
                  onChanged:
                      busy ? null : (v) => setState(() => _proxy = v),
                ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _load,
                  icon: const Icon(Icons.search),
                  label: Text(t('Read info', 'قراءة المعلومات')),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _pick,
                  icon: const Icon(Icons.upload_file),
                  label: Text(t('Choose PKG file', 'اختيار ملف PKG')),
                ),
                const SizedBox(height: 6),
                Text(
                  t('Large files are first copied to the app cache, so free storage is needed.',
                      'الملفات الكبيرة تُنسخ أولاً إلى ذاكرة التطبيق المؤقتة، فيلزم مساحة فارغة.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_loading)
                const Padding(
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
                            child:
                                Image.memory(pkg.icon!, width: 56, height: 56),
                          ),
                    title: Text(pkg.title),
                    subtitle: Text(
                        '${pkg.contentId}\n${pkg.bgftType} · ${_fmtSize(pkg.size)}'),
                    isThreeLine: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : _install,
                      icon: const Icon(Icons.download),
                      label: Text(t('Install', 'تثبيت')),
                    ),
                  ),
                  if (_sending) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: () => _ctl?.cancel(),
                        icon: const Icon(Icons.stop),
                        label: Text(t('Stop', 'إيقاف')),
                      ),
                    ),
                  ],
                ]),
                if (_sending || _served > 0) ...[
                  const SizedBox(height: 12),
                  _progressCard(pkg, cs),
                ],
              ],
              const SizedBox(height: 16),
              Text(t('Log', 'السجل'),
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  _logs.isEmpty ? '—' : _logs.join('\n'),
                  textDirection: TextDirection.ltr,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
