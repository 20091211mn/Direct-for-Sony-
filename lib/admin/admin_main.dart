import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/store_catalog.dart';
import '../services/updater.dart' show kRepo;
import 'github_api.dart';
import 'item_editor.dart';

void main() => runApp(const AdminApp());

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PS4 Store Admin',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE08A1E),
          brightness: Brightness.dark,
        ),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const AdminGate(),
    );
  }
}

/// Shows the login page until a valid token is saved.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  GithubApi? _api;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final token = p.getString('admin_token');
      final repo = p.getString('admin_repo') ?? kRepo;
      if (token != null && token.isNotEmpty) _api = GithubApi(token, repo);
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _logout() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('admin_token');
    if (mounted) setState(() => _api = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final api = _api;
    if (api == null) {
      return LoginPage(onLogin: (a) => setState(() => _api = a));
    }
    return AdminHome(api: api, onLogout: _logout);
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onLogin});

  final void Function(GithubApi api) onLogin;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _token = TextEditingController();
  final _repo = TextEditingController(text: kRepo);
  bool _busy = false;
  String? _error;

  Future<void> _login() async {
    final token = _token.text.trim();
    final repo = _repo.text.trim();
    if (token.isEmpty || !repo.contains('/')) {
      setState(() => _error = 'اكتب التوكن واسم المستودع بصيغة owner/name');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = GithubApi(token, repo);
      await api.verify();
      final p = await SharedPreferences.getInstance();
      await p.setString('admin_token', token);
      await p.setString('admin_repo', repo);
      widget.onLogin(api);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is GithubError && e.status == 401
            ? 'التوكن غير صالح.'
            : 'فشل التحقق: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المتجر')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
                'سجّل الدخول بتوكن GitHub (Personal access token) فيه صلاحية repo. يُحفظ على هذا الجوال فقط.'),
            const SizedBox(height: 16),
            TextField(
              controller: _token,
              obscureText: true,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'GitHub token',
                prefixIcon: Icon(Icons.key),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repo,
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(
                labelText: 'المستودع (owner/name)',
                prefixIcon: Icon(Icons.folder),
                border: OutlineInputBorder(),
              ),
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
            FilledButton.icon(
              onPressed: _busy ? null : _login,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.login),
              label: const Text('تسجيل الدخول'),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key, required this.api, required this.onLogout});

  final GithubApi api;
  final VoidCallback onLogout;

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  List<StoreItem> _items = [];
  bool _loading = true;
  String? _error;

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
      final items = await widget.api.loadItems();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر تحميل المتجر: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit([StoreItem? item]) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ItemEditor(api: widget.api, item: item),
    ));
    if (changed == true) _load();
  }

  Future<void> _delete(StoreItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف العنصر'),
        content: Text('حذف "${item.title}" من المتجر؟ سيُحذف الملف المرفوع أيضاً إن كان على GitHub.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.api.removeItem(item);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('فشل الحذف: $e')));
      }
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة المتجر'),
        actions: [
          IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
          IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('إضافة'),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24), child: Text(_error!)))
                : _items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('المتجر فارغ. اضغط "إضافة" لنشر أول عنصر.'),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        children: [
                          for (final i in _items)
                            Card(
                              color: cs.surfaceContainerHigh,
                              child: ListTile(
                                leading: i.icon.isEmpty
                                    ? const Icon(Icons.inventory_2, size: 40)
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(i.icon,
                                            width: 48,
                                            height: 48,
                                            errorBuilder: (_, __, ___) =>
                                                const Icon(Icons.inventory_2)),
                                      ),
                                title: Text(i.title),
                                subtitle: Text([
                                  if (i.category.isNotEmpty) i.category,
                                  if (i.version.isNotEmpty) 'v${i.version}',
                                  if (_fmtSize(i.size).isNotEmpty) _fmtSize(i.size),
                                ].join(' · ')),
                                onTap: () => _edit(i),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(i),
                                ),
                              ),
                            ),
                        ],
                      ),
      ),
    );
  }
}
