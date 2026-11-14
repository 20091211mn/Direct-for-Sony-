import 'package:flutter/material.dart';

import '../services/native_files.dart';
import '../services/pkg_info.dart';
import '../services/store_catalog.dart';
import 'github_api.dart';

enum _Src { link, file }

String _explain(Object e) {
  if (e is PkgError) {
    switch (e.code) {
      case 'invalid_url':
        return 'الرابط غير صالح. يجب أن يبدأ بـ http:// أو https://';
      case 'html_page':
        return 'الرابط يفتح صفحة ويب وليس ملف PKG. استخدم رابط التحميل المباشر.';
      case 'forbidden':
        return 'السيرفر رفض الوصول (انتهت صلاحية الرابط أو يحتاج تسجيل دخول).';
      case 'not_found':
        return 'الملف غير موجود (404).';
      case 'server_error':
        return 'السيرفر أرجع خطأ (${e.detail}).';
      case 'no_size':
        return 'السيرفر لم يرسل حجم الملف.';
      case 'archive':
        return 'هذا ملف مضغوط (${e.detail}). فك الضغط واستخدم ملف .pkg.';
      case 'not_pkg':
        return 'هذا ليس ملف PS4 PKG (${e.detail}).';
    }
  }
  if (e is GithubError) {
    if (e.status == 401) return 'التوكن غير صالح أو انتهت صلاحيته.';
    if (e.status == 403 || e.status == 404) {
      return 'ليس لديك صلاحية الكتابة في المستودع. تأكد أن التوكن فيه صلاحية repo. (${e.message})';
    }
    return e.toString();
  }
  return e.toString();
}

String _slug(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');

class ItemEditor extends StatefulWidget {
  const ItemEditor({super.key, required this.api, this.item});

  final GithubApi api;
  final StoreItem? item;

  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> {
  final _title = TextEditingController();
  final _category = TextEditingController();
  final _version = TextEditingController();
  final _desc = TextEditingController();
  final _url = TextEditingController();

  _Src _src = _Src.link;
  PkgInfo? _info;
  PickedFile? _file;
  bool _reading = false;
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    if (i != null) {
      _title.text = i.title;
      _category.text = i.category;
      _version.text = i.version;
      _desc.text = i.description;
      _url.text = i.url;
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _category, _version, _desc, _url]) {
      c.dispose();
    }
    NativeFiles.release();
    super.dispose();
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

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

  Future<void> _read(Future<PkgInfo> Function() f) async {
    setState(() {
      _reading = true;
      _error = null;
    });
    try {
      final info = await f();
      if (!mounted) return;
      setState(() {
        _info = info;
        if (_title.text.trim().isEmpty) _title.text = info.title;
      });
    } catch (e) {
      if (mounted) setState(() => _error = _explain(e));
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _readLink() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    _file = null;
    await _read(() => PkgReader.readUrl(url));
  }

  Future<void> _pickFile() async {
    try {
      final files = await NativeFiles.pick();
      if (files.isEmpty) return;
      final f = files.first;
      _file = f;
      await _read(() => PkgReader.readContent(f.uri, f.size));
    } catch (e) {
      setState(() => _error = _explain(e));
    }
  }

  Future<void> _publish() async {
    final title = _title.text.trim();
    final existing = widget.item;
    if (title.isEmpty) {
      _snack('اكتب اسم العنصر');
      return;
    }
    if (existing == null && _info == null) {
      _snack('اقرأ الرابط أو اختر ملفاً أولاً');
      return;
    }
    final file = _file;
    if (file != null && file.size >= 2 * 1024 * 1024 * 1024) {
      setState(() => _error =
          'GitHub يقبل ملفات أقل من 2GB. استخدم رابطاً خارجياً لهذا الملف.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = 'جارٍ التحضير…';
    });
    try {
      final api = widget.api;
      var id = existing?.id ?? '';
      if (id.isEmpty) {
        final taken = (await api.loadItems()).map((e) => e.id).toSet();
        var base = _slug(title);
        if (base.isEmpty) base = _slug(_info?.contentId ?? '');
        if (base.isEmpty) base = 'item-${DateTime.now().millisecondsSinceEpoch}';
        id = base;
        for (var n = 2; taken.contains(id); n++) {
          id = '$base-$n';
        }
      }

      var url = existing?.url ?? '';
      var size = existing?.size ?? 0;
      var icon = existing?.icon ?? '';
      final info = _info;
      if (info != null) {
        size = info.size;
        if (file != null) {
          setState(() => _status = 'جارٍ رفع الملف إلى GitHub…');
          final rel = await api.ensureRelease();
          final name = '$id.pkg';
          await api.deleteAsset(rel, name);
          url = await api.uploadAsset(
            rel,
            name,
            file.size,
            contentStream(file.uri, file.size),
            (n) {
              if (mounted) setState(() => _progress = n / file.size);
            },
          );
        } else {
          url = info.url ?? url;
        }
        final png = info.icon;
        if (png != null && png.isNotEmpty) {
          setState(() {
            _status = 'جارٍ رفع الأيقونة…';
            _progress = 0;
          });
          final path = 'store/icons/$id.png';
          final sha = await api.sha(path);
          await api.putFile(path, png, 'store icon: $title', sha: sha);
          icon = 'https://raw.githubusercontent.com/${api.repo}/main/$path';
        }
      }

      setState(() {
        _status = 'جارٍ تحديث المتجر…';
        _progress = 0;
      });
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await api.upsertItem(StoreItem(
        id: id,
        title: title,
        url: url,
        category: _category.text.trim(),
        description: _desc.text.trim(),
        version: _version.text.trim(),
        size: size,
        icon: icon,
        added: existing?.added.isNotEmpty == true ? existing!.added : today,
      ));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = _explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = _info;
    final editing = widget.item != null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? 'تعديل عنصر' : 'إضافة عنصر')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<_Src>(
              segments: const [
                ButtonSegment(
                    value: _Src.link, icon: Icon(Icons.link), label: Text('رابط')),
                ButtonSegment(
                    value: _Src.file,
                    icon: Icon(Icons.upload_file),
                    label: Text('رفع ملف')),
              ],
              selected: {_src},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _src = s.first),
            ),
            const SizedBox(height: 12),
            if (_src == _Src.link) ...[
              TextField(
                controller: _url,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رابط PKG مباشر',
                  prefixIcon: Icon(Icons.link),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: (_busy || _reading) ? null : _readLink,
                icon: const Icon(Icons.search),
                label: const Text('قراءة معلومات الحزمة'),
              ),
            ] else ...[
              FilledButton.tonalIcon(
                onPressed: (_busy || _reading) ? null : _pickFile,
                icon: const Icon(Icons.folder_open),
                label: Text(_file == null ? 'اختيار ملف PKG' : 'تغيير الملف'),
              ),
              if (_file != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${_file!.name} · ${_fmtSize(_file!.size)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 4),
              Text(
                'سيُرفع الملف إلى GitHub (حتى 2GB). الأيقونة والاسم يُقرآن من الحزمة تلقائياً.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_reading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            if (info != null) ...[
              const SizedBox(height: 12),
              Card(
                color: cs.surfaceContainerHigh,
                child: ListTile(
                  leading: info.icon == null
                      ? const Icon(Icons.inventory_2, size: 40)
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(info.icon!, width: 48, height: 48),
                        ),
                  title: Text(info.title),
                  subtitle: Text(
                      '${info.contentId}\n${info.bgftType} · ${_fmtSize(info.size)}'),
                  isThreeLine: true,
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(
                  labelText: 'الاسم', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _category,
              enabled: !_busy,
              decoration: const InputDecoration(
                  labelText: 'التصنيف', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final c in ['تطبيقات', 'ألعاب', 'محاكيات', 'أدوات'])
                  ActionChip(
                    label: Text(c),
                    onPressed: _busy ? null : () => setState(() => _category.text = c),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _version,
              enabled: !_busy,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                  labelText: 'الإصدار', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              enabled: !_busy,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                  labelText: 'الوصف', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!, style: TextStyle(color: cs.onErrorContainer)),
                ),
              ),
            if (_busy) ...[
              const SizedBox(height: 8),
              Text(_status),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              if (_progress > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${(_progress * 100).toStringAsFixed(0)}%'),
                ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: const Icon(Icons.cloud_upload),
              label: Text(editing ? 'حفظ التعديلات' : 'نشر في المتجر'),
            ),
          ],
        ),
      ),
    );
  }
}
