import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'services/app_state.dart';
import 'services/store_catalog.dart';

/// The "Store" tab: a catalog published by the admin app. Tapping "Add to queue"
/// sends the link to the Send tab.
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

  String t(String en, String ar) => appArabic.value ? ar : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

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

  void _add(StoreItem item) {
    Bridge.addUrl.value = item.url;
    Bridge.tab.value = 0;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(t('Added "${item.title}" to the queue.',
            'تمت إضافة "${item.title}" إلى القائمة.')),
      ));
  }

  Widget _icon(StoreItem item) {
    const size = 56.0;
    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.inventory_2),
    );
    if (item.icon.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        item.icon,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
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
        }).toList();

        return Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            appBar: AppBar(
              title: Text(t('Store', 'المتجر')),
              actions: [
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
                        border: const OutlineInputBorder(),
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
                                onSelected: (_) =>
                                    setState(() => _category = ''),
                              ),
                            ),
                            for (final c in categories)
                              Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(end: 8),
                                child: ChoiceChip(
                                  label: Text(c),
                                  selected: _category == c,
                                  onSelected: (_) =>
                                      setState(() => _category = c),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
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
                        child: Text(
                          t('No results.', 'لا توجد نتائج.'),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      for (final item in shown)
                        Card(
                          color: cs.surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
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
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item.title,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                          const SizedBox(height: 2),
                                          Text(
                                            [
                                              if (item.category.isNotEmpty)
                                                item.category,
                                              if (item.version.isNotEmpty)
                                                'v${item.version}',
                                              if (_fmtSize(item.size)
                                                  .isNotEmpty)
                                                _fmtSize(item.size),
                                            ].join(' · '),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.description.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(item.description,
                                      maxLines: 4,
                                      overflow: TextOverflow.ellipsis),
                                ],
                                const SizedBox(height: 8),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: FilledButton.tonalIcon(
                                    onPressed: () => _add(item),
                                    icon: const Icon(Icons.playlist_add),
                                    label: Text(
                                        t('Add to queue', 'إضافة للقائمة')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
