import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
// font_awesome_flutter removed in this commit — every 10.x release extends final IconData
// which strict Dart 3 rejects, breaking Flutter test/build. Brand icons below now use Material's
// built-in glyphs (Icons.facebook etc.) plus generic widgets for ones Material doesn't ship.
import 'package:url_launcher/url_launcher.dart';
import 'core/auth/auth_service.dart';
import 'core/network/relay_client.dart';
import 'features/auth/login_screen.dart';
import 'features/storage_accounts/accounts_screen.dart';
import 'features/upload/upload_screen.dart';
import 'features/relay/relay_screen.dart';
import 'features/update/update_screen.dart';
import 'features/relay/relay_management_screen.dart';
import 'features/files/gallery_settings.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService()
      .init(); // loads token from localStorage + handles OAuth callback
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
  String _storageStrategy =
      'Replica'; // historical setting — only "Replica" (1 file + N copies) is supported since relay v0.21.0

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
      theme: ThemeData(
          colorSchemeSeed: seed,
          brightness: Brightness.light,
          useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: seed,
          brightness: Brightness.dark,
          useMaterial3: true),
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
  late RelayClient _relay;
  String? _relayUrl;
  String? _relayError;
  Timer?
      _tokenRefreshTimer; // periodic relay_token refresh (token TTL=1h, refresh every 50min)
  bool _relayReady =
      false; // true after first _loadRelayUrl() completes — prevents cold-start 403

  @override
  void initState() {
    super.initState();
    _relay = RelayClient('');
    // Await initial token fetch before rendering RelayScreen to prevent cold-start 403
    _loadRelayUrl().then((_) {
      if (mounted) setState(() => _relayReady = true);
    });
    // Relay token expires after 1 hour — refresh every 50 minutes to prevent 403
    _tokenRefreshTimer =
        Timer.periodic(const Duration(minutes: 50), (_) => _loadRelayUrl());
  }

  @override
  void dispose() {
    _tokenRefreshTimer?.cancel();
    super.dispose();
  }

  // _loadRelayUrl resolves the relay URL and relay_token for the current authenticated user.
  // Production is server-authoritative: no hardcoded relay.dudenest.com fallback and no stale prefs.
  Future<void> _loadRelayUrl() async {
    final info = await _fetchRelayInfoFromApi();
    if (info != null) {
      final url = info['relay_url']!;
      final token =
          info['relay_token']; // may be null if relay not yet registered
      if (mounted)
        setState(() {
          _relayUrl = url;
          _relayError = null;
          _relay = RelayClient(url, relayToken: token);
        });
      return;
    }
    if (mounted)
      setState(() {
        _relayUrl = null;
        _relayError ??= 'No relay assigned to this account';
      });
  }

  // _fetchRelayInfoFromApi calls backend GET /api/v1/relays and returns relay_url + relay_token
  // for the first relay registered for the current user. Returns null on empty list, records error on failure.
  // relay_token is a short-lived HMAC (1h) signed by backup using relay_secret — Layer 3 security.
  Future<Map<String, String?>?> _fetchRelayInfoFromApi() async {
    final token = AuthService().token;
    if (token == null) return null;
    try {
      final resp = await http.get(
        Uri.parse('https://api.dudenest.com/api/v1/relays'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 5));
      if (resp.statusCode != 200) {
        _relayError = 'Cannot load relay (HTTP ${resp.statusCode})';
        return null;
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final relays = data['relays'] as List?;
      if (relays == null || relays.isEmpty) {
        _relayError = 'No relay assigned to this account';
        return null;
      }
      final first = relays.first as Map<String, dynamic>;
      final relayUrl = first['relay_url'] as String?;
      if (relayUrl == null || relayUrl.isEmpty) {
        _relayError = 'No relay assigned to this account';
        return null;
      }
      return {
        'relay_url': relayUrl,
        'relay_token': first['relay_token'] as String?
      };
    } catch (_) {
      _relayError = 'Cannot load relay';
      return null;
    }
  }

  void setRelayUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('relay_url', url);
    // Dev/custom override is stored for local experiments only; authenticated production users still use API relay_url + relay_token.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    // Show loading spinner until relay token is ready — prevents cold-start 403 on Files tab
    if (!_relayReady)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_relayUrl == null)
      return _RelayUnavailableScreen(
          message: _relayError ?? 'Cannot load relay', onRetry: _loadRelayUrl);
    final screens = [
      RelayScreen(relay: _relay, folder: 'photos'), // P3: media-only tab
      RelayScreen(relay: _relay, folder: 'files'), // P3: non-media tab
      UploadScreen(relay: _relay),
      SettingsScreen(
          relay: _relay, relayUrl: _relayUrl!, onRelayUrlChanged: setRelayUrl),
    ];
    return Scaffold(
      body: screens[
          _tab], // demo indicator is the pulsing DEMO badge in the Photos header (relay_screen)
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          // Refresh relay token when switching INTO a tab that hits /files (Photos or Files).
          // Settings + Upload don't read /files so they don't need it.
          if ((i == 0 || i == 1) && _tab != i) _loadRelayUrl();
          setState(() => _tab = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.image), label: 'Photos'),
          NavigationDestination(icon: Icon(Icons.folder), label: 'Files'),
          NavigationDestination(icon: Icon(Icons.upload), label: 'Upload'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

class _RelayUnavailableScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _RelayUnavailableScreen({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Scaffold(
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.router_outlined,
                    size: 56, color: Colors.orange),
                const SizedBox(height: 16),
                Text(message,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                    'This account does not have a server-authoritative relay URL and token. Please contact support or assign a relay in the backend.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry')),
              ]))));
}

class SettingsScreen extends StatelessWidget {
  final RelayClient relay;
  final String relayUrl;
  final void Function(String) onRelayUrlChanged;
  const SettingsScreen(
      {super.key,
      required this.relay,
      required this.relayUrl,
      required this.onRelayUrlChanged});
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
              backgroundImage:
                  user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
              child: user.avatarUrl == null
                  ? Text(user.email[0].toUpperCase())
                  : null,
            ),
            title: Text(user.name ?? user.email),
            subtitle: Text('${user.provider} · ${user.email}'),
          ),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Sign out', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await AuthService().signOut();
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove(
                  'relay_url'); // prevent next account from inheriting a stale dev/custom URL
              app.refresh();
            },
          ),
          const Divider(),
        ],
        // Version — displayed right after user info; tap to open full Update screen
        ListTile(
          leading: const Icon(Icons.tag),
          title: const Text('Version & Updates'),
          subtitle: const Text(
              'App + Relay versions, changelog, one-click relay update',
              style: TextStyle(fontSize: 12)),
          trailing: const Row(mainAxisSize: MainAxisSize.min, children: [
            Text(String.fromEnvironment('APP_VERSION', defaultValue: 'dev'),
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ]),
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => UpdateScreen(relay: relay))),
        ),
        const Divider(),
        const ListTile(
            title:
                Text('Theme', style: TextStyle(fontWeight: FontWeight.bold))),
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
        const ListTile(
            title:
                Text('Relay', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.router),
          title: const Text('Relay URL (dev/custom override)'),
          subtitle: Text(relayUrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          trailing: const Icon(Icons.edit),
          onTap: () async {
            final ctrl = TextEditingController(text: relayUrl);
            final result = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Set dev/custom Relay URL'),
                content: TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                        helperText:
                            'Logged-in production users use the server-assigned relay URL and token.',
                        hintText: 'http://localhost:8086')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      child: const Text('Save')),
                ],
              ),
            );
            if (result != null && result.isNotEmpty) onRelayUrlChanged(result);
          },
        ),
        const Divider(),
        const ListTile(
            title:
                Text('Storage', style: TextStyle(fontWeight: FontWeight.bold))),
        ListTile(
          leading: const Icon(Icons.sd_storage),
          title: const Text('Storage Strategy'),
          subtitle:
              const Text('1 file + N replicas (per SelectReplicas policy)'),
          trailing: const Icon(Icons.copy_all),
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
          leading: const Icon(Icons.backup),
          title: const Text('My Relays & Backups'),
          subtitle: const Text('View registered relays and backup status'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RelayManagementScreen()),
          ),
        ),
        const Divider(),
        const ListTile(
            title: Text('Files View',
                style: TextStyle(fontWeight: FontWeight.bold))),
        _GallerySettingsTile(),
        const Divider(),
        const ListTile(
            title: Text('Community',
                style: TextStyle(fontWeight: FontWeight.bold))),
        _SocialLinkTile(
            icon: Icons.code,
            color: const Color(0xFF24292e),
            label: 'GitHub',
            subtitle: 'Source code',
            url: 'https://github.com/dudenest/dudenest'),
        _SocialLinkTile(
            icon: Icons.forum,
            color: const Color(0xFF5865F2),
            label: 'Discord',
            subtitle: 'Community chat',
            url: 'https://discord.gg/pYjR9jS4'),
        _SocialLinkTile(
            icon: Icons.play_arrow_rounded,
            color: const Color(0xFFFF0000),
            label: 'YouTube',
            subtitle: 'Videos — coming soon'),
        _SocialLinkTile(
            icon: Icons.facebook,
            color: const Color(0xFF1877F2),
            label: 'Facebook',
            subtitle: 'Page — coming soon'),
        _SocialLinkTile(
            icon: Icons.close,
            color: Colors.black87,
            label: 'X / Twitter',
            subtitle: 'Updates — coming soon'),
      ]),
    );
  }
}

// ─── Gallery Settings Tile ────────────────────────────────────────────────────

class _GallerySettingsTile extends StatefulWidget {
  @override
  State<_GallerySettingsTile> createState() => _GallerySettingsTileState();
}

class _GallerySettingsTileState extends State<_GallerySettingsTile> {
  GallerySettings? _s;

  @override
  void initState() {
    super.initState();
    GallerySettings.load().then((s) {
      if (mounted) setState(() => _s = s);
    });
  }

  Future<void> _save() async {
    await _s?.save();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_s == null) return const SizedBox.shrink();
    final s = _s!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // View mode
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text('View mode', style: Theme.of(context).textTheme.bodySmall),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: SegmentedButton<GalleryViewMode>(
          segments: const [
            ButtonSegment(
                value: GalleryViewMode.justified,
                label: Text('Justified'),
                icon: Icon(Icons.view_stream)),
            ButtonSegment(
                value: GalleryViewMode.masonry,
                label: Text('Masonry'),
                icon: Icon(Icons.dashboard)),
            ButtonSegment(
                value: GalleryViewMode.square,
                label: Text('Square'),
                icon: Icon(Icons.grid_view)),
            ButtonSegment(
                value: GalleryViewMode.list,
                label: Text('List'),
                icon: Icon(Icons.list)),
          ],
          selected: {s.viewMode},
          onSelectionChanged: (v) {
            s.viewMode = v.first;
            _save();
          },
        ),
      ),
      // Row height (justified only) — s329 Feature 6: auto-resize toggle + slider 20-400px.
      if (s.viewMode == GalleryViewMode.justified) ...[
        SwitchListTile.adaptive(
          dense: true,
          title: const Text('Auto-resize with browser window'),
          subtitle: const Text(
              'Tiles scale proportionally to viewport (recommended)'),
          value: s.autoResizeRowHeight,
          onChanged: (v) {
            s.autoResizeRowHeight = v;
            _save();
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(children: [
            Text(
                s.autoResizeRowHeight
                    ? 'Max row height (auto): ${s.justifiedRowHeight.round()}px'
                    : 'Row height (fixed): ${s.justifiedRowHeight.round()}px',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        Slider(
          value: s.justifiedRowHeight.clamp(
              GallerySettings.minRowHeight, GallerySettings.maxRowHeight),
          min: GallerySettings
              .minRowHeight, // 20 — user request 2026-05-30 ("min 20px")
          max: GallerySettings.maxRowHeight, // 400 — extended from 320
          divisions:
              ((GallerySettings.maxRowHeight - GallerySettings.minRowHeight) /
                      10)
                  .round(),
          label: '${s.justifiedRowHeight.round()}px',
          onChanged: (v) {
            s.justifiedRowHeight = v;
            _save();
          },
        ),
      ],
      // Masonry columns
      if (s.viewMode == GalleryViewMode.masonry)
        ListTile(
          dense: true,
          title: const Text('Columns'),
          trailing: SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 2, label: Text('2')),
              ButtonSegment(value: 3, label: Text('3')),
            ],
            selected: {s.masonryColumns},
            onSelectionChanged: (v) {
              s.masonryColumns = v.first;
              _save();
            },
          ),
        ),
      // Toggles
      SwitchListTile(
        dense: true,
        title: const Text('Group by date'),
        value: s.groupByDate,
        onChanged: (v) {
          s.groupByDate = v;
          _save();
        },
      ),
      SwitchListTile(
        dense: true,
        title: const Text('Show date headers'),
        value: s.showDateHeaders,
        onChanged: s.groupByDate
            ? (v) {
                s.showDateHeaders = v;
                _save();
              }
            : null,
      ),
      SwitchListTile(
        dense: true,
        title: const Text('Date scrubbar (right side)'),
        value: s.showDateScrubbar,
        onChanged: s.groupByDate
            ? (v) {
                s.showDateScrubbar = v;
                _save();
              }
            : null,
      ),
      const Divider(),
      SwitchListTile(
        dense: true,
        title: const Text('Local tile cache'),
        value: s.localTileCacheEnabled,
        onChanged: (v) {
          s.localTileCacheEnabled = v;
          _save();
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text('Tile cache: ${s.localTileCacheMaxItems} items',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      Slider(
        value: s.localTileCacheMaxItems.toDouble(),
        min: 500,
        max: 20000,
        divisions: 39,
        label: '${s.localTileCacheMaxItems}',
        onChanged: (v) {
          s.localTileCacheMaxItems = v.round();
          _save();
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text(
            'Tile cache size: ${(s.localTileCacheMaxBytes / 1024 / 1024).round()} MB',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      Slider(
        value: (s.localTileCacheMaxBytes / 1024 / 1024).toDouble(),
        min: 2,
        max: 64,
        divisions: 31,
        label: '${(s.localTileCacheMaxBytes / 1024 / 1024).round()} MB',
        onChanged: (v) {
          s.localTileCacheMaxBytes = v.round() * 1024 * 1024;
          _save();
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text('Thumbnail memory LRU: ${s.thumbnailMemoryCacheMb} MB',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      Slider(
        value: s.thumbnailMemoryCacheMb.toDouble(),
        min: 32,
        max: 512,
        divisions: 15,
        label: '${s.thumbnailMemoryCacheMb} MB',
        onChanged: (v) {
          s.thumbnailMemoryCacheMb = v.round();
          _save();
        },
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        child: Text('Thumbnail LRU items: ${s.thumbnailMemoryCacheItems}',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      Slider(
        value: s.thumbnailMemoryCacheItems.toDouble(),
        min: 200,
        max: 5000,
        divisions: 24,
        label: '${s.thumbnailMemoryCacheItems}',
        onChanged: (v) {
          s.thumbnailMemoryCacheItems = v.round();
          _save();
        },
      ),
    ]);
  }
}

class _SocialLinkTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final String? url;
  const _SocialLinkTile(
      {required this.icon,
      required this.color,
      required this.label,
      required this.subtitle,
      this.url});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.12),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(label),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: url != null
          ? const Icon(Icons.open_in_new, size: 16, color: Colors.grey)
          : null,
      onTap: url != null
          ? () =>
              launchUrl(Uri.parse(url!), mode: LaunchMode.externalApplication)
          : null,
    );
  }
}
