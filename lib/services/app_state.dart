import 'package:flutter/foundation.dart';

import 'announcements.dart';
import 'updater.dart';

/// UI language shared by all tabs (true = Arabic).
final ValueNotifier<bool> appArabic = ValueNotifier<bool>(true);

/// Newest app version found online (null = up to date).
final ValueNotifier<UpdateInfo?> appUpdate = ValueNotifier<UpdateInfo?>(null);

/// Notices published by the admin app, newest first.
final ValueNotifier<List<Announcement>> appAnnouncements =
    ValueNotifier<List<Announcement>>([]);

/// Ids of the notices the user already opened.
final ValueNotifier<Set<String>> appReadIds = ValueNotifier<Set<String>>({});

/// Lets the Store tab talk to the Send tab.
class Bridge {
  /// 0 = Send, 1 = Store.
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  /// A link the Store asks the Send tab to add to its queue.
  static final ValueNotifier<String?> addUrl = ValueNotifier<String?>(null);

  /// When true the Send tab starts sending right after adding [addUrl].
  static bool autoSend = false;
}

/// Number shown on the bell: unread notices + a pending app update.
int unreadCount() {
  final unread = appAnnouncements.value
      .where((a) => !appReadIds.value.contains(a.id))
      .length;
  return unread + (appUpdate.value != null ? 1 : 0);
}

/// Reloads the update information and the notices.
Future<void> refreshNotifications() async {
  try {
    appUpdate.value = await Updater.checkQuiet();
  } catch (_) {}
  appAnnouncements.value = await AnnouncementService.fetch();
  appReadIds.value = await AnnouncementService.readIds();
}

/// Marks every notice as read.
Future<void> markAllRead() async {
  final ids = {
    ...appReadIds.value,
    ...appAnnouncements.value.map((a) => a.id),
  };
  appReadIds.value = ids;
  await AnnouncementService.saveReadIds(ids);
}

/// Fires when the update, the notices or the read marks change.
final Listenable appNotificationsChanged =
    Listenable.merge([appUpdate, appAnnouncements, appReadIds]);
