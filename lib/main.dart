import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/auth/auth_service.dart';
import 'core/network/relay_client.dart';
import 'features/auth/login_screen.dart';
import 'features/storage_accounts/accounts_screen.dart';
import 'features/upload/upload_screen.dart';
import 'features/relay/relay_screen.dart';
import 'features/relay/relay_management_screen.dart';

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
  String _storageStrategy = 'Replica'; // 'Chunking' or 'Replica'

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = ThemeMode.values[prefs.getInt('theme_mode') ?? 0];
      _storageStrategy = prefs.getString('storage_strategy') ?? 'Replica';
    });
  }

  void setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    setState(() => _themeMode = mode);
  }

  void setStorageStrategy(String strategy) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('storage_strategy', strategy);
    setState(() => _storageStrategy = strategy);
  }

  String get storageStrategy => _storageStrategy;

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
  static const _defaultRelayUrl = 'https://relay.dudenest.com';
  late RelayClient _relay;
  late String _relayUrl;

  @override
  void initState() {
    super.initState();
    _relayUrl = _defaultRelayUrl;
    _relay = RelayClient(_relayUrl);
    _loadRelayUrl();
  }

  Future<void> _loadRelayUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('relay_url') ?? _defaultRelayUrl;
    if (saved != _relayUrl && mounted) {
      setState(() { _relayUrl = saved; _relay = RelayClient(saved); });
    }
  }

  void setRelayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('relay_url', url);
    if (mounted) setState(() { _relayUrl = url; _relay = RelayClient(url); });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      RelayScreen(relay: _relay),
      UploadScreen(relay: _relay),
      SettingsScreen(relay: _relay, relayUrl: _relayUrl, onRelayUrlChanged: setRelayUrl),
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
  final String relayUrl;
  final void Function(String) onRelayUrlChanged;
  const SettingsScreen({super.key, required this.relay, required this.relayUrl, required this.onRelayUrlChanged});
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
        // Version — displayed right after user info
        ListTile(
          leading: const Icon(Icons.tag),
          title: const Text('Version'),
          trailing: const Text(
            String.fromEnvironment('APP_VERSION', defaultValue: 'dev'),
            style: TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const Divider(),
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
        const ListTile(title: Text('Relay', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.router),
          title: const Text('Relay URL'),
          subtitle: Text(relayUrl, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final ctrl = TextEditingController(text: relayUrl);
            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Set Relay URL'),
                content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'https://relay.dudenest.com')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
                ],
              ),
            );
            if (result != null && result.isNotEmpty) onRelayUrlChanged(result);
          },
        ),
        const Divider(),
        const ListTile(title: Text('Storage', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.sd_storage),
          title: const Text('Storage Strategy'),
          subtitle: Text(app.storageStrategy == 'Replica' ? 'Main + 2 Backups' : 'Chunking + Erasure Coding'),
          trailing: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'Chunking', label: Text('Chunking'), icon: Icon(Icons.grid_view)),
              ButtonSegment(value: 'Replica', label: Text('Replica'), icon: Icon(Icons.copy_all)),
            ],
            selected: {app.storageStrategy},
            onSelectionChanged: (val) => app.setStorageStrategy(val.first),
          ),
        ),
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
        ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('My Relays & Backups'),
          subtitle: const Text('View registered relays and backup status'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RelayManagementScreen()),
          ),
        ),
        const Divider(),
        const ListTile(title: Text('Community', style: TextStyle(fontWeight: FontWeight.bold))),
        _SocialLinkTile(icon: FontAwesomeIcons.github, color: const Color(0xFF24292e),
            label: 'GitHub', subtitle: 'Source code', url: 'https://github.com/dudenest/dudenest'),
        _SocialLinkTile(icon: FontAwesomeIcons.discord, color: const Color(0xFF5865F2),
            label: 'Discord', subtitle: 'Community chat', url: 'https://discord.gg/pYjR9jS4'),
        _SocialLinkTile(icon: FontAwesomeIcons.youtube, color: const Color(0xFFFF0000),
            label: 'YouTube', subtitle: 'Videos — coming soon'),
        _SocialLinkTile(icon: FontAwesomeIcons.facebook, color: const Color(0xFF1877F2),
            label: 'Facebook', subtitle: 'Page — coming soon'),
        _SocialLinkTile(icon: FontAwesomeIcons.xTwitter, color: Colors.black87,
            label: 'X / Twitter', subtitle: 'Updates — coming soon'),
      ]),
    );
  }
}

class _SocialLinkTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final String? url;
  const _SocialLinkTile({required this.icon, required this.color, required this.label,
      required this.subtitle, this.url});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: FaIcon(icon, color: color, size: 18),
      ),
      title: Text(label),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: url != null ? const Icon(Icons.open_in_new, size: 16, color: Colors.grey) : null,
      onTap: url != null ? () => launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication) : null,
    );
  }
}
