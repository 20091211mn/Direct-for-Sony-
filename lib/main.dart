import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/discovery.dart';
import 'services/keep_alive.dart';
import 'services/native_files.dart';
import 'services/pkg_info.dart';
import 'services/progress.dart';
import 'services/ps4_sender.dart';
import 'services/updater.dart';
import 'settings_page.dart';

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

/// Keeps only digits and dots. The iPhone number pad has no "." key (or shows
/// a locale separator), so ",", "٫", "،" become "." and Arabic digits become 0-9.
class _IpFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final src = newValue.text;
    final sel = newValue.selection.baseOffset;
    final out = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < src.length; i++) {
      if (i == sel) cursor = out.length;
      final c = src.codeUnitAt(i);
      if (c >= 0x30 && c <= 0x39) {
        out.writeCharCode(c);
      } else if (c >= 0x0660 && c <= 0x0669) {
        out.writeCharCode(0x30 + c - 0x0660);
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        out.writeCharCode(0x30 + c - 0x06F0);
      } else if (c == 0x2E ||
          c == 0x2C ||
          c == 0x066B ||
          c == 0x060C ||
          c == 0x3002 ||
          c == 0xFF0C) {
        out.write('.');
      }
    }
    if (sel < 0 || sel >= src.length) cursor = out.length;
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: math.min(cursor, text.length)),
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
  final _queue = <PkgInfo>[];

  Source _source = Source.link;
  String? _phoneIp;
  bool _loading = false;
  bool _sending = false;
  bool _scanning = false;
  bool _proxy = true;
  bool _fast = true;
  bool _ar = true;
  List<int> _served = [];
  SpeedMeter _meter = SpeedMeter();
  SendController? _ctl;
  UpdateInfo? _update;
  SharedPreferences? _prefs;

  String t(String en, String ar) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    Ps4Sender.localIp().then((ip) {
      if (mounted) setState(() => _phoneIp = ip);
    });
    _loadPrefs();
    _clearPickerCache();
    _checkUpdate();
  }

  @override
  void dispose() {
    _ps4.dispose();
    _url.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- storage

  Future<void> _loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      if (!mounted) return;
      setState(() {
        _ps4.text = p.getString('ps4_ip') ?? '';
        _url.text = p.getString('last_url') ?? '';
        _ar = p.getBool('ar') ?? true;
        _proxy = p.getBool('proxy') ?? true;
        _fast = p.getBool('fast') ?? true;
        _source = p.getString('source') == 'file' ? Source.file : Source.link;
      });
    } catch (_) {}
  }

  void _save() {
    final p = _prefs;
    if (p == null) return;
    p.setString('ps4_ip', _ps4.text.trim());
    p.setString('last_url', _url.text.trim());
    p.setBool('ar', _ar);
    p.setBool('proxy', _proxy);
    p.setBool('fast', _fast);
    p.setString('source', _source == Source.file ? 'file' : 'link');
  }

  Future<void> _clearPickerCache() async {
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
  }

  // ---------------------------------------------------------------- updates

  Future<void> _checkUpdate() async {
    try {
      final u = await Updater.check();
      if (mounted) setState(() => _update = u);
    } catch (_) {}
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(ar: _ar, update: _update),
    ));
  }

  // ------------------------------------------------------------------- misc

  void _log(String m) {
    if (mounted) setState(() => _logs.add(m));
  }

  bool _viaServer(PkgInfo p) => p.isLocal || _proxy;

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

  // -------------------------------------------------------------- PS4 finder

  Future<void> _scan() async {
    final phone = _phoneIp;
    if (phone == null) {
      _log('No Wi-Fi IP found. Connect to the same network as the PS4.');
      return;
    }
    setState(() => _scanning = true);
    _log('Scanning the network for BinLoader (port 9090)...');
    final found = await Discovery.scan(phone);
    if (!mounted) return;
    setState(() => _scanning = false);
    if (found.isEmpty) {
      _log('No PS4 found. Enable GoldHEN > Servers > BinLoader and use the same Wi-Fi.');
      _snack(t('No PS4 found', 'لم يتم العثور على PS4'));
      return;
    }
    String? chosen = found.first;
    if (found.length > 1) {
      chosen = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(t('Choose your PS4', 'اختر جهاز الـ PS4')),
          children: [
            for (final h in found)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, h),
                child: Text(h),
              ),
          ],
        ),
      );
    }
    final ip = chosen;
    if (ip == null || !mounted) return;
    setState(() => _ps4.text = ip);
    _save();
    _log('PS4 found: $ip');
    _snack(t('PS4 found: $ip', 'تم العثور على PS4: $ip'));
  }

  Future<void> _test() async {
    final ip = _ps4.text.trim();
    if (ip.isEmpty) {
      _snack(t('Enter the PS4 IP first', 'اكتب عنوان الـ PS4 أولاً'));
      return;
    }
    setState(() => _scanning = true);
    final ok = await Discovery.test(ip);
    if (!mounted) return;
    setState(() => _scanning = false);
    _log(ok
        ? 'BinLoader reachable at $ip'
        : 'Cannot reach BinLoader at $ip (enable GoldHEN > Servers > BinLoader)');
    _snack(ok
        ? t('PS4 reachable ✓', 'الـ PS4 متصل ✓')
        : t('Cannot reach the PS4', 'تعذّر الاتصال بالـ PS4'));
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  // ------------------------------------------------------------------ queue

  Future<void> _read(Future<PkgInfo> Function() read) async {
    setState(() => _loading = true);
    try {
      final pkg = await read();
      if (!mounted) return;
      setState(() => _queue.add(pkg));
      _log('Added: ${pkg.title} (${pkg.contentId}), ${pkg.size} bytes');
    } catch (e) {
      _log('Load failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addLink() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    if (_queue.any((p) => p.url == url)) {
      _snack(t('Already in the queue', 'موجود في القائمة'));
      return;
    }
    _save();
    await _read(() => PkgReader.readUrl(url));
  }

  Future<void> _addFiles() async {
    try {
      if (Platform.isAndroid) {
        final files = await NativeFiles.pick();
        for (final f in files) {
          await _read(() => PkgReader.readContent(f.uri, f.size));
        }
      } else {
        final res = await FilePicker.platform
            .pickFiles(type: FileType.any, allowMultiple: true);
        if (res == null) return;
        for (final f in res.files) {
          final path = f.path;
          if (path != null) await _read(() => PkgReader.readFile(path));
        }
      }
    } catch (e) {
      _log('Pick failed: $e');
    }
  }

  void _removeAt(int i) => setState(() => _queue.removeAt(i));

  Future<void> _clearQueue() async {
    setState(() {
      _queue.clear();
      _served = [];
    });
    await NativeFiles.release();
    await _clearPickerCache();
  }

  // ---------------------------------------------------------------- sending

  Future<void> _install() async {
    final phone = _phoneIp;
    final ps4 = _ps4.text.trim();
    if (_queue.isEmpty) return;
    if (phone == null) {
      _log('No Wi-Fi IP found. Connect to the same network as the PS4.');
      return;
    }
    if (ps4.isEmpty) {
      _log('Enter the PS4 IP first.');
      _snack(t('Enter the PS4 IP first', 'اكتب عنوان الـ PS4 أولاً'));
      return;
    }
    _save();
    final ctl = SendController();
    _ctl = ctl;
    _meter = SpeedMeter();
    final pkgs = List<PkgInfo>.of(_queue);
    setState(() {
      _sending = true;
      _served = List<int>.filled(pkgs.length, 0);
    });
    await ForegroundKeeper.start();
    try {
      await WakelockPlus.enable();
    } catch (_) {}
    try {
      await Ps4Sender.send(
        ps4Ip: ps4,
        phoneIp: phone,
        pkgs: pkgs,
        proxy: _proxy,
        fast: _fast,
        controller: ctl,
        log: _log,
        onProgress: (served) {
          _meter.add(served.fold<int>(0, (a, b) => a + b));
          if (mounted) setState(() => _served = served);
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

  // ------------------------------------------------------------------- views

  Widget _queueTile(int i, ColorScheme cs) {
    final p = _queue[i];
    final served = i < _served.length ? _served[i] : 0;
    final showBar = (_sending || served > 0) && _viaServer(p);
    return Card(
      color: cs.surfaceContainerHigh,
      child: Column(
        children: [
          ListTile(
            leading: p.icon == null
                ? const Icon(Icons.inventory_2, size: 40)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(p.icon!, width: 48, height: 48),
                  ),
            title: Text(p.title),
            subtitle:
                Text('${p.contentId}\n${p.bgftType} · ${_fmtSize(p.size)}'),
            isThreeLine: true,
            trailing: _sending
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => _removeAt(i),
                  ),
          ),
          if (showBar)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: LinearProgressIndicator(
                value: p.size == 0 ? 0 : math.min(served, p.size) / p.size,
              ),
            ),
        ],
      ),
    );
  }

  Widget _progressCard(ColorScheme cs) {
    var total = 0;
    var done = 0;
    for (var i = 0; i < _queue.length; i++) {
      final p = _queue[i];
      if (!_viaServer(p)) continue;
      total += p.size;
      done += math.min(i < _served.length ? _served[i] : 0, p.size);
    }
    if (total == 0) {
      return Card(
        color: cs.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(t(
              'The PS4 downloads directly from the links, so no progress is available here.',
              'الـ PS4 يحمّل مباشرة من الروابط، لذلك لا يمكن عرض النسبة هنا.')),
        ),
      );
    }
    final frac = done / total;
    final eta = _meter.eta(total, done);
    final speed = _meter.bytesPerSecond;
    final String etaText;
    if (done >= total) {
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
            Text(etaText, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final busy = _loading || _sending || _scanning;
    return Directionality(
      textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PS4 Sender'),
          actions: [
            IconButton(
              tooltip: t('Settings', 'الإعدادات'),
              icon: Badge(
                isLabelVisible: _update != null,
                child: const Icon(Icons.settings),
              ),
              onPressed: _openSettings,
            ),
            TextButton(
              onPressed: () {
                setState(() => _ar = !_ar);
                _save();
              },
              child: Text(_ar ? 'EN' : 'ع'),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_update != null && !_sending)
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.system_update),
                    title: Text(
                        '${t('New version available', 'يوجد إصدار جديد')}: ${_update!.tag}'),
                    trailing: FilledButton(
                      onPressed: _openSettings,
                      child: Text(t('Update', 'تحديث')),
                    ),
                  ),
                ),
              Text(
                '${t('Phone IP', 'IP الجوال')}: ${_phoneIp ?? t('not found', 'غير موجود')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _ps4,
                enabled: !_sending,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [_IpFormatter()],
                textDirection: TextDirection.ltr,
                onChanged: (_) => _save(),
                decoration: InputDecoration(
                  labelText: t('PS4 IP', 'عنوان الـ PS4'),
                  hintText: '192.168.1.20',
                  prefixIcon: const Icon(Icons.sports_esports),
                  suffixIcon: _scanning
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: t('Find my PS4', 'ابحث عن الـ PS4'),
                              icon: const Icon(Icons.radar),
                              onPressed: busy ? null : _scan,
                            ),
                            IconButton(
                              tooltip: t('Test connection', 'اختبار الاتصال'),
                              icon: const Icon(Icons.wifi_tethering),
                              onPressed: busy ? null : _test,
                            ),
                          ],
                        ),
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
                    : (s) {
                        setState(() => _source = s.first);
                        _save();
                      },
              ),
              const SizedBox(height: 12),
              if (_source == Source.link) ...[
                TextField(
                  controller: _url,
                  enabled: !_sending,
                  keyboardType: TextInputType.url,
                  textDirection: TextDirection.ltr,
                  onChanged: (_) => _save(),
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
                  onChanged: busy
                      ? null
                      : (v) {
                          setState(() => _proxy = v);
                          _save();
                        },
                ),
                if (_proxy)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t('Fast mode (parallel connections)',
                        'وضع سريع (اتصالات متوازية)')),
                    subtitle: Text(t(
                        'Faster with slow servers. Turn off if the download fails.',
                        'أسرع مع السيرفرات البطيئة. أطفئه إذا فشل التحميل.')),
                    value: _fast,
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() => _fast = v);
                            _save();
                          },
                  ),
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _addLink,
                  icon: const Icon(Icons.playlist_add),
                  label: Text(t('Add to queue', 'إضافة إلى القائمة')),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: busy ? null : _addFiles,
                  icon: const Icon(Icons.upload_file),
                  label: Text(t('Add PKG files', 'إضافة ملفات PKG')),
                ),
                const SizedBox(height: 6),
                Text(
                  Platform.isAndroid
                      ? t('Files are read directly from storage (no copy).',
                          'الملفات تُقرأ مباشرة من التخزين (بدون نسخ).')
                      : t('On iPhone the system gives the app a copy of the file, so free storage is needed.',
                          'على الآيفون يعطي النظام التطبيق نسخة من الملف، فيلزم مساحة فارغة.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (_queue.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: Text(
                      '${t('Queue', 'قائمة الانتظار')} (${_queue.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (!_sending)
                    TextButton.icon(
                      onPressed: busy ? null : _clearQueue,
                      icon: const Icon(Icons.delete_sweep),
                      label: Text(t('Clear', 'مسح الكل')),
                    ),
                ]),
                for (var i = 0; i < _queue.length; i++) _queueTile(i, cs),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy ? null : _install,
                      icon: const Icon(Icons.download),
                      label: Text(_queue.length > 1
                          ? t('Install all (${_queue.length})',
                              'تثبيت الكل (${_queue.length})')
                          : t('Install', 'تثبيت')),
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
                if (_sending || _served.any((b) => b > 0)) ...[
                  const SizedBox(height: 12),
                  _progressCard(cs),
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
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
