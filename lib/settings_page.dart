import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/updater.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.ar, this.update});

  final bool ar;
  final UpdateInfo? update;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  UpdateInfo? _update;
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String? _message;

  String t(String en, String ar) => widget.ar ? ar : en;

  @override
  void initState() {
    super.initState();
    _update = widget.update;
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    try {
      final u = await Updater.check();
      if (!mounted) return;
      setState(() {
        _update = u;
        _message =
            u == null ? t('You have the latest version.', 'أنت على آخر إصدار.') : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = e.toString().contains('not_found')
            ? t('Cannot read releases. The repository must be public.',
                'تعذّر قراءة الإصدارات. يجب أن يكون المستودع عاماً (Public).')
            : t('Update check failed: $e', 'فشل التحقق من التحديث: $e');
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _doUpdate() async {
    final url = _update?.apkUrl;
    if (url == null) {
      setState(() => _message = t('This release has no APK.', 'هذا الإصدار لا يحتوي ملف APK.'));
      return;
    }
    setState(() {
      _downloading = true;
      _progress = 0;
      _message = null;
    });
    try {
      final path = await Updater.download(url, (p) {
        if (mounted) setState(() => _progress = p);
      });
      final r = await Updater.install(path);
      if (!mounted) return;
      setState(() {
        _message = r == 'needs_permission'
            ? t('Allow "install unknown apps" for this app, then press Update again.',
                'اسمح بـ "تثبيت التطبيقات غير المعروفة" لهذا التطبيق، ثم اضغط تحديث مرة أخرى.')
            : null;
      });
    } catch (e) {
      if (mounted) setState(() => _message = t('Update failed: $e', 'فشل التحديث: $e'));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _copySource() async {
    await Clipboard.setData(const ClipboardData(text: kSourceUrl));
    if (mounted) setState(() => _message = t('Source link copied.', 'تم نسخ رابط المصدر.'));
  }

  Future<void> _copyIpa() async {
    final url = _update?.ipaUrl ?? _update?.pageUrl ?? '';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) setState(() => _message = t('Link copied.', 'تم نسخ الرابط.'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final u = _update;
    return Directionality(
      textDirection: widget.ar ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(title: Text(t('Settings', 'الإعدادات'))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: Text(t('Version', 'الإصدار')),
                subtitle: Text(kBuildNumber == 0
                    ? t('development build', 'نسخة تطوير')
                    : 'v1.0.$kBuildNumber'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: (_checking || _downloading) ? null : _check,
                icon: const Icon(Icons.system_update),
                label: Text(t('Check for updates', 'التحقق من التحديثات')),
              ),
              if (_checking)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: LinearProgressIndicator(),
                ),
              if (u != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: cs.surfaceContainerHigh,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${t('New version available', 'يوجد إصدار جديد')}: ${u.tag}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (u.notes.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(u.notes),
                        ],
                        const SizedBox(height: 12),
                        if (Platform.isAndroid) ...[
                          if (_downloading) ...[
                            LinearProgressIndicator(
                              value: _progress,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            const SizedBox(height: 6),
                            Text('${(_progress * 100).toStringAsFixed(0)}%'),
                          ] else
                            FilledButton.icon(
                              onPressed: _doUpdate,
                              icon: const Icon(Icons.download),
                              label: Text(t('Update now', 'تحديث الآن')),
                            ),
                        ] else ...[
                          Text(t(
                              'Open SideStore / AltStore, go to My Apps and press Update.',
                              'افتح SideStore أو AltStore ثم "تطبيقاتي" واضغط تحديث.')),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _copyIpa,
                            icon: const Icon(Icons.copy),
                            label: Text(t('Copy download link', 'نسخ رابط التحميل')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (!Platform.isAndroid) ...[
                const SizedBox(height: 24),
                Text(t('One-tap updates on iPhone', 'تحديث بنقرة على الآيفون'),
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 6),
                Text(t(
                    'Add this source once in SideStore / AltStore (Sources > +). New versions then appear in the app and install with one tap.',
                    'أضف هذا المصدر مرة واحدة في SideStore أو AltStore (Sources ثم +). بعدها تظهر الإصدارات الجديدة هناك وتُثبَّت بنقرة.')),
                const SizedBox(height: 8),
                SelectableText(kSourceUrl,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: _copySource,
                  icon: const Icon(Icons.copy),
                  label: Text(t('Copy source link', 'نسخ رابط المصدر')),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Text(_message!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
