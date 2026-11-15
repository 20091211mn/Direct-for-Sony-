import 'package:flutter/material.dart';

import 'home_page.dart';
import 'services/app_state.dart';
import 'store_page.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PS4 Sender',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2F6BFF),
          brightness: Brightness.dark,
        ),
      ),
      home: const RootPage(),
    );
  }
}

/// Bottom navigation: Send | Store.
class RootPage extends StatelessWidget {
  const RootPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: appArabic,
      builder: (context, ar, _) => ValueListenableBuilder<int>(
        valueListenable: Bridge.tab,
        builder: (context, tab, _) => Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: IndexedStack(
              index: tab,
              children: const [HomePage(), StorePage()],
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => Bridge.tab.value = i,
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.send_outlined),
                  selectedIcon: const Icon(Icons.send),
                  label: ar ? 'إرسال' : 'Send',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.storefront_outlined),
                  selectedIcon: const Icon(Icons.storefront),
                  label: ar ? 'المتجر' : 'Store',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
