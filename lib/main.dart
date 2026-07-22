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
import 'core/analytics/analytics.dart';
import 'core/network/relay_client.dart';
import 'features/auth/login_screen.dart';
import 'features/storage_accounts/accounts_screen.dart';
import 'features/upload/upload_screen.dart';
import 'features/relay/relay_screen.dart';
import 'features/update/update_screen.dart';
import 'features/relay/relay_management_screen.dart';
import 'features/files/gallery_settings.dart';
import 'features/files/direct_mode_screen.dart';
import 'core/storage/engine_config.dart';
import 'core/storage/direct_engine.dart';
import 'core/oauth/google_drive_auth.dart';

// Direct mode (E3): izolacja kont ZWERYFIKOWANA 2026-07-19 w 2 izolowanych profilach (Dudenest email ==
// Drive email na obu, zero wycieków). Włączone jako beta. Token Drive wiązany z AuthService.user.id +
// czyszczony przy wylogowaniu + select_account przy Connect. Domyślny silnik i tak = relay; user włącza
// direct w Settings. Historia/handover: docs/DIRECT-MODE-E3-TEST-HANDOVER.md.
const bool kDirectModeEnabled = true;

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
    Analytics.pageView('/photos', 'Photos');
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
  int _uploadNonce = 0;
  late RelayClient _relay;
  EngineMode _engineMode = EngineMode.relay; // feature flag: relay (default) | direct (Drive bez relaya)
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
    EngineConfig.load().then((m) {
      // Gdy direct wyłączony na prod → wymuś relay, nawet jeśli user miał zapisany direct (nie utknie).
      if (mounted) setState(() => _engineMode = kDirectModeEnabled ? m : EngineMode.relay);
    });
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
    if (!_relayReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final hasRelay = _relayUrl != null;
    final direct = kDirectModeEnabled && _engineMode == EngineMode.direct;
    final screens = [
      direct
          // ValueKey per folder: bez tego Flutter reużywa TEN SAM State między zakładkami Photos↔Files
          // (ta sama pozycja+typ w drzewie) → `_files` nie przefiltrowuje się przy zmianie folder →
          // obie zakładki pokazują to samo. Odrębny klucz = odrębny State = poprawny filtr per folder.
          ? const DirectModeScreen(key: ValueKey('direct-photos'), folder: 'photos')
          : hasRelay
              ? RelayScreen(relay: _relay, folder: 'photos')
              : _PlaceholderPhotosScreen(onUpload: _openUpload),
      direct
          ? const DirectModeScreen(key: ValueKey('direct-files'), folder: 'files')
          : hasRelay
              ? RelayScreen(relay: _relay, folder: 'files')
              : _RelayRequiredPlaceholder(
                  message: _relayError ?? 'No relay assigned to this account'),
      direct
          ? UploadScreen(
              // Direct: token bierze backend (odnawia refresh) — ciche, bez popupu. Jeśli podłączony →
              // buduj DirectEngine; jeśli nie (404) → redirect zgody (connectDrive). Token NIE w HomeScreen.
              engine: null,
              onConnect: () async {
                try {
                  await getDriveAccessToken(); // backend GET (ciche)
                  return DirectEngine(accessToken: getDriveAccessToken);
                } catch (_) {
                  await connectDrive(); // brak refresh tokena → redirect zgody (strona odchodzi)
                  return null;
                }
              },
              // Sonduj backend: podłączony → auto-connect bez klikania (parytet z relay).
              hasValidToken: () async {
                try {
                  await getDriveAccessToken();
                  return true;
                } catch (_) {
                  return false;
                }
              },
              autoPickNonce: _uploadNonce)
          : UploadScreen(
              engine: hasRelay ? _relay : null, autoPickNonce: _uploadNonce),
      SettingsScreen(
          relay: hasRelay ? _relay : null,
          relayUrl: _relayUrl,
          relayError: _relayError,
          engineMode: _engineMode,
          onEngineModeChanged: _setEngineMode,
          onRelayUrlChanged: setRelayUrl,
          onRelayClaimed: _loadRelayUrl),
    ];
    return Scaffold(
      body: screens[
          _tab], // demo indicator is the pulsing DEMO badge in the Photos header (relay_screen)
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          // Refresh relay token when switching INTO a tab that hits /files (Photos or Files).
          // Settings + Upload don't read /files so they don't need it.
          if ((i == 0 || i == 1) && _tab != i) {
            _loadRelayUrl();
          }
          setState(() {
            _tab = i;
            if (i == 2) _uploadNonce++;
          });
          if (i == 0 || i == 1 || i == 3) Analytics.pageView(analyticsPathForTab(i), analyticsTitleForTab(i));
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

  // Przełączenie silnika (feature flag). Tylko PERSYSTUJE tryb + odświeża UI; token OAuth pozyskuje
  // sam DirectModeScreen (connect-gate) — EngineFactory rzuca, gdy direct bez tokenu, więc toggle
  // nie może „po cichu" wejść w direct bez OAuth.
  Future<void> _setEngineMode(EngineMode m) async {
    // Tylko persystuj tryb + odśwież UI. Połączenie z Drive robi ekran Photos/Files (cichy auto-connect
    // gdy user już wyraził zgodę; inaczej brama Connect = pierwsza, jednorazowa zgoda Google).
    await EngineConfig.save(m);
    if (mounted) setState(() => _engineMode = m);
  }

  void _openUpload() => setState(() {
        _tab = 2;
        _uploadNonce++;
      });
}

class _RelayRequiredPlaceholder extends StatelessWidget {
  final String message;
  const _RelayRequiredPlaceholder({required this.message});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Files')),
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
                    'A relay is required to browse stored files. You can still upload after assigning or installing a relay.',
                    textAlign: TextAlign.center),
              ]))));
}

class _PlaceholderPhotosScreen extends StatelessWidget {
  final VoidCallback onUpload;
  const _PlaceholderPhotosScreen({required this.onUpload});
  @override
  Widget build(BuildContext context) {
    final dates = ['Today', 'Yesterday', 'Sunday', 'Last week'];
    return Scaffold(
        appBar: AppBar(title: const Text('Photos'), actions: [
          IconButton(
              onPressed: onUpload,
              icon: const Icon(Icons.upload),
              tooltip: 'Upload photos')
        ]),
        body: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: dates.length,
            itemBuilder: (ctx, section) =>
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                      child: Text(dates[section],
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700))),
                  GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 25,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 5,
                              crossAxisSpacing: 6,
                              mainAxisSpacing: 6),
                      itemBuilder: (ctx, i) {
                        final n = section * 25 + i;
                        return DecoratedBox(
                            decoration: BoxDecoration(
                                color: Colors
                                    .primaries[n % Colors.primaries.length]
                                    .shade100,
                                borderRadius: BorderRadius.circular(8)),
                            child: Center(
                                child: Icon(Icons.image,
                                    color: Colors
                                        .primaries[n % Colors.primaries.length]
                                        .shade400,
                                    size: 20)));
                      }),
                ])));
  }
}

class SettingsScreen extends StatelessWidget {
  final RelayClient? relay;
  final String? relayUrl;
  final String? relayError;
  final EngineMode engineMode;
  final void Function(EngineMode) onEngineModeChanged;
  final void Function(String) onRelayUrlChanged;
  final Future<void> Function() onRelayClaimed;
  const SettingsScreen(
      {super.key,
      required this.relay,
      required this.relayUrl,
      this.relayError,
      required this.engineMode,
      required this.onEngineModeChanged,
      required this.onRelayUrlChanged,
      required this.onRelayClaimed});
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
              await clearDriveToken(); // 🔒 skasuj token Drive — inaczej następny user dziedziczy dostęp
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
          enabled: relay != null,
          onTap: relay == null
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => UpdateScreen(relay: relay!))),
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
        if (kDirectModeEnabled) ...[
          const Divider(),
          const ListTile(
              title: Text('Storage engine (experimental)',
                  style: TextStyle(fontWeight: FontWeight.bold))),
          SwitchListTile(
            secondary: const Icon(Icons.cloud_sync),
            title: const Text('Direct mode (Google Drive without relay)'),
            subtitle: const Text(
                'Photos/Files read files straight from your Google Drive (drive.file). '
                'Beta — Google sign-in on entry. Off = relay (default).',
                style: TextStyle(fontSize: 12)),
            value: engineMode == EngineMode.direct,
            onChanged: (v) =>
                onEngineModeChanged(v ? EngineMode.direct : EngineMode.relay),
          ),
        ],
        const Divider(),
        const ListTile(
            title:
                Text('Relay', style: TextStyle(fontWeight: FontWeight.bold))),
        if (relayUrl != null)
          _RelayUrlTile(
              relayUrl: relayUrl!, onRelayUrlChanged: onRelayUrlChanged)
        else
          _NoRelaySettings(
              relayError: relayError,
              onRelayUrlChanged: onRelayUrlChanged,
              onRelayClaimed: onRelayClaimed),
        const Divider(),
        const ListTile(
            title:
                Text('Storage', style: TextStyle(fontWeight: FontWeight.bold))),
        const ListTile(
          leading: Icon(Icons.sd_storage),
          title: Text('Storage Strategy'),
          subtitle: Text('1 file + N replicas (per SelectReplicas policy)'),
          trailing: Icon(Icons.copy_all),
        ),
        ListTile(
          leading: const Icon(Icons.cloud),
          title: const Text('Cloud Accounts'),
          subtitle: const Text('Connected Google Drive accounts'),
          trailing: const Icon(Icons.chevron_right),
          enabled: relay != null,
          onTap: relay == null
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AccountsScreen(relay: relay!)),
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
        const _SocialLinkTile(
            icon: Icons.code,
            color: Color(0xFF24292e),
            label: 'GitHub',
            subtitle: 'Source code',
            url: 'https://github.com/dudenest/dudenest'),
        const _SocialLinkTile(
            icon: Icons.forum,
            color: Color(0xFF5865F2),
            label: 'Discord',
            subtitle: 'Community chat',
            url: 'https://discord.gg/pYjR9jS4'),
        const _SocialLinkTile(
            icon: Icons.play_arrow_rounded,
            color: Color(0xFFFF0000),
            label: 'YouTube',
            subtitle: 'Videos — coming soon'),
        const _SocialLinkTile(
            icon: Icons.facebook,
            color: Color(0xFF1877F2),
            label: 'Facebook',
            subtitle: 'Page — coming soon'),
        const _SocialLinkTile(
            icon: Icons.close,
            color: Colors.black87,
            label: 'X / Twitter',
            subtitle: 'Updates — coming soon'),
      ]),
    );
  }
}

class _RelayUrlTile extends StatelessWidget {
  final String relayUrl;
  final void Function(String) onRelayUrlChanged;
  const _RelayUrlTile(
      {required this.relayUrl, required this.onRelayUrlChanged});
  @override
  Widget build(BuildContext context) => ListTile(
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
                    ]));
        if (result != null && result.isNotEmpty) onRelayUrlChanged(result);
      });
}

class _LocalRelayCandidate {
  final String url;
  final String relayID;
  final String status;
  final String version;
  const _LocalRelayCandidate(
      {required this.url,
      required this.relayID,
      required this.status,
      required this.version});
}

class _NoRelaySettings extends StatefulWidget {
  final String? relayError;
  final void Function(String) onRelayUrlChanged;
  final Future<void> Function() onRelayClaimed;
  const _NoRelaySettings(
      {required this.relayError,
      required this.onRelayUrlChanged,
      required this.onRelayClaimed});
  @override
  State<_NoRelaySettings> createState() => _NoRelaySettingsState();
}

class _NoRelaySettingsState extends State<_NoRelaySettings> {
  final _client = http.Client();
  _LocalRelayCandidate? _candidate;
  bool _scanning = false;
  bool _claiming = false;
  String? _scanError;
  String _scanStatus = 'Preparing local relay scan…';
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _scanLocalRelays();
    _retryTimer = Timer.periodic(const Duration(seconds: 12), (_) {
      if (!_scanning && _candidate == null) _scanLocalRelays(auto: true);
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _client.close();
    super.dispose();
  }

  Future<void> _scanLocalRelays({bool auto = false}) async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _scanError = null;
      _scanStatus = auto
          ? 'Retrying local relay scan…'
          : 'Scanning likely relay addresses first…';
    });
    final likelyHosts = [89, 1, 2, 10, 50, 100, 101, 119, 200, 254];
    final likely = <String>{
      for (final prefix in ['192.168.0', '192.168.1'])
        for (final host in likelyHosts) 'http://$prefix.$host:8086'
    }.toList();
    const prefixes = [
      '192.168.0',
      '192.168.1',
      '192.168.2',
      '192.168.86',
      '10.0.0',
      '10.0.1'
    ];
    try {
      for (final url in likely) {
        if (!mounted) return;
        setState(() => _scanStatus = 'Checking $url');
        final found = await _probeRelay(url);
        if (found != null) {
          setState(() {
            _candidate = found;
            _scanning = false;
            _scanStatus = 'Found local relay';
          });
          return;
        }
      }
      for (final prefix in prefixes) {
        for (var start = 1; start <= 254; start += 16) {
          if (!mounted) return;
          setState(() => _scanStatus =
              'Scanning $prefix.$start-${(start + 15).clamp(1, 254)}');
          final batch = <Future<_LocalRelayCandidate?>>[];
          for (var host = start; host < start + 16 && host <= 254; host++) {
            batch.add(_probeRelay('http://$prefix.$host:8086'));
          }
          _LocalRelayCandidate? found;
          for (final result in await Future.wait(batch)) {
            if (result != null) {
              found = result;
              break;
            }
          }
          if (!mounted) return;
          if (found != null) {
            setState(() {
              _candidate = found;
              _scanning = false;
              _scanStatus = 'Found local relay';
            });
            return;
          }
        }
      }
      if (mounted) {
        setState(() {
          _scanError =
              'No local relay found yet — retrying automatically every 12 seconds';
          _scanStatus = 'Scan finished; waiting before retry';
        });
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<_LocalRelayCandidate?> _probeRelay(String baseUrl) async {
    try {
      final resp = await _client
          .get(Uri.parse('$baseUrl/pairing/info'))
          .timeout(const Duration(milliseconds: 2500));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['pairing_mode'] != 'local' || data['path'] != '/pairing/info') {
        return null;
      }
      return _LocalRelayCandidate(
          url: baseUrl,
          relayID: data['relay_id'] as String? ?? '',
          status: data['status'] as String? ?? 'unknown',
          version: data['version'] as String? ?? 'unknown');
    } catch (_) {
      return null;
    }
  }

  Future<void> _manualRelay(String raw) async {
    final url = _normalizeRelayUrl(raw);
    setState(() {
      _scanning = true;
      _scanError = null;
      _scanStatus = 'Checking manual relay $url';
    });
    final found = await _probeRelay(url);
    if (!mounted) return;
    setState(() {
      _scanning = false;
      if (found != null) {
        _candidate = found;
        _scanStatus = 'Found manual relay';
      } else {
        _scanError = 'Manual relay did not respond to /pairing/info';
        _scanStatus = 'Manual relay check failed';
      }
    });
  }

  String _normalizeRelayUrl(String raw) {
    final value = raw.trim();
    final withScheme = value.startsWith('http') ? value : 'http://$value';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.hasPort || uri.host.isEmpty) return withScheme;
    return uri.replace(port: 8086).toString();
  }

  Future<void> _claimRelay() async {
    final token = AuthService().token;
    if (token == null || _candidate == null || _claiming) return;
    if (_candidate!.relayID.isEmpty) {
      setState(() => _scanError =
          'Relay has no relay_id yet; wait for provisioning to finish, then scan again.');
      return;
    }
    setState(() => _claiming = true);
    try {
      final resp = await http.get(
        Uri.https('api.dudenest.com', '/api/v1/relay/discover',
            {'relay_id': _candidate!.relayID}),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        throw 'Claim failed (HTTP ${resp.statusCode}): ${resp.body}';
      }
      await widget.onRelayClaimed();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Relay paired with this account')));
    } catch (e) {
      if (mounted) setState(() => _scanError = e.toString());
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
            leading: const Icon(Icons.warning_amber, color: Colors.orange),
            title: const Text('No relay assigned to this account'),
            subtitle: Text(widget.relayError ?? 'Cannot load relay')),
        ListTile(
            leading: _scanning
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.router_outlined),
            title: Text(_candidate == null
                ? 'Scanning for local relay…'
                : 'Add local relay ${_candidate!.url}'),
            subtitle: Text(_candidate == null
                ? '${_scanError ?? 'Looking for a Dudenest relay on this network'}\n$_scanStatus'
                : 'Relay ${_candidate!.relayID.isEmpty ? 'unregistered' : _candidate!.relayID} · ${_candidate!.status} · ${_candidate!.version}'),
            trailing: _candidate == null
                ? TextButton(
                    onPressed: _scanning ? null : _scanLocalRelays,
                    child: const Text('Scan'))
                : FilledButton(
                    onPressed: _claiming ? null : _claimRelay,
                    child: Text(_claiming ? 'Pairing…' : 'Claim'))),
        const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Add remote relay'),
            subtitle: Text('Coming soon'),
            enabled: false),
        ListTile(
            leading: const Icon(Icons.computer),
            title: const Text('Install new relay Virtual Machine'),
            subtitle: const Text('Show install command'),
            onTap: () => showDialog<void>(
                context: context,
                builder: (ctx) => AlertDialog(
                        title: const Text('Install relay VM'),
                        content: const SelectableText(
                            'curl -sSL https://raw.githubusercontent.com/dudenest/dudenest-relay/main/scripts/install.sh | sudo bash'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'))
                        ]))),
        ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Enter new relay code'),
            subtitle: const Text('Advanced dev/custom/manual address or code'),
            onTap: () async {
              final ctrl = TextEditingController();
              final result = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                          title: const Text(
                              'Enter dev/custom relay address or code'),
                          content: TextField(
                              controller: ctrl,
                              decoration: const InputDecoration(
                                  helperText:
                                      'Manual entry is not secure production pairing.',
                                  hintText:
                                      'http://192.168.1.50:8086 or code')),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel')),
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(ctx, ctrl.text.trim()),
                                child: const Text('Save')),
                          ]));
              if (result != null && result.isNotEmpty) {
                await _manualRelay(result);
              }
            }),
      ]);
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
