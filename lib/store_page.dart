import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'services/app_state.dart';
import 'services/store_catalog.dart';
import 'widgets/notification_bell.dart';

/// The "Store" tab: a catalog published by the admin app. "Add to queue" sends
/// the link to the Send tab; "Install now" also starts sending when the queue is empty.
class StorePage extends StatefulWidget {
  const StorePage({super.key});

  @override
  State<StorePage> createState() => _StorePageState();
}

class _StorePageState extends State<StorePage> {
  StoreCatalog? _catalog;
  bool _loading = true;
  String? _error;
  String _query = '';
  String _category = '';
  Map<String, String> _installed = {};

  String t(String en, String ar) => appArabic.value ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
    _loadInstalled();
    Bridge.storeTick.addListener(_loadInstalled);
  }

  @override
  void dispose() {
    Bridge.storeTick.removeListener(_loadInstalled);
    super.dispose();
  }

  Future<void> _loadInstalled() async {
    final m = await StoreInstalled.load();
    if (mounted) setState(() => _installed = m);
  }

  /// The store has a newer version than the one sent from this app.
  bool _hasUpdate(StoreItem i) =>
      i.version.isNotEmpty &&
      _installed.containsKey(i.id) &&
      _installed[i.id] != i.version;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await StoreService.fetch();
      if (mounted) setState(() => _catalog = c);
    } catch (e) {
      if (mounted) {
        setState(() => _error = (e is SocketException || e is TimeoutException)
            ? t('Cannot reach the store. Check your internet connection.',
                'تعذّر الوصول إلى المتجر. تحقق من اتصال الإنترنت.')
            : t('The store is unavailable right now ($e).',
                'المتجر غير متاح حالياً ($e).'));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmtSize(int b) {
    if (b <= 0) return '';
    const u = ['B', 'KB', 'MB', 'GB'];
    var v = b.toDouble();
    var i = 0;
    while (v >= 1024 && i < u.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
  }

  bool _isNew(StoreItem i) {
    final d = DateTime.tryParse(i.added);
    return d != null && DateTime.now().difference(d).inDays <= 14;
  }

  void _add(StoreItem item) {
    Bridge.autoSend = false;
    Bridge.addId = item.id;
    Bridge.addVersion = item.version;
    Bridge.addUrl.value = item.url;
    Bridge.tab.value = 0;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(t('Added "${item.title}" to the queue.',
            'تمت إضافة "${item.title}" إلى القائمة.')),
      ));
  }

  /// Adds the item and, when the queue was empty and the PS4 address is saved, sends it.
  void _installNow(StoreItem item) {
    Bridge.autoSend = true;
    Bridge.addId = item.id;
    Bridge.addVersion = item.version;
    Bridge.addUrl.value = item.url;
    Bridge.tab.value = 0;
  }

  /// Adds an older version of an item to the queue.
  void _addVersion(StoreItem item, StoreVersion v) {
    Bridge.autoSend = false;
    Bridge.addId = item.id;
    Bridge.addVersion = v.version;
    Bridge.addUrl.value = v.url;
    Bridge.tab.value = 0;
  }

  Widget _updateBadge(ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.tertiary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t('Update available', 'تحديث متوفر'),
            style: TextStyle(color: cs.onTertiary, fontSize: 12)),
      );

  Widget _icon(StoreItem item, {double size = 56}) {
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.inventory_2),
    );
    if (item.icon.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        item.icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }

  Widget _newBadge(ColorScheme cs) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: cs.primary,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t('New', 'جديد'),
            style: TextStyle(color: cs.onPrimary, fontSize: 12)),
      );

  Widget _featuredStrip(List<StoreItem> items, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Icon(Icons.star, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Text(t('Featured', 'مميز'),
                style: Theme.of(context).textTheme.titleSmall),
          ]),
        ),
        SizedBox(
          height: 132,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final i in items)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _add(i),
                    child: Container(
                      width: 120,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _icon(i, size: 60),
                          const SizedBox(height: 8),
                          Text(i.title,
                              maxLines: 2,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: cs.onPrimaryContainer, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _card(StoreItem item, ColorScheme cs) {
    final meta = [
      if (item.category.isNotEmpty) item.category,
      if (item.version.isNotEmpty) 'v${item.version}',
      if (_fmtSize(item.size).isNotEmpty) _fmtSize(item.size),
    ].join(' · ');
    final update = _hasUpdate(item);
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _icon(item),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(item.title,
                              style: Theme.of(context).textTheme.titleMedium),
                        ),
                        if (update) _updateBadge(cs) else if (_isNew(item)) _newBadge(cs),
                      ]),
                      const SizedBox(height: 2),
                      Text(meta, style: Theme.of(context).textTheme.bodySmall),
                      if (update)
                        Text(
                          '${t('You sent', 'آخر إصدار أرسلته')}: v${_installed[item.id]}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (item.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item.description, maxLines: 4, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _add(item),
                  icon: const Icon(Icons.playlist_add),
                  label: Text(t('Add to queue', 'إضافة للقائمة')),
                ),
                FilledButton.icon(
                  onPressed: () => _installNow(item),
                  icon: Icon(update ? Icons.system_update : Icons.bolt),
                  label: Text(update
                      ? t('Update', 'تحديث')
                      : t('Install now', 'تثبيت الآن')),
                ),
              ],
            ),
            if (item.history.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  '${t('Previous versions', 'الإصدارات السابقة')} (${item.history.length})',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                children: [
                  for (final v in item.history)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text('v${v.version}'),
                      subtitle: Text([
                        if (_fmtSize(v.size).isNotEmpty) _fmtSize(v.size),
                        if (v.date.length >= 10) v.date.substring(0, 10),
                      ].join(' · ')),
                      trailing: IconButton(
                        tooltip: t('Add to queue', 'إضافة للقائمة'),
                        icon: const Icon(Icons.playlist_add),
                        onPressed: () => _addVersion(item, v),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: appArabic,
      builder: (context, ar, _) {
        final cs = Theme.of(context).colorScheme;
        final all = _catalog?.items ?? const <StoreItem>[];
        final categories = <String>{
          for (final i in all)
            if (i.category.isNotEmpty) i.category
        }.toList()
          ..sort();
        final q = _query.trim().toLowerCase();
        final shown = all.where((i) {
          if (_category.isNotEmpty && i.category != _category) return false;
          if (q.isEmpty) return true;
          return i.title.toLowerCase().contains(q) ||
              i.description.toLowerCase().contains(q);
        }).toList()
          ..sort((a, b) => b.added.compareTo(a.added)); // newest first
        final featured = (q.isEmpty && _category.isEmpty)
            ? all.where((i) => i.featured).toList()
            : <StoreItem>[];

        return Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              title: Text(t('Store', 'المتجر')),
              actions: [
                const NotificationBell(),
                IconButton(
                  tooltip: t('Refresh', 'تحديث'),
                  icon: const Icon(Icons.refresh),
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            body: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        hintText: t('Search the store', 'ابحث في المتجر'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            Padding(
                              padding: const EdgeInsetsDirectional.only(end: 8),
                              child: ChoiceChip(
                                label: Text(t('All', 'الكل')),
                                selected: _category.isEmpty,
                                onSelected: (_) => setState(() => _category = ''),
                              ),
                            ),
                            for (final c in categories)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(end: 8),
                                child: ChoiceChip(
                                  label: Text(c),
                                  selected: _category == c,
                                  onSelected: (_) => setState(() => _category = c),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (featured.isNotEmpty) _featuredStrip(featured, cs),
                    if (_loading && _catalog == null)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null && _catalog == null)
                      Card(
                        color: cs.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!,
                              style: TextStyle(color: cs.onErrorContainer)),
                        ),
                      )
                    else if (_catalog != null && !_catalog!.exists)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          t('The store is empty for now. Items will appear here once the admin publishes them.',
                              'المتجر فارغ حالياً. ستظهر العناصر هنا عندما ينشرها المشرف.'),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else if (shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(t('No results.', 'لا توجد نتائج.'),
                            textAlign: TextAlign.center),
                      )
                    else ...[
                      if (featured.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(t('Latest', 'الأحدث'),
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                      for (final item in shown) _card(item, cs),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
