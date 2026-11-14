import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'services/app_state.dart';
import 'services/discovery.dart';
import 'services/keep_alive.dart';
import 'services/native_files.dart';
import 'services/net_check.dart';
import 'services/pkg_info.dart';
import 'services/progress.dart';
import 'services/ps4_sender.dart';
import 'services/share_intake.dart';
import 'services/updater.dart';
import 'settings_page.dart';
import 'store_page.dart';

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
      home: const RootPage(),
    );
  }
}

/// Bottom navigation: Send | Store.
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: appArabic,
      builder: (context, ar, _) => ValueListenableBuilder<int>(
        valueListenable: Bridge.tab,
        builder: (context, tab, _) => Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: IndexedStack(
              index: tab,
              children: const [HomePage(), StorePage()],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => Bridge.tab.value = i,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.send_outlined),
                  selectedIcon: const Icon(Icons.send),
                  label: ar ? 'إرسال' : 'Send',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.storefront_outlined),
                  selectedIcon: const Icon(Icons.storefront),
                  label: ar ? 'المتجر' : 'Store',
                ),
              ],
            ),
          ),
        ),
      ),
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
  int _lastPct = -1;
  List<Map<String, String>> _history = [];
  String? _error;
  bool _hasCellular = false;
  bool _warnedCellular = false;
  DateTime _lastNotif = DateTime.fromMillisecondsSinceEpoch(0);

  String t(String en, String ar) => _ar ? ar : en;

  @override
  void initState() {
    super.initState();
    Ps4Sender.localIp().then((ip) {
      if (mounted) setState(() => _phoneIp = ip);
    });
    Bridge.addUrl.addListener(_onBridge);
    _loadPrefs().then((_) => _initShare());
    NetCheck.hasCellular().then((v) {
      if (mounted) setState(() => _hasCellular = v);
    });
    _clearPickerCache();
    _checkUpdate();
  }

  @override
  void dispose() {
    Bridge.addUrl.removeListener(_onBridge);
    _ps4.dispose();
    _url.dispose();
    super.dispose();
  }

  /// The Store tab asked to add a link to the queue.
  void _onBridge() {
    final u = Bridge.addUrl.value;
    if (u == null) return;
    Bridge.addUrl.value = null;
    if (_sending) {
      _snack(t('Busy sending, try again after it ends.',
          'جارٍ الإرسال، أعد المحاولة بعد انتهائه.'));
      return;
    }
    setState(() {
      _source = Source.link;
      _url.text = u;
    });
    _addLink();
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
        appArabic.value = _ar;
        final raw = p.getString('history');
        if (raw != null) {
          _history = (jsonDecode(raw) as List)
              .map((e) => Map<String, String>.from(e as Map))
              .toList();
        }
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

  // ------------------------------------------------------------ share / paste

  Future<void> _initShare() async {
    ShareIntake.listen(_onShare);
    final m = await ShareIntake.initial();
    if (m != null) await _onShare(m);
  }

  /// A link or files sent from another app with "Share" (Android).
  Future<void> _onShare(Map<dynamic, dynamic> m) async {
    if (_sending) {
      _snack(t('Busy sending, try again after it ends.',
          'جارٍ الإرسال، أعد المحاولة بعد انتهائه.'));
      return;
    }
    final text = (m['text'] ?? '') as String;
    final files = (m['files'] as List?) ?? const [];
    final links = RegExp(r'https?://\S+')
        .allMatches(text)
        .map((x) => x.group(0)!)
        .toSet()
        .toList();
    if (links.isEmpty && files.isEmpty) return;
    _snack(t('Adding shared items…', 'جارٍ إضافة العناصر المشاركة…'));
    if (links.isNotEmpty) {
      setState(() {
        _source = Source.link;
        _url.text = links.first;
      });
      for (final l in links) {
        if (_queue.any((p) => p.url == l)) continue;
        final pkg = await _read(() => PkgReader.readUrl(l));
        if (pkg != null) _rememberLink(pkg);
      }
      _save();
    }
    if (files.isNotEmpty) {
      setState(() => _source = Source.file);
      for (final f in files) {
        final fm = Map<String, dynamic>.from(f as Map);
        final uri = fm['uri'] as String;
        final size = ((fm['size'] ?? 0) as num).toInt();
        await _read(() => PkgReader.readContent(uri, size));
      }
    }
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final m = RegExp(r'https?://\S+').firstMatch(d?.text ?? '');
    if (m == null) {
      _snack(t('No link in the clipboard', 'لا يوجد رابط في الحافظة'));
      return;
    }
    setState(() => _url.text = m.group(0)!);
    _save();
  }

  // ------------------------------------------------------- progress / notify

  ({int total, int done}) _totals() {
    var total = 0;
    var done = 0;
    for (var i = 0; i < _queue.length; i++) {
      final p = _queue[i];
      if (!_viaServer(p)) continue;
      total += p.size;
      done += math.min(i < _served.length ? _served[i] : 0, p.size);
    }
    return (total: total, done: done);
  }

  /// Updates the Android notification (at most once per second).
  void _notifyProgress() {
    final r = _totals();
    if (r.total == 0) return;
    final pct = r.done * 100 ~/ r.total;
    final now = DateTime.now();
    if (now.difference(_lastNotif).inMilliseconds < 1000) return;
    if (pct == _lastPct && now.difference(_lastNotif).inSeconds < 10) return;
    _lastPct = pct;
    _lastNotif = now;
    final eta = _meter.eta(r.total, r.done);
    ForegroundKeeper.progress(pct, eta == null ? '$pct%' : '$pct% · ${_fmtEta(eta)}');
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

  // ------------------------------------------------------- history / errors

  void _saveHistory() {
    _prefs?.setString('history', jsonEncode(_history));
  }

  void _rememberLink(PkgInfo pkg) {
    final url = pkg.url;
    if (url == null) return;
    setState(() {
      _history.removeWhere((h) => h['url'] == url);
      _history.insert(0, {'url': url, 'title': pkg.title});
      if (_history.length > 30) _history = _history.sublist(0, 30);
    });
    _saveHistory();
  }

  Future<void> _showHistory() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Directionality(
            textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: Text(t('Recent links', 'الروابط الأخيرة'),
                      style: Theme.of(ctx).textTheme.titleMedium),
                  trailing: _history.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () {
                            setState(() => _history = []);
                            _saveHistory();
                            setSheet(() {});
                          },
                          child: Text(t('Clear all', 'مسح الكل')),
                        ),
                ),
                if (_history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(t('No saved links yet.', 'لا توجد روابط محفوظة بعد.')),
                  )
                else
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final h in _history)
                          ListTile(
                            leading: const Icon(Icons.history),
                            title: Text(h['title'] ?? h['url'] ?? '',
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(h['url'] ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr),
                            onTap: () {
                              Navigator.pop(ctx);
                              _url.text = h['url'] ?? '';
                              _addLink();
                            },
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () {
                                setState(() => _history.remove(h));
                                _saveHistory();
                                setSheet(() {});
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Turns a failure into a clear message in the current language.
  String _explain(Object e) {
    if (e is PkgError) {
      switch (e.code) {
        case 'invalid_url':
          return t('This is not a valid link. It must start with http:// or https://.',
              'هذا ليس رابطاً صالحاً. يجب أن يبدأ بـ http:// أو https://.');
        case 'html_page':
          return t('The link opens a web page, not the PKG file. Use the direct download link.',
              'الرابط يفتح صفحة ويب وليس ملف PKG. استخدم رابط التحميل المباشر.');
        case 'forbidden':
          return t('The server refused access (the link expired or needs a login). Get a fresh link.',
              'السيرفر رفض الوصول (انتهت صلاحية الرابط أو يحتاج تسجيل دخول). احصل على رابط جديد.');
        case 'not_found':
          return t('The file was not found (404). Check the link.',
              'الملف غير موجود (404). تحقق من الرابط.');
        case 'server_error':
          return t('The server returned an error (${e.detail}). Try again later.',
              'السيرفر أرجع خطأ (${e.detail}). حاول لاحقاً.');
        case 'no_size':
          return t('The server did not report the file size, so it cannot be used.',
              'السيرفر لم يرسل حجم الملف، فلا يمكن استخدامه.');
        case 'archive':
          return t('This is a compressed archive (${e.detail}). Extract it and use the .pkg file.',
              'هذا ملف مضغوط (${e.detail}). فك الضغط واستخدم ملف .pkg.');
        case 'not_pkg':
          return t('This is not a PS4 PKG file (${e.detail}).',
              'هذا ليس ملف PS4 PKG (${e.detail}).');
      }
    }
    if (e is SocketException) {
      return t('Cannot reach the server. Check the internet connection and the link.',
          'تعذّر الاتصال بالسيرفر. تحقق من الإنترنت ومن الرابط.');
    }
    if (e is TimeoutException) {
      return t('The connection timed out.', 'انتهت مهلة الاتصال.');
    }
    if (e is TlsException) {
      return t('There is a problem with the HTTPS certificate of this site.',
          'توجد مشكلة في شهادة HTTPS لهذا الموقع.');
    }
    return e.toString();
  }

  /// Same for failures while sending to the PS4.
  String _explainSend(Object e) {
    final s = e.toString();
    if (s.contains('Could not reach BinLoader')) {
      return t('Cannot reach the PS4. Enable GoldHEN > Servers > BinLoader and check the IP.',
          'تعذّر الوصول إلى الـ PS4. فعّل GoldHEN > Servers > BinLoader وتحقق من العنوان.');
    }
    if (e is TimeoutException) {
      return t('The PS4 payload did not connect back to the phone. Make sure both are on the same Wi-Fi and that the router does not isolate devices (AP isolation).',
          'الـ payload على الـ PS4 لم يتصل بالجوال. تأكد أنهما على نفس الواي فاي وأن الراوتر لا يعزل الأجهزة (AP isolation).');
    }
    return _explain(e);
  }

  /// Checks before sending. Returns false when the user cancels.
  Future<bool> _preflight(String phone, String ps4) async {
    if (!NetCheck.validIpv4(ps4)) {
      _snack(t('The PS4 IP is not valid (example: 192.168.1.20).',
          'عنوان الـ PS4 غير صالح (مثال: 192.168.1.20).'));
      return false;
    }
    final warns = <String>[];
    if (!NetCheck.sameLan(phone, ps4)) {
      warns.add(t(
          'The phone ($phone) and the PS4 ($ps4) look like they are on different networks. Both must be on the same Wi-Fi.',
          'الجوال ($phone) والـ PS4 ($ps4) يبدوان على شبكتين مختلفتين. يجب أن يكونا على نفس الواي فاي.'));
    }
    final cell = await NetCheck.hasCellular();
    if (mounted) setState(() => _hasCellular = cell);
    final proxiedLinks = _proxy && _queue.any((p) => !p.isLocal);
    if (proxiedLinks && cell && !_warnedCellular) {
      warns.add(t(
          'The download goes through this phone. If the Wi-Fi has no internet it may use your mobile data plan.',
          'التحميل يمر عبر هذا الجوال. إذا كان الواي فاي بدون إنترنت فقد يستهلك من باقة بيانات الجوال.'));
    }
    if (warns.isEmpty) return true;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(t('Before sending', 'قبل الإرسال')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final w in warns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $w'),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('Send anyway', 'إرسال على أي حال')),
            ),
          ],
        ),
      ),
    );
    if (go == true) _warnedCellular = true;
    return go ?? false;
  }

  // ------------------------------------------------------------------ queue

  Future<PkgInfo?> _read(Future<PkgInfo> Function() read) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pkg = await read();
      if (!mounted) return null;
      setState(() => _queue.add(pkg));
      _log('Added: ${pkg.title} (${pkg.contentId}), ${pkg.size} bytes');
      if (!pkg.rangeOk && !pkg.isLocal) {
        _log('Note: this server does not support resume (fast mode will not work for it).');
      }
      return pkg;
    } catch (e) {
      _log('Load failed: $e');
      if (mounted) setState(() => _error = _explain(e));
      return null;
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
    final pkg = await _read(() => PkgReader.readUrl(url));
    if (pkg != null) _rememberLink(pkg);
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

  void _removeAt(int i) => setState(() {
        _queue.removeAt(i);
        _served = [];
      });

  void _reorder(int oldIndex, int newIndex) {
    if (_sending) return;
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _queue.removeAt(oldIndex);
      _queue.insert(newIndex, item);
      _served = [];
    });
  }

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
    if (!await _preflight(phone, ps4)) return;
    _save();
    final ctl = SendController();
    _ctl = ctl;
    _meter = SpeedMeter();
    _lastPct = -1;
    _lastNotif = DateTime.fromMillisecondsSinceEpoch(0);
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
          _notifyProgress();
        },
      );
    } catch (e) {
      _log('Install failed: $e');
      if (mounted) setState(() => _error = _explainSend(e));
    } finally {
      await ForegroundKeeper.stop();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      final r = _totals();
      if (!ctl.cancelled && r.total > 0 && r.done >= r.total) {
        await ForegroundKeeper.finished(
            t('Transfer complete', 'اكتمل النقل'));
      }
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
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _removeAt(i),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(Icons.drag_handle),
                        ),
                      ),
                    ],
                  ),
          ),
          if (!p.isLocal && !p.rangeOk)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  '⚠ ${t('No resume support on this server (no fast mode)', 'السيرفر لا يدعم الاستئناف (بدون الوضع السريع)')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
    final totals = _totals();
    final total = totals.total;
    final done = totals.done;
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
                appArabic.value = _ar;
                _save();
              },
              child: Text(_ar ? 'EN' : 'ع'),
            ),
          ],
        ),
        body: SafeArea(
          bottom: false,
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
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: t('Recent links', 'الروابط الأخيرة'),
                          icon: const Icon(Icons.history),
                          onPressed: _sending ? null : _showHistory,
                        ),
                        IconButton(
                          tooltip: t('Paste', 'لصق'),
                          icon: const Icon(Icons.content_paste),
                          onPressed: _sending ? null : _paste,
                        ),
                      ],
                    ),
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
                if (_proxy && _hasCellular)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      t('Note: the proxy uses this phone internet. If the Wi-Fi has no internet it may use your mobile data plan.',
                          'ملاحظة: الـ Proxy يستخدم إنترنت هذا الجوال. إذا كان الواي فاي بدون إنترنت فقد يستهلك من باقة بياناتك.'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Card(
                    color: cs.errorContainer,
                    child: ListTile(
                      leading: Icon(Icons.error_outline, color: cs.onErrorContainer),
                      title: Text(_error!,
                          style: TextStyle(color: cs.onErrorContainer)),
                      trailing: IconButton(
                        icon: Icon(Icons.close, color: cs.onErrorContainer),
                        onPressed: () => setState(() => _error = null),
                      ),
                    ),
                  ),
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
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: _reorder,
                  children: [
                    for (var i = 0; i < _queue.length; i++)
                      KeyedSubtree(
                        key: ObjectKey(_queue[i]),
                        child: _queueTile(i, cs),
                      ),
                  ],
                ),
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
