import 'package:flutter/material.dart';
import 'core/network/relay_client.dart';
import 'features/storage_accounts/accounts_screen.dart';
import 'features/upload/upload_screen.dart';
import 'features/relay/relay_screen.dart';

void main() => runApp(const DudenestApp());

class DudenestApp extends StatelessWidget {
  const DudenestApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dudenest',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
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
  // Relay URL — configurable; defaults to relay-poc via Headscale
  static const _relayUrl = 'http://10.71.0.1:8086';
  final _relay = RelayClient(_relayUrl);

  @override
  Widget build(BuildContext context) {
    final screens = [
      AccountsScreen(relay: _relay),
      UploadScreen(relay: _relay),
      RelayScreen(relay: _relay),
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
        ],
      ),
    );
  }
}
