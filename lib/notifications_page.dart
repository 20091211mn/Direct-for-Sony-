import 'package:flutter/material.dart';

import 'services/announcements.dart';
import 'services/app_state.dart';
import 'services/updater.dart';
import 'settings_page.dart';

/// Notices from the admin (news and "what's new" lists) and the pending update.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late final Set<String> _unreadAtOpen;
  bool _refreshing = false;

  String t(String en, String ar) => appArabic.value ? ar : en;

  @override
  void initState() {
    super.initState();
    _unreadAtOpen = appAnnouncements.value
        .map((a) => a.id)
        .where((id) => !appReadIds.value.contains(id))
        .toSet();
    markAllRead();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    await refreshNotifications();
    if (!mounted) return;
    // Notices that arrive while the page is open are also counted as read.
    await markAllRead();
    if (mounted) setState(() => _refreshing = false);
  }

  Widget _bullets(List<String> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in items)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(f)),
                ],
              ),
            ),
        ],
      );

  Widget _updateCard(UpdateInfo u, ColorScheme cs) {
    return Card(
      color: cs.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.system_update),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${t('New update available', 'تحديث جديد متوفر')}: ${u.tag}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ]),
            if (u.features.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t("What's new", 'الجديد في هذا الإصدار'),
                  style: Theme.of(context).textTheme.labelLarge),
              _bullets(u.features),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SettingsPage(ar: appArabic.value, update: u),
                )),
                icon: const Icon(Icons.download),
                label: Text(t('Update', 'تحديث')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _announcementCard(Announcement a, ColorScheme cs) {
    final isNew = _unreadAtOpen.contains(a.id);
    final isUpdate = a.type == 'update';
    return Card(
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(isUpdate ? Icons.new_releases : Icons.campaign),
              const SizedBox(width: 8),
              Expanded(
                child: Text(a.title,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (isNew)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(t('New', 'جديد'),
                      style: TextStyle(color: cs.onPrimary, fontSize: 12)),
                ),
            ]),
            if (a.date.length >= 10)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(a.date.substring(0, 10),
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            if (a.body.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(a.body),
            ],
            if (a.features.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(t("What's new", 'الجديد'),
                  style: Theme.of(context).textTheme.labelLarge),
              _bullets(a.features),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: appArabic,
      builder: (context, ar, _) => Directionality(
        textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: Text(t('Notifications', 'الإشعارات')),
            actions: [
              IconButton(
                tooltip: t('Refresh', 'تحديث'),
                icon: const Icon(Icons.refresh),
                onPressed: _refreshing ? null : _refresh,
              ),
            ],
          ),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListenableBuilder(
                listenable: appNotificationsChanged,
                builder: (context, _) {
                  final update = appUpdate.value;
                  final items = appAnnouncements.value;
                  if (update == null && items.isEmpty) {
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            children: [
                              const Icon(Icons.notifications_none, size: 48),
                              const SizedBox(height: 12),
                              Text(
                                t('No notifications yet.', 'لا توجد إشعارات بعد.'),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  }
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (update != null) _updateCard(update, cs),
                      for (final a in items) _announcementCard(a, cs),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
