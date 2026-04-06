import 'package:flutter/material.dart';
import 'core/network/relay_client.dart';
import 'features/storage_accounts/accounts_screen.dart';
import 'features/upload/upload_screen.dart';
import 'features/relay/relay_screen.dart';

void main() => runApp(const DudenestApp());

class DudenestApp extends StatefulWidget {
  const DudenestApp({super.key});
  static DudenestAppState of(BuildContext context) =>
      context.findAncestorStateOfType<DudenestAppState>()!;
  @override
  State<DudenestApp> createState() => DudenestAppState();
}

class DudenestAppState extends State<DudenestApp> {
  ThemeMode _themeMode = ThemeMode.system; // default: follow system
  void setThemeMode(ThemeMode mode) => setState(() => _themeMode = mode);

  @override
  Widget build(BuildContext context) {
    const seed = Colors.indigo;
    return MaterialApp(
      title: 'Dudenest',
      themeMode: _themeMode,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  // Relay URL — localhost tunnel for dev (ssh -L 8086:192.168.0.119:8086 root@10.51.1.101)
  // Production: http://10.71.0.1:8086 (Headscale)
  static const _relayUrl = 'http://localhost:8086';
  final _relay = RelayClient(_relayUrl);

  @override
  Widget build(BuildContext context) {
    final screens = [
      AccountsScreen(relay: _relay),
      UploadScreen(relay: _relay),
      RelayScreen(relay: _relay),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.cloud), label: 'Accounts'),
          NavigationDestination(icon: Icon(Icons.upload), label: 'Upload'),
          NavigationDestination(icon: Icon(Icons.folder), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = DudenestApp.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
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
      ]),
    );
  }
}
