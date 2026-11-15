import 'package:flutter/material.dart';

import '../notifications_page.dart';
import '../services/app_state.dart';

/// Bell icon with the number of unread notices; opens the notifications page.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: appArabic,
      builder: (context, ar, _) => ListenableBuilder(
        listenable: appNotificationsChanged,
        builder: (context, _) {
          final n = unreadCount();
          return IconButton(
            tooltip: ar ? 'الإشعارات' : 'Notifications',
            icon: Badge(
              isLabelVisible: n > 0,
              label: Text('$n'),
              child: const Icon(Icons.notifications_outlined),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
            ),
          );
        },
      ),
    );
  }
}
