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
import 'services/explain.dart';
import 'services/keep_alive.dart';
import 'services/native_files.dart';
import 'services/net_check.dart';
import 'services/notify_bridge.dart';
import 'services/pkg_info.dart';
import 'services/progress.dart';
import 'services/ps4_sender.dart';
import 'services/share_intake.dart';
import 'services/store_catalog.dart';
import 'services/updater.dart';
import 'settings_page.dart';
import 'util/brand.dart';
import 'util/format.dart';
import 'util/legal.dart';
import 'util/ip_formatter.dart';
import 'widgets/notification_bell.dart';
import 'widgets/progress_card.dart';
import 'widgets/queue_tile.dart';

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
    _loadPrefs().then((_) async {
      await _maybeShowTerms();
      await _initShare();
    });
    NetCheck.hasCellular().then((v) {
      if (mounted) setState(() => _hasCellular = v);
    });
    _clearPickerCache();
    appUpdate.addListener(_rebuild);
    refreshNotifications();
    _startupChecks();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// First launch: the disclaimer must be accepted once.
  Future<void> _maybeShowTerms() async {
    final p = _prefs;
    if (p == null || !mounted) return;
    if (p.getBool('terms_accepted') ?? false) return;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Directionality(
          textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
          child: AlertDialog(
            title: Text(t('Before you start', 'قبل أن تبدأ')),
            content: SingleChildScrollView(child: Text(disclaimerText(_ar))),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t('Exit', 'خروج')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(t('I agree', 'أوافق')),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      await p.setBool('terms_accepted', true);
    } else {
      SystemNavigator.pop();
    }
  }

  void _onSendWarning(String code) {
    if (!mounted) return;
    if (code == 'ip_changed') {
      setState(() => _error = t(
          'The phone address changed during the transfer (the Wi-Fi probably dropped and came back). The PS4 cannot finish the download from the old address. Press Stop and send again.',
          'تغيّر عنوان الجوال أثناء الإرسال (غالباً انقطع الواي فاي وعاد بعنوان جديد). الـ PS4 لا يستطيع إكمال التحميل من العنوان القديم. اضغط إيقاف ثم أرسل من جديد.'));
    } else if (code == 'waiting') {
      _snack(t('Waiting for the PS4 to continue the download…',
          'بانتظار أن يكمل الـ PS4 التحميل…'));
    }
  }

  /// Did the last update attempt work? Show what is new, or explain the failure.
  Future<void> _startupChecks() async {
    final outcome = await Updater.reconcile();
    if (outcome == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: _ar ? TextDirection.rtl : TextDirection.ltr,
        child: AlertDialog(
          title: Text(outcome.success
              ? '${t('Updated to', 'تم التحديث إلى')} ${outcome.tag}'
              : t('The update was not installed', 'لم يتم تثبيت التحديث')),
          content: SingleChildScrollView(
            child: outcome.success
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (outcome.features.isNotEmpty)
                        Text(t("What's new:", 'الجديد في هذا الإصدار:')),
                      for (final f in outcome.features)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('• $f'),
                        ),
                    ],
                  )
                : Text(t(
                    'If the installer said the app conflicts with an existing package, uninstall the app once and install the new version; updates work automatically after that.',
                    'إذا ظهر في المثبّت أن التطبيق يتعارض مع حزمة موجودة، فاحذف التطبيق مرة واحدة ثم ثبّت النسخة الجديدة؛ بعدها تعمل التحديثات تلقائياً.')),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(t('OK', 'حسناً')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    Bridge.addUrl.removeListener(_onBridge);
    appUpdate.removeListener(_rebuild);
    _ps4.dispose();
    _url.dispose();
    super.dispose();
  }

  /// The Store tab asked to add a link to the queue.
  /// The Store tab asked to add a link (and maybe send it right away).
  Future<void> _onBridge() async {
    final u = Bridge.addUrl.value;
    if (u == null) return;
    Bridge.addUrl.value = null;
    final auto = Bridge.autoSend;
    Bridge.autoSend = false;
    final sid = Bridge.addId;
    final sver = Bridge.addVersion;
    Bridge.addId = null;
    Bridge.addVersion = null;
    if (_sending) {
      _snack(t('Busy sending, try again after it ends.',
          'جارٍ الإرسال، أعد المحاولة بعد انتهائه.'));
      return;
    }
    final wasEmpty = _queue.isEmpty;
    setState(() {
      _source = Source.link;
      _url.text = u;
    });
    final before = _queue.length;
    await _addLink();
    if (sid != null && _queue.length > before) {
      _queue.last.storeId = sid;
      _queue.last.storeVersion = sver;
    }
    if (!auto) return;
    if (wasEmpty && _queue.length == 1) {
      if (_ps4.text.trim().isEmpty) {
        _snack(t('Enter the PS4 IP, then press Install.',
            'اكتب عنوان الـ PS4 ثم اضغط تثبيت.'));
        return;
      }
      await _install();
    } else {
      _snack(t('Added. Press "Install all" to send the queue.',
          'تمت الإضافة. اضغط "تثبيت الكل" لإرسال القائمة.'));
    }
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
        NotifyBridge.schedule(kRepo, _ar);
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

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(ar: _ar, update: appUpdate.value),
    ));
  }

  // ------------------------------------------------------------------- misc

  void _log(String m) {
    if (mounted) setState(() => _logs.add(m));
  }

  bool _viaServer(PkgInfo p) => p.isLocal || _proxy;

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
    ForegroundKeeper.progress(pct, eta == null ? '$pct%' : '$pct% · ${fmtEta(eta, _ar)}');
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
  /// Same for failures while sending to the PS4.
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
      if (mounted) setState(() => _error = explainError(e, _ar));
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
        onWarning: _onSendWarning,
        onProgress: (served) {
          _meter.add(served.fold<int>(0, (a, b) => a + b));
          if (mounted) setState(() => _served = served);
          _notifyProgress();
        },
      );
    } catch (e) {
      _log('Install failed: $e');
      if (mounted) setState(() => _error = explainSend(e, _ar));
    } finally {
      await ForegroundKeeper.stop();
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      for (var i = 0; i < pkgs.length; i++) {
        final p = pkgs[i];
        final sid = p.storeId;
        if (!ctl.cancelled &&
            sid != null &&
            p.size > 0 &&
            i < _served.length &&
            _served[i] >= p.size) {
          await StoreInstalled.record(sid, p.storeVersion ?? '');
          Bridge.storeTick.value++;
        }
      }
      final r = _totals();
      if (!ctl.cancelled && r.total > 0 && r.done >= r.total) {
        await ForegroundKeeper.finished(
            t('Transfer complete', 'اكتمل النقل'));
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  // ------------------------------------------------------------------- views

  Widget _progressCard() {
    final r = _totals();
    return ProgressCard(
      total: r.total,
      done: r.done,
      speed: _meter.bytesPerSecond,
      eta: _meter.eta(r.total, r.done),
      ar: _ar,
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
          title: const Text(kAppName),
          actions: [
            const NotificationBell(),
            IconButton(
              tooltip: t('Settings', 'الإعدادات'),
              icon: Badge(
                isLabelVisible: appUpdate.value != null,
                child: const Icon(Icons.settings),
              ),
              onPressed: _openSettings,
            ),
            TextButton(
              onPressed: () {
                setState(() => _ar = !_ar);
                appArabic.value = _ar;
                NotifyBridge.schedule(kRepo, _ar);
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
              if (appUpdate.value != null && !_sending)
                Card(
                  color: cs.primaryContainer,
                  child: ListTile(
                    leading: const Icon(Icons.system_update),
                    title: Text(
                        '${t('New version available', 'يوجد إصدار جديد')}: ${appUpdate.value!.tag}'),
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
                inputFormatters: [IpFormatter()],
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
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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
                        child: QueueTile(
                          pkg: _queue[i],
                          index: i,
                          served: i < _served.length ? _served[i] : 0,
                          sending: _sending,
                          viaServer: _viaServer(_queue[i]),
                          ar: _ar,
                          onRemove: () => _removeAt(i),
                        ),
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
                  _progressCard(),
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
