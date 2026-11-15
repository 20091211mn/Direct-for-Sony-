import 'package:flutter/material.dart';

import '../services/announcements.dart';
import '../services/updater.dart' show parseFeatures;
import 'github_api.dart';

enum _Kind { news, update }

/// Publishes a notice: general news, or "new update" with its list of new features.
/// An update notice also writes the same list into the release notes.
class AnnouncementEditor extends StatefulWidget {
  const AnnouncementEditor({super.key, required this.api});

  final GithubApi api;

  @override
  State<AnnouncementEditor> createState() => _AnnouncementEditorState();
}

class _AnnouncementEditorState extends State<AnnouncementEditor> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _features = TextEditingController();

  _Kind _kind = _Kind.news;
  List<ReleaseInfo> _releases = [];
  ReleaseInfo? _release;
  bool _loadingReleases = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _features.dispose();
    super.dispose();
  }

  Future<void> _loadReleases() async {
    if (_releases.isNotEmpty || _loadingReleases) return;
    setState(() {
      _loadingReleases = true;
      _error = null;
    });
    try {
      final list = await widget.api.listReleases();
      if (!mounted) return;
      setState(() {
        _releases = list;
        if (list.isNotEmpty) _pick(list.first);
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر تحميل الإصدارات: $e');
    } finally {
      if (mounted) setState(() => _loadingReleases = false);
    }
  }

  void _pick(ReleaseInfo r) {
    _release = r;
    _title.text = 'تحديث جديد ${r.tag}';
    // Keep the notes already written on the release (the CI placeholder is ignored).
    _features.text = parseFeatures(r.body).join('\n');
  }

  Future<void> _publish() async {
    final title = _title.text.trim();
    final features = _features.text
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^[-*•]\s*'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final body = _body.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'اكتب عنوان الإشعار');
      return;
    }
    if (body.isEmpty && features.isEmpty) {
      setState(() => _error = 'اكتب نص الإشعار أو قائمة الميزات');
      return;
    }
    if (_kind == _Kind.update && _release == null) {
      setState(() => _error = 'اختر الإصدار');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final date = now.toUtc().toIso8601String();
      if (_kind == _Kind.update) {
        final r = _release!;
        if (features.isNotEmpty) {
          await widget.api
              .setReleaseNotes(r.id, features.map((f) => '- $f').join('\n'));
        }
        await widget.api.addAnnouncement(Announcement(
          id: 'u-${r.build}-${now.millisecondsSinceEpoch}',
          type: 'update',
          title: title,
          body: body,
          features: features,
          date: date,
          build: r.build,
        ));
      } else {
        await widget.api.addAnnouncement(Announcement(
          id: 'n-${now.millisecondsSinceEpoch}',
          type: 'news',
          title: title,
          body: body,
          features: features,
          date: date,
        ));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'فشل النشر: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إشعار جديد')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<_Kind>(
              segments: const [
                ButtonSegment(
                    value: _Kind.news,
                    icon: Icon(Icons.campaign),
                    label: Text('خبر عام')),
                ButtonSegment(
                    value: _Kind.update,
                    icon: Icon(Icons.system_update),
                    label: Text('تحديث جديد')),
              ],
              selected: {_kind},
              onSelectionChanged: _busy
                  ? null
                  : (s) {
                      setState(() => _kind = s.first);
                      if (_kind == _Kind.update) _loadReleases();
                    },
            ),
            const SizedBox(height: 12),
            if (_kind == _Kind.update) ...[
              if (_loadingReleases)
                const LinearProgressIndicator()
              else if (_releases.isEmpty)
                const Text('لا توجد إصدارات منشورة بعد.')
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الإصدار'),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final r in _releases.take(6))
                          ChoiceChip(
                            label: Text(r.tag),
                            selected: _release?.id == r.id,
                            onSelected: _busy ? null : (_) => setState(() => _pick(r)),
                          ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _title,
              enabled: !_busy,
              decoration: const InputDecoration(
                  labelText: 'العنوان', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              enabled: !_busy,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                  labelText: 'النص (اختياري)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _features,
              enabled: !_busy,
              minLines: 4,
              maxLines: 10,
              decoration: InputDecoration(
                labelText: _kind == _Kind.update
                    ? 'الميزات الجديدة (كل ميزة في سطر)'
                    : 'نقاط (اختياري، كل نقطة في سطر)',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _kind == _Kind.update
                  ? 'تُكتب هذه القائمة أيضاً في ملاحظات الإصدار، وتظهر للمستخدمين في بطاقة التحديث وفي الإشعارات.'
                  : 'يظهر الإشعار في تطبيق المستخدمين وكإشعار على أندرويد.',
              style: Theme.of(context).textTheme.bodySmall,
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
            if (_busy) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _publish,
              icon: const Icon(Icons.send),
              label: const Text('نشر الإشعار'),
            ),
          ],
        ),
      ),
    );
  }
}
