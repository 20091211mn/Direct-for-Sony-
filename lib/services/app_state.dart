import 'package:flutter/foundation.dart';

/// UI language shared by all tabs (true = Arabic).
final ValueNotifier<bool> appArabic = ValueNotifier<bool>(true);

/// Lets the Store tab talk to the Send tab.
class Bridge {
  /// 0 = Send, 1 = Store.
  static final ValueNotifier<int> tab = ValueNotifier<int>(0);

  /// A link the Store asks the Send tab to add to its queue.
  static final ValueNotifier<String?> addUrl = ValueNotifier<String?>(null);
}
