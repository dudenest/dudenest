import 'package:flutter/material.dart';
import 'core/auth/auth_service.dart';
import 'core/network/relay_client.dart';
import 'features/auth/login_screen.dart';
import 'features/storage_accounts/accounts_screen.dart';
import 'features/upload/upload_screen.dart';
import 'features/relay/relay_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService().init(); // loads token from localStorage + handles OAuth callback
  runApp(const DudenestApp());
}

class DudenestApp extends StatefulWidget {
  const DudenestApp({super.key});
  static DudenestAppState of(BuildContext context) =>
      context.findAncestorStateOfType<DudenestAppState>()!;
  @override
  State<DudenestApp> createState() => DudenestAppState();
}

class DudenestAppState extends State<DudenestApp> {
  ThemeMode _themeMode = ThemeMode.system;
  void setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);
  void refresh() => setState(() {}); // called after sign-out to rebuild

  @override
  Widget build(BuildContext context) {
    const seed = Colors.indigo;
    return MaterialApp(
      title: 'Dudenest',
      themeMode: _themeMode,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: AuthService().isLoggedIn ? const HomeScreen() : const LoginScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0; // 0=Files, 1=Upload, 2=Settings
  // Relay URL — Cloudflare Tunnel (relay-poc → relay.dudenest.com)
  // Dev: http://localhost:8086 (ssh -L 8086:192.168.0.119:8086 root@10.51.1.101)
  static const _relayUrl = 'https://relay.dudenest.com';
  final _relay = RelayClient(_relayUrl);

  @override
  Widget build(BuildContext context) {
    final screens = [
      RelayScreen(relay: _relay),
      UploadScreen(relay: _relay),
      SettingsScreen(relay: _relay),
    ];
    return Scaffold(
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.upload), label: 'Upload'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  final RelayClient relay;
  const SettingsScreen({super.key, required this.relay});
  @override
  Widget build(BuildContext context) {
    final app = DudenestApp.of(context);
    final user = AuthService().user;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        // Logged-in user info
        if (user != null) ...[
          ListTile(
            leading: CircleAvatar(
              backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
              child: user.avatarUrl == null ? Text(user.email[0].toUpperCase()) : null,
            ),
            title: Text(user.name ?? user.email),
            subtitle: Text('${user.provider} · ${user.email}'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await AuthService().signOut();
              app.refresh();
            },
          ),
          const Divider(),
        ],
        const ListTile(title: Text('Theme', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.brightness_auto),
          title: const Text('System default'),
          onTap: () => app.setThemeMode(ThemeMode.system),
        ),
        ListTile(
          leading: const Icon(Icons.light_mode),
          title: const Text('Light'),
          onTap: () => app.setThemeMode(ThemeMode.light),
        ),
        ListTile(
          leading: const Icon(Icons.dark_mode),
          title: const Text('Dark'),
          onTap: () => app.setThemeMode(ThemeMode.dark),
        ),
        const Divider(),
        const ListTile(title: Text('Storage', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.cloud),
          title: const Text('Cloud Accounts'),
          subtitle: const Text('Connected Google Drive accounts'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AccountsScreen(relay: relay)),
          ),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Wersja'),
          trailing: Text(
            String.fromEnvironment('APP_VERSION', defaultValue: 'dev'),
            style: TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
        ),
      ]),
    );
  }
}
