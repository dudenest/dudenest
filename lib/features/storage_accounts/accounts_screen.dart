import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/relay_client.dart';
import '../../core/oauth/oauth_service.dart';
import 'storage_visualizer.dart';

class AccountsScreen extends StatefulWidget {
  final RelayClient relay;
  const AccountsScreen({super.key, required this.relay});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  // Legacy /providers data — still drives StorageVisualizer + per-token auth status.
  List<Map<String, dynamic>> _providers = [];
  // Phase α/β /admin/accounts data — drives the new richer list (priority, role, quota).
  // Keyed by account ID for fast lookup when merging with legacy provider data.
  Map<int, Map<String, dynamic>> _adminAccounts = {};
  // Global policy (replication_factor, soft_cap, etc.) — surfaced in a header card.
  Map<String, dynamic> _adminPolicy = {};
  // s320 Phase 1: per-provider scan engine state (last scan time, files indexed, errors).
  // Keyed by provider ID (e.g. "gdrive:user@gmail.com"). Empty when scan endpoint unreachable.
  Map<String, Map<String, dynamic>> _scanStatus = {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Fetch in parallel: legacy /providers (token health) + /admin/accounts (priority/role/quota) + /admin/scan/status (s320 Phase 1).
      final results = await Future.wait([
        widget.relay.getProviders(),
        widget.relay.getAdminAccounts().catchError((e) {
          // /admin/accounts is Phase α+ — older relays return 404. Tolerate gracefully so
          // the UI degrades to legacy behavior instead of erroring out entirely.
          debugPrint('AccountsScreen: /admin/accounts unavailable (older relay?): $e');
          return <String, dynamic>{'accounts': <dynamic>[], 'policy': <String, dynamic>{}};
        }),
        widget.relay.getScanStatus().catchError((e) { // s320 Phase 1: tolerate older relays without /admin/scan
          debugPrint('AccountsScreen: /admin/scan/status unavailable: $e');
          return <String, dynamic>{};
        }),
      ]);
      final providers = results[0] as List<Map<String, dynamic>>;
      final adminData = results[1] as Map<String, dynamic>;
      final scanData = results[2] as Map<String, dynamic>;
      final accountsList = (adminData['accounts'] as List?) ?? const [];
      final accountsByID = <int, Map<String, dynamic>>{
        for (final a in accountsList) (a as Map<String, dynamic>)['id'] as int: Map<String, dynamic>.from(a),
      };
      // scanData shape: {providerID: {state, started_at, last_finished_at, files_discovered, ...}}
      // Defensive: skip entries whose value isn't a Map (e.g. MockClient in widget tests returning unrelated JSON).
      final scanByID = <String, Map<String, dynamic>>{
        for (final e in scanData.entries)
          if (e.value is Map) e.key: Map<String, dynamic>.from(e.value as Map),
      };
      setState(() {
        _providers = providers;
        _adminAccounts = accountsByID;
        _adminPolicy = Map<String, dynamic>.from((adminData['policy'] as Map?) ?? {});
        _scanStatus = scanByID;
        _loading = false;
      });
    } catch (e) {
      debugPrint('AccountsScreen load error: $e');
      setState(() { _error = e; _loading = false; });
    }
  }

  // s320 Phase 1: lookup scan state for a provider — matches on "type:email" provider ID.
  Map<String, dynamic>? _scanFor(Map<String, dynamic> provider) {
    final type = (provider['type'] ?? 'gdrive') as String;
    final email = (provider['email'] ?? '') as String;
    return _scanStatus['$type:$email'];
  }

  // Find the admin account record for a legacy provider entry, matching on type+email.
  // Returns null when no admin record exists (older relay, or provider not yet bootstrapped).
  Map<String, dynamic>? _adminFor(Map<String, dynamic> provider) {
    final email = (provider['email'] ?? '') as String;
    final type = (provider['type'] ?? 'gdrive') as String;
    for (final acc in _adminAccounts.values) {
      if (acc['email'] == email && acc['provider'] == type) return acc;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cloud Accounts'),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list), text: 'Accounts'),
              Tab(icon: Icon(Icons.insights), text: 'Visualizer'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.add),
          label: const Text('Add Account'),
          onPressed: () async {
            await showModalBottomSheet(
              context: context, isScrollControlled: true, useSafeArea: true,
              builder: (_) => _AddAccountSheet(relay: widget.relay),
            );
            _load();
          },
        ),
        body: TabBarView(
          children: [
            _buildList(),
            StorageVisualizer(relay: widget.relay),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorDisplay(error: _error!, onRetry: _load);
    if (_providers.isEmpty) return _emptyState(context);

    // Sort providers by admin priority (when available) so users see them in the order the
    // selection algorithm actually picks them.
    final sortedProviders = [..._providers]..sort((a, b) {
      final pa = _adminFor(a)?['priority'] as int? ?? 999;
      final pb = _adminFor(b)?['priority'] as int? ?? 999;
      return pa.compareTo(pb);
    });
    // s329 fix: ReorderableListView is enabled whenever any admin metadata is loaded. The previous
    // canReorder gate also required `sortedProviders.any((p) => _adminFor(p) != null)` which was a
    // fragile second check — empirically on Chrome/Safari/Firefox desktop the gate evaluated false
    // and silently fell through to a plain ListView (no drag-handle, no Reorder semantic node),
    // even though /admin/accounts returned 3 matched accounts. Single source of truth = the load
    // result itself. Providers without admin metadata still render in the list; onReorder filters
    // them out of the payload so the backend never sees an unknown id.
    final canReorder = _adminAccounts.isNotEmpty;
    return Column(children: [
      _StorageSummaryCard(providers: _providers),
      if (_adminPolicy.isNotEmpty) _PolicyCard(policy: _adminPolicy, relay: widget.relay, onChanged: _load),
      Expanded(child: canReorder
        ? ReorderableListView.builder(
            itemCount: sortedProviders.length,
            // s329 fix #3 (final): two empirically-observed Flutter web canvaskit failure modes
            // forced this third iteration:
            //   1. buildDefaultDragHandles=true → handle renders Icons.drag_handle BUT on web with mouse
            //      it requires long-press timing (no mouse-down=drag), so user "nie może złapać".
            //   2. Icons.drag_handle / Icons.drag_indicator codepoints in bundled MaterialIcons font
            //      paint as wrong glyph on production (e.g. fix#2 ☰ rendered as folder-looking icon).
            //      Same family of bugs as s319 Icons.tune / Icons.photo_library codepoint shifts.
            // Fix: wrap whole tile in custom ReorderableDragStartListener (mouse-down = drag), and use
            // a pure-paint `_DragHandleHamburger` widget (no Material Icons font dependency) as the
            // visual affordance. Cannot fail to render — three Container lines + Colors.grey.
            buildDefaultDragHandles: false,
            onReorder: (oldIdx, newIdx) async {
              if (newIdx > oldIdx) newIdx -= 1; // Flutter quirk: insertion index after removal
              final movedProvider = sortedProviders[oldIdx];
              final newOrderProviders = [...sortedProviders]..removeAt(oldIdx)..insert(newIdx, movedProvider);
              // Drop providers without admin id from reorder payload — relay accepts subset (only re-prioritizes known ids).
              final newIDs = newOrderProviders.map((p) => _adminFor(p)?['id'] as int?).whereType<int>().toList();
              if (newIDs.isEmpty) return; // nothing reorderable in the new sequence
              try {
                await widget.relay.reorderAdminAccounts(newIDs);
                await _load();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Reorder failed: $e'), backgroundColor: Colors.red),
                );
              }
            },
            itemBuilder: (ctx, i) {
              final p = sortedProviders[i];
              final admin = _adminFor(p);
              final keyId = admin?['id'] ?? p['email'] ?? p['id'] ?? i;
              final tileKey = ValueKey('account-$keyId'); // stable key required by ReorderableListView
              final tile = _AccountListTile(
                provider: p, admin: admin, scan: _scanFor(p), relay: widget.relay, onChanged: _load,
                showHamburger: admin != null, // s329 #3: paint the always-visible handle inside the tile header
                onReconnect: () async {
                  await showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true,
                    builder: (_) => _AddAccountSheet(relay: widget.relay));
                  _load();
                },
              );
              // Wrap admin-matched tiles in the immediate-drag listener — clicking ANYWHERE on the
              // Card body triggers reorder (matches user expectation "łapię i ciągnę"). Orphan tiles
              // (admin==null) skip the wrapper so they cannot be dragged into the reorder payload.
              if (admin == null) return KeyedSubtree(key: tileKey, child: tile);
              return ReorderableDragStartListener(key: tileKey, index: i, child: tile);
            },
          )
        : ListView.builder(
            itemCount: sortedProviders.length,
            itemBuilder: (ctx, i) {
              final p = sortedProviders[i];
              final admin = _adminFor(p);
              return _AccountListTile(
                provider: p, admin: admin, scan: _scanFor(p), relay: widget.relay, onChanged: _load,
                onReconnect: () async {
                  await showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true,
                    builder: (_) => _AddAccountSheet(relay: widget.relay));
                  _load();
                },
              );
            },
          )),
    ]);
  }

  Widget _providerIcon(String type, bool available) {
    final color = available ? Colors.green : Colors.grey;
    return switch (type) {
      'gdrive'   => Icon(Icons.drive_folder_upload, color: color),
      'mega'     => Icon(Icons.storage, color: color),
      'onedrive' => Icon(Icons.cloud, color: color),
      _          => Icon(Icons.cloud, color: color),
    };
  }

  Widget _emptyState(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
      const SizedBox(height: 16),
      const Text('No storage accounts', style: TextStyle(fontSize: 16)),
      const SizedBox(height: 8),
      const Text('Add a cloud storage account to start storing files.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add Account'),
        onPressed: () async {
          await showModalBottomSheet(
            context: context, isScrollControlled: true, useSafeArea: true,
            builder: (_) => _AddAccountSheet(relay: relay),
          );
          _load();
        },
      ),
    ]),
  );

  RelayClient get relay => widget.relay;
}

// ─── Error Display Widget ───────────────────────────────────────────────────

class _ErrorDisplay extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorDisplay({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    String msg = error.toString();
    String? body;
    int? code;
    if (error is RelayException) {
      final re = error as RelayException;
      msg = re.message;
      code = re.statusCode;
      body = re.body;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: $msg', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          if (code != null) ...[
            const SizedBox(height: 8),
            Text('Status Code: $code', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(body.length > 500 ? body.substring(0, 500) + '...' : body,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'), maxLines: 10, overflow: TextOverflow.ellipsis),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

// ─── Add Account Sheet ────────────────────────────────────────────────────────

enum _AddStep { selectProvider, selectMethod, oauthFlow, browserFlow, webviewCredentials, webviewFlow, done }
enum _AuthMethod { flutterOAuth, browserAuth, webviewOAuth }

class _AddAccountSheet extends StatefulWidget {
  final RelayClient relay;
  const _AddAccountSheet({required this.relay});
  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> with SingleTickerProviderStateMixin {
  _AddStep _step = _AddStep.selectProvider;
  _AuthMethod _method = _AuthMethod.flutterOAuth;
  String _selectedProvider = 'gdrive';

  // OAuth (Method A) state
  bool _oauthBusy = false;
  String? _oauthEmail;
  String? _oauthError;

  // Browser Auth (Method B) state — chromedp / noVNC
  String? _sessionId;
  Map<String, dynamic>? _currentStep;
  bool _browserBusy = false;
  String? _browserError;
  String? _vncUrl; // set when relay returns vnc_ready — enables noVNC waiting UI
  WebSocketChannel? _wsChannel; // listens for auth_done from relay
  Timer? _pollTimer; // polling fallback — checks /providers every 3s in case WS misses auth_done
  int _pollProviderCount = 0; // snapshot of provider count before auth started
  late AnimationController _pulseCtrl; // drives green button pulse
  late Animation<double> _pulseAnim;
  final _ctrl = TextEditingController();

  // WebView Auth (Method E) state — in-app WebView with auto-fill
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  WebViewController? _webviewCtrl;
  bool _webviewBusy = false;
  String? _webviewError;

  @override
  void initState() { super.initState(); _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true); _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut)); }
  @override
  void dispose() { _pulseCtrl.dispose(); _ctrl.dispose(); _emailCtrl.dispose(); _passwordCtrl.dispose(); _phoneCtrl.dispose(); _wsChannel?.sink.close(); _pollTimer?.cancel(); super.dispose(); }

  // ── Method A: Flutter-side OAuth (user's IP ✅) ──

  Future<void> _startOAuth() async {
    setState(() { _oauthBusy = true; _oauthError = null; });
    try {
      final oauth = OAuthService(widget.relay);
      final email = await oauth.addProvider(_selectedProvider);
      setState(() { _oauthEmail = email; _step = _AddStep.done; _oauthBusy = false; });
    } catch (e) {
      setState(() { _oauthError = e.toString(); _oauthBusy = false; });
    }
  }

  // ── Method B: Browser Auth — noVNC (relay opens Chromium, user interacts via VNC in browser) ──

  Future<void> _startBrowserSession() async {
    setState(() { _browserBusy = true; _browserError = null; });
    try {
      // Snapshot providers before auth — polling detects both new AND re-authed (available: false → true)
      final beforeProviders = await widget.relay.getProviders().catchError((_) => <Map<String, dynamic>>[]);
      _pollProviderCount = beforeProviders.length;
      final step = await widget.relay.startAuthSession(_selectedProvider);
      final status = step['status'] as String?;
      final sid = step['session_id'] as String?;
      if (status == 'vnc_ready') {
        final vnc = step['vnc_url'] as String?;
        setState(() { _sessionId = sid; _vncUrl = vnc; _step = _AddStep.browserFlow; _browserBusy = false; });
        // NOTE: do NOT call launchUrl here — browsers block window.open() outside of user gesture.
        // On web: user must click "Sign in" button below (direct click = no popup block).
        // On mobile: WebView shown inline in _buildVNCWaitingFlow.
        _listenForAuthDone(); // WebSocket primary path
        _startPollingFallback(beforeProviders); // polling fallback: detects new + re-authed providers
      } else {
        setState(() { _sessionId = sid; _currentStep = step; _step = _AddStep.browserFlow; _browserBusy = false; });
      }
    } catch (e) {
      setState(() { _browserError = e.toString(); _browserBusy = false; });
    }
  }

  void _listenForAuthDone() {
    _wsChannel?.sink.close();
    _wsChannel = WebSocketChannel.connect(Uri.parse(widget.relay.wsUrl));
    _wsChannel!.stream.listen((msg) {
      try {
        final data = jsonDecode(msg.toString()) as Map<String, dynamic>;
        if (data['type'] == 'auth_done') {
          final email = data['email'] as String?;
          if (mounted) setState(() { _oauthEmail = email; _step = _AddStep.done; });
          _wsChannel?.sink.close();
          _pollTimer?.cancel();
        }
      } catch (_) {}
    }, onError: (_) {}, onDone: () {});
  }

  // Polling fallback: checks /providers every 3s
  // Detects: (1) new provider added, (2) previously unavailable provider became available (re-auth)
  void _startPollingFallback(List<Map<String, dynamic>> beforeProviders) {
    final countBefore = beforeProviders.length;
    // Emails of providers that were unavailable before auth — re-auth makes them available again
    final unavailableBefore = beforeProviders
        .where((p) => p['available'] != true)
        .map((p) => p['email'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toSet();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_step == _AddStep.done) { _pollTimer?.cancel(); return; }
      try {
        final providers = await widget.relay.getProviders();
        final newlyAvailable = providers.where(
          (p) => unavailableBefore.contains(p['email'] as String? ?? '') && p['available'] == true
        ).toList();
        Map<String, dynamic>? resolved;
        if (providers.length > countBefore) resolved = providers.last; // new provider
        else if (newlyAvailable.isNotEmpty) resolved = newlyAvailable.first; // re-authed provider
        if (resolved != null) {
          final email = resolved['email'] as String?;
          if (mounted) setState(() { _oauthEmail = email; _step = _AddStep.done; });
          _pollTimer?.cancel();
          _wsChannel?.sink.close();
        }
      } catch (_) {}
    });
  }

  Future<void> _submitBrowserField() async {
    final sid = _sessionId;
    final stepData = _currentStep;
    if (sid == null || stepData == null) return;
    final fields = (stepData['fields'] as List? ?? []).cast<Map<String, dynamic>>();
    if (fields.isEmpty) return;
    final field = fields.first;
    final selector = field['selector'] as String? ?? '';
    setState(() { _browserBusy = true; _browserError = null; });
    try {
      final next = await widget.relay.authInput(sid, selector, _ctrl.text.trim());
      _ctrl.clear();
      if ((next['status'] as String?) == 'done') {
        setState(() { _step = _AddStep.done; _browserBusy = false; });
      } else {
        setState(() { _currentStep = next; _browserBusy = false; });
      }
    } catch (e) {
      setState(() { _browserError = e.toString(); _browserBusy = false; });
    }
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9, minChildSize: 0.4, maxChildSize: 0.95, expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: switch (_step) {
          _AddStep.selectProvider      => _buildProviderSelect(scrollCtrl),
          _AddStep.selectMethod        => _buildMethodSelect(scrollCtrl),
          _AddStep.oauthFlow           => _buildOAuthFlow(scrollCtrl),
          _AddStep.browserFlow         => _buildBrowserFlow(scrollCtrl),
          _AddStep.webviewCredentials  => _buildWebViewCredentials(scrollCtrl),
          _AddStep.webviewFlow         => _buildWebViewFlow(),
          _AddStep.done                => _buildDone(),
        },
      ),
    );
  }

  // Step 1: Choose provider
  Widget _buildProviderSelect(ScrollController sc) => ListView(
    controller: sc,
    padding: const EdgeInsets.all(24),
    children: [
      const Text('Add Storage Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Connect a cloud storage provider. Your files will be encrypted and split across providers.',
          style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      _ProviderTile(
        initial: 'G', color: const Color(0xFF4285F4),
        title: 'Google Drive', subtitle: '15 GB free',
        onTap: () => setState(() { _selectedProvider = 'gdrive'; _step = _AddStep.selectMethod; }),
      ),
      const Divider(),
      _ProviderTile(
        icon: Icons.storage, color: Colors.orange,
        title: 'MEGA.nz', subtitle: '20 GB free',
        onTap: () => setState(() { _selectedProvider = 'mega'; _step = _AddStep.selectMethod; }),
      ),
      const Divider(),
      _ProviderTile(
        icon: Icons.cloud, color: const Color(0xFF0078D4),
        title: 'OneDrive', subtitle: '5 GB free · coming soon',
        enabled: false,
      ),
    ],
  );

  // Step 2: Choose auth method
  Widget _buildMethodSelect(ScrollController sc) => ListView(
    controller: sc,
    padding: const EdgeInsets.all(24),
    children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back_ios_new), padding: EdgeInsets.zero,
            onPressed: () => setState(() => _step = _AddStep.selectProvider)),
        const SizedBox(width: 8),
        const Text('Login Method', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      const Text('How do you want to connect?', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      // Method A — recommended
      Card(
        child: ListTile(
          leading: const CircleAvatar(child: Icon(Icons.open_in_browser)),
          title: const Text('Login via your browser'),
          subtitle: const Text('Recommended · Your IP is used · Works with any relay'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() { _method = _AuthMethod.flutterOAuth; _step = _AddStep.oauthFlow; _startOAuth(); }),
        ),
      ),
      const SizedBox(height: 12),
      // Method E — in-app WebView auto-fill (native only, user's IP ✅)
      if (!kIsWeb) Card(
        child: ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.auto_fix_high, color: Colors.white)),
          title: const Text('Auto-fill in app'),
          subtitle: const Text('Enter email & password · Your IP · No browser switch'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() { _method = _AuthMethod.webviewOAuth; _step = _AddStep.webviewCredentials; }),
        ),
      ),
      if (!kIsWeb) const SizedBox(height: 12),
      // Method B — self-hosted only
      Card(
        child: ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.computer, color: Colors.white)),
          title: const Text('Relay browser (automated)'),
          subtitle: const Text('Self-hosted relay only · Uses relay\'s IP'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => setState(() { _method = _AuthMethod.browserAuth; _step = _AddStep.browserFlow; _startBrowserSession(); }),
        ),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
        child: const Row(children: [
          Icon(Icons.info_outline, color: Colors.blue, size: 18),
          SizedBox(width: 8),
          Expanded(child: Text(
            'For best security, use "Login via your browser" — Google sees your personal IP for each account.',
            style: TextStyle(fontSize: 12, color: Colors.blue),
          )),
        ]),
      ),
    ],
  );

  // Step 3A: Flutter OAuth — opens system browser, shows spinner
  Widget _buildOAuthFlow(ScrollController sc) => ListView(
    controller: sc,
    padding: const EdgeInsets.all(32),
    children: [
      const Icon(Icons.open_in_browser, size: 64, color: Colors.blue),
      const SizedBox(height: 24),
      const Text('Opening browser...', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
      const SizedBox(height: 8),
      const Text('Sign in to your Google account in the browser that just opened.\n\nYour personal IP is used for this login — Google sees it as your own account.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 32),
      if (_oauthBusy) ...[
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        const Text('Waiting for approval...', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      ],
      if (_oauthError != null) ...[
        Text(_oauthError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: () => setState(() { _oauthError = null; _startOAuth(); }), child: const Text('Retry')),
        TextButton(
          onPressed: () => setState(() { _step = _AddStep.selectMethod; }),
          child: const Text('Use different method'),
        ),
      ],
    ],
  );

  // Step 3B: Browser Auth — noVNC waiting UI or legacy screenshot+input
  Widget _buildBrowserFlow(ScrollController sc) {
    if (_vncUrl != null) return _buildVNCWaitingFlow(sc); // noVNC flow: VNC opened in browser tab
    // Loading state — waiting for /auth/session response
    if (_browserBusy) return ListView(controller: sc, padding: const EdgeInsets.all(32), children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back_ios_new), padding: EdgeInsets.zero,
            onPressed: () => setState(() => _step = _AddStep.selectMethod)),
        const SizedBox(width: 8),
        const Text('Browser Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 48),
      const Center(child: CircularProgressIndicator()),
      const SizedBox(height: 16),
      const Text('Opening login page on relay...', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
    ]);
    // Legacy screenshot+input flow (relay without noVNC)
    final stepData = _currentStep ?? {};
    final fields = (stepData['fields'] as List? ?? []).cast<Map<String, dynamic>>();
    final screenshotB64 = stepData['screenshot_b64'] as String?;
    final field = fields.isNotEmpty ? fields.first : null;
    final fieldType = field?['type'] as String? ?? 'text';
    final fieldLabel = field?['label'] as String? ?? 'Enter value';
    final isInfo = fieldType == 'info';
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new), padding: EdgeInsets.zero,
              onPressed: () { widget.relay.authClose(_sessionId ?? ''); Navigator.pop(context); }),
          const SizedBox(width: 8),
          const Text('Browser Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        if (screenshotB64 != null && screenshotB64.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(base64Decode(screenshotB64), height: 240, fit: BoxFit.cover, gaplessPlayback: true),
          ),
        const SizedBox(height: 16),
        if (_browserError != null) ...[
          Text(_browserError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        if (isInfo) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.info_outline, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(child: Text(fieldLabel, style: const TextStyle(color: Colors.blue))),
            ]),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _browserBusy ? null : _submitBrowserField, child: const Text('Continue')),
        ] else if (field != null) ...[
          Text(fieldLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            obscureText: fieldType == 'password',
            keyboardType: (fieldType == 'number' || fieldType == 'tel') ? TextInputType.phone : TextInputType.emailAddress,
            decoration: InputDecoration(hintText: fieldLabel, border: const OutlineInputBorder()),
            onSubmitted: (_) => _browserBusy ? null : _submitBrowserField(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _browserBusy ? null : _submitBrowserField,
            child: _browserBusy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue'),
          ),
        ],
      ],
    );
  }

  // noVNC waiting UI — shown while user authenticates
  // Mobile: embedded WebView with noVNC; Web/desktop: button that opens VNC in browser tab
  Widget _buildVNCWaitingFlow(ScrollController sc) {
    // Mobile: show WebView with noVNC inline (user authenticates inside the app)
    if (!kIsWeb && _vncUrl != null && _webviewCtrl == null) {
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(_vncUrl!));
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) setState(() => _webviewCtrl = ctrl); });
    }
    if (!kIsWeb && _webviewCtrl != null) {
      return Column(children: [
        AppBar(
          leading: IconButton(icon: const Icon(Icons.close),
              onPressed: () { widget.relay.authClose(_sessionId ?? ''); _wsChannel?.sink.close(); _pollTimer?.cancel(); Navigator.pop(context); }),
          title: const Text('Sign in to Google'),
          actions: [const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))],
        ),
        Expanded(child: WebViewWidget(controller: _webviewCtrl!)),
      ]);
    }
    // Web/desktop: user must click to open VNC (popup blocker requires direct user gesture)
    return ListView(
      controller: sc,
      padding: const EdgeInsets.all(32),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new), padding: EdgeInsets.zero,
              onPressed: () { widget.relay.authClose(_sessionId ?? ''); _wsChannel?.sink.close(); _pollTimer?.cancel(); Navigator.pop(context); }),
          const SizedBox(width: 8),
          const Text('Browser Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 32),
        const Icon(Icons.computer, size: 64, color: Colors.blue),
        const SizedBox(height: 24),
        const Text('Sign in to Google', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Tap the button below to open the Google login page.\nAfter signing in, this screen will update automatically.',
            textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 32),
        if (_vncUrl != null) AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Opacity(
            opacity: _pulseAnim.value,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open login'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
              ),
              onPressed: () => launchUrl(Uri.parse(_vncUrl!), mode: LaunchMode.externalApplication),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          icon: const Icon(Icons.close, size: 18),
          label: const Text('Cancel'),
          style: TextButton.styleFrom(foregroundColor: Colors.grey),
          onPressed: () { widget.relay.authClose(_sessionId ?? ''); _wsChannel?.sink.close(); _pollTimer?.cancel(); Navigator.pop(context); },
        ),
        const SizedBox(height: 16),
        if (_browserError != null) ...[
          Text(_browserError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
          const SizedBox(height: 16),
        ],
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 8),
        const Text('Waiting for authentication...', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }

  // ── Method E: WebView auto-fill ──

  // Step 3E-1: Credentials form (email/password/phone)
  Widget _buildWebViewCredentials(ScrollController sc) => ListView(
    controller: sc,
    padding: const EdgeInsets.all(24),
    children: [
      Row(children: [
        IconButton(icon: const Icon(Icons.arrow_back_ios_new), padding: EdgeInsets.zero,
            onPressed: () => setState(() => _step = _AddStep.selectMethod)),
        const SizedBox(width: 8),
        const Text('Enter Credentials', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 8),
      const Text('Your credentials are used only to auto-fill the Google login page. They are never sent to the relay.',
          style: TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 20),
      TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder(), prefixIcon: Icon(Icons.email))),
      const SizedBox(height: 12),
      TextField(controller: _passwordCtrl, obscureText: true,
          decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))),
      const SizedBox(height: 12),
      TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (for 2FA, optional)', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone))),
      const SizedBox(height: 20),
      if (_webviewError != null) ...[
        Text(_webviewError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        const SizedBox(height: 12),
      ],
      ElevatedButton.icon(
        icon: _webviewBusy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.login),
        label: const Text('Continue'),
        onPressed: _webviewBusy || _emailCtrl.text.isEmpty ? null : _startWebViewAuth,
      ),
    ],
  );

  Future<void> _startWebViewAuth() async {
    setState(() { _webviewBusy = true; _webviewError = null; });
    try {
      final callback = 'com.dudenest.app://oauth/callback'; // native: custom scheme intercepted by webview
      final urlData = await widget.relay.getAuthUrl(_selectedProvider, callback);
      final authUrl = urlData['url'] as String;
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageFinished: (url) => _webviewAutoFill(url),
          onNavigationRequest: (req) {
            if (req.url.startsWith('com.dudenest.app://oauth/callback')) {
              _handleWebViewCallback(req.url);
              return NavigationDecision.prevent; // relay handles token exchange
            }
            return NavigationDecision.navigate;
          },
        ))
        ..loadRequest(Uri.parse(authUrl));
      setState(() { _webviewCtrl = ctrl; _step = _AddStep.webviewFlow; _webviewBusy = false; });
    } catch (e) {
      setState(() { _webviewError = e.toString(); _webviewBusy = false; });
    }
  }

  // Auto-fill credentials via JS injection when Google pages load
  void _webviewAutoFill(String url) async {
    final ctrl = _webviewCtrl;
    if (ctrl == null) return;
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final phone = _phoneCtrl.text.trim();
    await Future.delayed(const Duration(milliseconds: 600)); // wait for page render
    if (url.contains('accounts.google.com') && url.contains('identifier')) {
      // Email step
      await ctrl.runJavaScript(
        "var e=document.querySelector('input[type=email]'); if(e){e.value='\${email.replaceAll("'", "\\'")}';e.dispatchEvent(new Event('input',{bubbles:true}));}");
      await Future.delayed(const Duration(milliseconds: 400));
      await ctrl.runJavaScript(
        "var b=document.querySelector('#identifierNext button,button[jsname=LgbsSe]'); if(b)b.click();");
    } else if (url.contains('accounts.google.com') && url.contains('challenge/pwd')) {
      // Password step
      await ctrl.runJavaScript(
        "var p=document.querySelector('input[type=password]'); if(p){p.value='\${password.replaceAll("'", "\\'")}';p.dispatchEvent(new Event('input',{bubbles:true}));}");
      await Future.delayed(const Duration(milliseconds: 400));
      await ctrl.runJavaScript(
        "var b=document.querySelector('#passwordNext button,button[jsname=LgbsSe]'); if(b)b.click();");
    } else if (url.contains('accounts.google.com') && (url.contains('challenge') || url.contains('totp') || url.contains('phone'))) {
      // 2FA step — phone number if available
      if (phone.isNotEmpty) {
        await ctrl.runJavaScript(
          "var p=document.querySelector('input[type=tel],input[name=phoneNumber]'); if(p){p.value='\${phone.replaceAll("'", "\\'")}';p.dispatchEvent(new Event('input',{bubbles:true}));}");
        await Future.delayed(const Duration(milliseconds: 400));
        await ctrl.runJavaScript("var b=document.querySelector('button[jsname=LgbsSe],#idvPreregisteredPhoneNext button'); if(b)b.click();");
      }
    }
  }

  Future<void> _handleWebViewCallback(String callbackUrl) async {
    final code = Uri.parse(callbackUrl).queryParameters['code'] ?? '';
    if (code.isEmpty) { setState(() { _webviewError = 'No code in callback'; _step = _AddStep.webviewCredentials; }); return; }
    setState(() { _webviewBusy = true; });
    try {
      final data = await widget.relay.exchangeOAuthCode(_selectedProvider, code, 'com.dudenest.app://oauth/callback');
      final email = data['email'] as String? ?? 'unknown';
      setState(() { _oauthEmail = email; _step = _AddStep.done; _webviewBusy = false; });
    } catch (e) {
      setState(() { _webviewError = e.toString(); _step = _AddStep.webviewCredentials; _webviewBusy = false; });
    }
  }

  // Step 3E-2: WebView shown to user (handles 2FA prompts, consent screen)
  Widget _buildWebViewFlow() => Column(children: [
    AppBar(
      leading: IconButton(icon: const Icon(Icons.close),
          onPressed: () => setState(() { _webviewCtrl = null; _step = _AddStep.webviewCredentials; })),
      title: const Text('Sign in to Google'),
      actions: [if (_webviewBusy) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))],
    ),
    if (_webviewCtrl != null) Expanded(child: WebViewWidget(controller: _webviewCtrl!))
    else const Expanded(child: Center(child: CircularProgressIndicator())),
  ]);

  // Step 4: Done
  Widget _buildDone() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        const Text('Account Connected!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_oauthEmail != null)
          Text(_oauthEmail!, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        const Text('The account has been added to your relay storage.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    ),
  );
}

// ─── Storage summary card ─────────────────────────────────────────────────────

class _StorageSummaryCard extends StatelessWidget {
  final List<Map<String, dynamic>> providers;
  const _StorageSummaryCard({required this.providers});
  @override
  Widget build(BuildContext context) {
    final used = providers.fold<double>(0, (s, p) => s + ((p['quota_used_gb'] as num?)?.toDouble() ?? 0));
    final total = providers.fold<double>(0, (s, p) => s + ((p['quota_total_gb'] as num?)?.toDouble() ?? 0));
    final frac = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final n = providers.length;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.cloud_done, size: 20),
            const SizedBox(width: 8),
            Text('$n account${n == 1 ? "" : "s"} connected',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${used.toStringAsFixed(2)} GB used', style: const TextStyle(fontSize: 13)),
            Text('${total.toStringAsFixed(1)} GB total', style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: frac, minHeight: 6, borderRadius: BorderRadius.circular(3)),
        ]),
      ),
    );
  }
}

// ─── Helper widget ────────────────────────────────────────────────────────────

class _ProviderTile extends StatelessWidget {
  final String? initial;
  final IconData? icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool enabled;
  const _ProviderTile({this.initial, this.icon, required this.color, required this.title, required this.subtitle, this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    final leading = Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: initial != null
          ? Text(initial!, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color))
          : Icon(icon, color: color),
    );
    return ListTile(
      leading: leading,
      title: Text(title, style: TextStyle(color: enabled ? null : Colors.grey)),
      subtitle: Text(subtitle, style: TextStyle(color: enabled ? Colors.grey : Colors.grey.shade400)),
      trailing: enabled ? const Icon(Icons.chevron_right) : null,
      enabled: enabled,
      onTap: onTap,
    );
  }
}

// ─── Phase α/β UI widgets ────────────────────────────────────────────────────

// _AccountListTile renders one cloud account with Phase α/β metadata: priority badge
// (showing ID + position), role badge (PrimaryWrite/ReplicaWrite/ColdArchive/etc),
// quota progress bar (with soft/hard cap thresholds), file count, plus a popup menu for
// admin actions (refresh quota, edit, drain).
// Degrades gracefully when admin==null (legacy relay without /admin/accounts).
class _AccountListTile extends StatelessWidget {
  final Map<String, dynamic> provider;        // legacy /providers entry (has file_count, available, quota_used_gb)
  final Map<String, dynamic>? admin;          // /admin/accounts entry (priority, role, pinned) — nullable
  final Map<String, dynamic>? scan;           // s320 Phase 1: scan engine snapshot (state, last_finished_at, files_discovered)
  final RelayClient relay;
  final VoidCallback onChanged;               // reload trigger after edit/drain
  final VoidCallback onReconnect;             // re-auth flow when provider unavailable
  final int? dragIndex;                       // legacy s320 (kept for back-compat) — no longer used
  final bool showHamburger;                   // s329 #3: true → paint pure-Container drag-cue at row start

  const _AccountListTile({
    super.key,
    required this.provider, required this.admin, required this.relay,
    required this.onChanged, required this.onReconnect,
    this.scan, this.dragIndex, this.showHamburger = false,
  });

  @override
  Widget build(BuildContext context) {
    final available = provider['available'] == true;
    final email = provider['email'] ?? provider['id'] ?? 'Unknown';
    final type = (provider['type'] ?? 'gdrive') as String;
    final fileCount = (provider['file_count'] as num?)?.toInt() ?? 0;
    final usedGB = (provider['quota_used_gb'] as num?)?.toDouble() ?? 0.0;
    final totalGB = (provider['quota_total_gb'] as num?)?.toDouble() ?? 0.0;
    // Prefer fresher admin quota if present (background poll updates it every 30 min).
    final usedB = (admin?['quota_used_bytes'] as num?)?.toDouble();
    final totalB = (admin?['quota_total_bytes'] as num?)?.toDouble();
    final useFreshQuota = usedB != null && totalB != null && totalB > 0;
    final pct = useFreshQuota
      ? (usedB / totalB)
      : (totalGB > 0 ? usedGB / totalGB : 0.0);
    final usedDisplay = useFreshQuota ? (usedB / 1e9).toStringAsFixed(2) : usedGB.toStringAsFixed(1);
    final totalDisplay = useFreshQuota ? (totalB / 1e9).toStringAsFixed(2) : totalGB.toStringAsFixed(1);

    final role = (admin?['role'] ?? 'unknown') as String;
    final priority = admin?['priority'] as int?;
    final id = admin?['id'] as int?;
    final pinned = admin?['pinned'] == true;
    final softCap = ((admin?['soft_cap_pct'] as int?) ?? 90) / 100.0;
    final hardCap = ((admin?['hard_cap_pct'] as int?) ?? 98) / 100.0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header row: drag-cue (when reorderable) + icon + id badge + email + connection state + popup menu
          Row(children: [
            if (showHamburger) const Padding(
              padding: EdgeInsets.only(right: 8),
              child: _DragHandleHamburger(), // s329 #3: pure-paint cue; the tile itself is wrapped in ReorderableDragStartListener upstream
            ),
            _providerIcon(type, available),
            const SizedBox(width: 8),
            if (id != null) _IDBadge(id: id, pinned: pinned),
            if (id != null) const SizedBox(width: 6),
            Expanded(child: Text(email,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            )),
            Tooltip(
              message: available ? 'Connected' : 'Token expired — tap menu → Reconnect',
              child: available
                ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                : const Icon(Icons.error, color: Colors.red, size: 18),
            ),
            if (admin != null) PopupMenuButton<String>(
              tooltip: 'Account actions',
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) => _handleAction(context, v),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh',   child: ListTile(leading: Icon(Icons.refresh), title: Text('Refresh quota'))),
                PopupMenuItem(value: 'scan',      child: ListTile(leading: Icon(Icons.cloud_sync), title: Text('Scan cloud now'))), // s320 Phase 1
                PopupMenuItem(value: 'bootstrap', child: ListTile(leading: Icon(Icons.travel_explore), title: Text('Index ALL Drive files'))), // s321 Drive-wide bootstrap
                PopupMenuItem(value: 'edit',      child: ListTile(leading: Icon(Icons.edit), title: Text('Edit'))),
                PopupMenuDivider(),
                PopupMenuItem(value: 'drain',     child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Remove (drain)', style: TextStyle(color: Colors.red)))),
              ],
            ),
          ]),
          const SizedBox(height: 8),
          // Role + priority badges (only when admin endpoint is reachable)
          if (admin != null) Row(children: [
            _RoleBadge(role: role),
            const SizedBox(width: 8),
            if (priority != null) Chip(
              label: Text('Priority $priority', style: const TextStyle(fontSize: 11)),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            const Spacer(),
            if (!available) const Text('reconnect needed', style: TextStyle(color: Colors.red, fontSize: 11)),
          ]),
          if (admin != null) const SizedBox(height: 8),
          // Drain progress (only when role=drain — Phase γ continue)
          if (admin != null && role == 'drain' && id != null) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DrainProgressIndicator(relay: relay, accountID: id),
          ),
          // Quota progress bar with soft/hard cap markers
          if (totalDisplay != '0.0') _QuotaBar(percent: pct.clamp(0.0, 1.0), softCap: softCap, hardCap: hardCap),
          const SizedBox(height: 4),
          // Quota details + file count
          Text(
            '$usedDisplay / $totalDisplay GB · ${(pct * 100).toStringAsFixed(1)}% used · $fileCount files',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
          // s320 Phase 1: cloud-side scan engine status (last scan, indexed count, current state)
          if (scan != null) _ScanStatusLine(scan: scan!),
          if (!available) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reconnect'),
              onPressed: onReconnect,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _providerIcon(String type, bool available) {
    final color = available ? Colors.green : Colors.grey;
    return switch (type) {
      'gdrive'   => Icon(Icons.drive_folder_upload, color: color),
      'mega'     => Icon(Icons.storage, color: color),
      'onedrive' => Icon(Icons.cloud, color: color),
      _          => Icon(Icons.cloud, color: color),
    };
  }

  Future<void> _handleAction(BuildContext context, String action) async {
    final id = admin?['id'] as int?;
    if (id == null) return;
    switch (action) {
      case 'refresh':
        try {
          await relay.refreshAdminQuota(id);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quota refreshed')));
          onChanged();
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Refresh failed: $e')));
        }
        break;
      case 'scan': // s320 Phase 1: manual cloud-side scan trigger (discovers files added directly to cloud)
        final providerID = '${provider['type'] ?? 'gdrive'}:${provider['email'] ?? provider['id']}';
        try {
          final st = await relay.startScan(providerID);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scan started — ${st['state'] ?? 'running'}. Files will appear in /Files as discovered.'),
              duration: const Duration(seconds: 4)));
          // Reload after a beat so the new files_discovered counter starts showing up
          await Future.delayed(const Duration(seconds: 2));
          onChanged();
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Scan failed: $e'), backgroundColor: Colors.red));
        }
        break;
      case 'bootstrap': // s321: Drive-wide retro-index (catches files outside dudenest folder uploaded before)
        final providerID = '${provider['type'] ?? 'gdrive'}:${provider['email'] ?? provider['id']}';
        final alreadyDone = scan?['whole_drive_bootstrapped'] == true;
        final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
          title: Text(alreadyDone ? 'Re-index ALL Drive files?' : 'Index ALL Drive files?'),
          content: Text(alreadyDone
            ? 'Drive-wide bootstrap was already run for this account (${scan?['whole_drive_bootstrap_indexed'] ?? 0} files indexed). Re-run to catch any new files that may have been added outside Phase 2 polling window.\n\nIdempotent — already-indexed files are skipped (dedup by Drive file ID).'
            : 'One-shot scan of EVERY file in this Drive account (not just the dudenest folder). Catches files you uploaded directly to Drive before connecting dudenest.\n\nMay take 1-10 min for large accounts. Idempotent.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(alreadyDone ? 'Re-index' : 'Index now')),
          ],
        ));
        if (confirmed != true) return;
        try {
          await relay.bootstrapWholeDrive(providerID, reset: alreadyDone);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Drive-wide bootstrap started — runs in background, progress in scan status'),
              duration: Duration(seconds: 4)));
          await Future.delayed(const Duration(seconds: 3));
          onChanged();
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bootstrap failed: $e'), backgroundColor: Colors.red));
        }
        break;
      case 'edit':
        final changed = await showDialog<bool>(
          context: context,
          builder: (_) => _EditAccountDialog(relay: relay, admin: admin!),
        );
        if (changed == true) onChanged();
        break;
      case 'drain':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove cloud account?'),
            content: Text(
              'This will start a background migration of all files currently stored on this account '
              'to your other active accounts. The original files will be deleted from this cloud only '
              'after they have been successfully copied elsewhere. The account record stays in audit log '
              'with status=Removed.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton.tonal(
                style: FilledButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        try {
          await relay.drainAdminAccount(id);
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drain started — migration runs in background')));
          onChanged();
        } catch (e) {
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Drain failed: $e')));
        }
        break;
    }
  }
}

// _IDBadge displays the stable account ID (e.g. "ID003") with a pin icon when Pinned=true.
// IDs are NEVER reused after removal — useful in audit logs + support conversations.
class _IDBadge extends StatelessWidget {
  final int id;
  final bool pinned;
  const _IDBadge({required this.id, required this.pinned});
  @override
  Widget build(BuildContext context) {
    final padded = id < 1000 ? id.toString().padLeft(3, '0') : id.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade100,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('ID$padded', style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
        if (pinned) const Padding(padding: EdgeInsets.only(left: 3), child: Icon(Icons.push_pin, size: 11)),
      ]),
    );
  }
}

// _RoleBadge color-codes the account's current selection role. Driven by the Phase α/β
// state machine in account.Manager — PrimaryWrite/ReplicaWrite are auto-managed by
// ReconcileRoles based on quota; ColdArchive/ReadOnly/Drain are user/policy-driven.
class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (role) {
      'primary_write' => ('Primary', Colors.green),
      'replica_write' => ('Replica', Colors.blue),
      'read_only'     => ('Read only', Colors.grey),
      'cold_archive'  => ('Cold archive', Colors.purple),
      'drain'         => ('Draining', Colors.orange),
      'quarantine'    => ('Quarantine', Colors.red),
      _               => (role, Colors.blueGrey),
    };
    return Chip(
      label: Text(label, style: TextStyle(fontSize: 11, color: color.shade900)),
      backgroundColor: color.shade50,
      side: BorderSide(color: color.shade200),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
}

// _QuotaBar — linear progress with two vertical lines at SoftCap (yellow) + HardCap (red).
// Visually communicates "you can write up to softCap before auto-demote kicks in, and never above hardCap".
class _QuotaBar extends StatelessWidget {
  final double percent;   // 0..1 used fraction
  final double softCap;   // 0..1 soft cap fraction (e.g. 0.90)
  final double hardCap;   // 0..1 hard cap fraction (e.g. 0.98)
  const _QuotaBar({required this.percent, required this.softCap, required this.hardCap});

  @override
  Widget build(BuildContext context) {
    final color = percent >= hardCap
      ? Colors.red
      : (percent >= softCap ? Colors.orange : Colors.green);
    return SizedBox(
      height: 8,
      child: LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth;
        return Stack(children: [
          Container(decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(4))),
          FractionallySizedBox(
            widthFactor: percent,
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
          ),
          Positioned(left: w * softCap - 0.5, top: 0, bottom: 0, child: Container(width: 1, color: Colors.amber.shade800)),
          Positioned(left: w * hardCap - 0.5, top: 0, bottom: 0, child: Container(width: 1, color: Colors.red.shade800)),
        ]);
      }),
    );
  }
}

// _PolicyCard shows the global Account Policy summary (replication factor, diversity, caps)
// + a button to edit. For Phase γ continue (this iteration) we surface read-only; the editor
// dialog ships as `_EditPolicyDialog` immediately below — already implemented + wired.
class _PolicyCard extends StatelessWidget {
  final Map<String, dynamic> policy;
  final RelayClient relay;
  final VoidCallback onChanged;
  const _PolicyCard({required this.policy, required this.relay, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final rf = policy['replication_factor'] ?? '?';
    final divProv = policy['diversity_required'] == true;
    final softCap = policy['soft_cap_default_pct'] ?? '?';
    final hardCap = policy['hard_cap_default_pct'] ?? '?';
    final ageRot = policy['age_based_rotation'] == true;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      color: Colors.indigo.shade50,
      child: ListTile(
        leading: const Icon(Icons.policy, color: Colors.indigo),
        title: const Text('Global Policy', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          'Replication factor: $rf · Diversity: ${divProv ? "ON" : "off"} · '
          'Caps: $softCap% / $hardCap% · Age rotation: ${ageRot ? "ON" : "off"}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          // s319 #9: bulk refresh — triggers all accounts' Drive about.get concurrently;
          // _load() refresh ~5-10s later picks up new quota values.
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh quota for all accounts',
            onPressed: () async {
              try {
                final resp = await relay.refreshAllAdminQuota();
                final n = resp['accounts_queued'] ?? '?';
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Refreshing $n accounts…'), duration: const Duration(seconds: 2)),
                );
                await Future<void>.delayed(const Duration(seconds: 6));
                onChanged();
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Refresh failed: $e'), backgroundColor: Colors.red),
                );
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            tooltip: 'Edit global policy',
            onPressed: () async {
              final changed = await showDialog<bool>(
                context: context,
                builder: (_) => _EditPolicyDialog(relay: relay, current: policy),
              );
              if (changed == true) onChanged();
            },
          ),
        ]),
      ),
    );
  }
}

// _EditAccountDialog — interactive PATCH for /admin/accounts/{id}. Lets the user change
// role + priority + pinned + soft/hard cap overrides. Submits only fields the user actually
// touched (partial overlay matches the backend PATCH semantics).
class _EditAccountDialog extends StatefulWidget {
  final RelayClient relay;
  final Map<String, dynamic> admin;
  const _EditAccountDialog({required this.relay, required this.admin});
  @override
  State<_EditAccountDialog> createState() => _EditAccountDialogState();
}

class _EditAccountDialogState extends State<_EditAccountDialog> {
  late String _role;
  late int _priority;
  late bool _pinned;
  String? _softCapText;
  String? _hardCapText;
  // s319 #7: forward-compat fields (F3 deep archive + F4 multi-region + content-type routing)
  String? _regionText;
  int? _compressionLevel;
  Set<String> _acceptsContentTypes = {}; // empty = inherit policy default (accept all)
  bool _saving = false;

  static const _contentTypeOptions = ['photos', 'files']; // matches types.PhotosFolder / types.FilesFolder

  @override
  void initState() {
    super.initState();
    _role = widget.admin['role'] as String? ?? 'replica_write';
    _priority = widget.admin['priority'] as int? ?? 0;
    _pinned = widget.admin['pinned'] == true;
    _softCapText = widget.admin['soft_cap_pct']?.toString();
    _hardCapText = widget.admin['hard_cap_pct']?.toString();
    _regionText = widget.admin['region'] as String?;
    _compressionLevel = widget.admin['compression_level'] as int?;
    final accepted = widget.admin['accepts_content_types'] as List<dynamic>?;
    if (accepted != null) _acceptsContentTypes = accepted.map((e) => e.toString()).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.admin['id'] as int;
    final email = widget.admin['email'] as String? ?? 'unknown';
    return AlertDialog(
      title: Text('Edit ID${id.toString().padLeft(3, '0')} — $email'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String>(
            value: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'primary_write', child: Text('Primary write')),
              DropdownMenuItem(value: 'replica_write', child: Text('Replica write')),
              DropdownMenuItem(value: 'read_only',     child: Text('Read only')),
              DropdownMenuItem(value: 'cold_archive',  child: Text('Cold archive')),
            ],
            onChanged: (v) => setState(() => _role = v!),
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: _priority.toString(),
            decoration: const InputDecoration(labelText: 'Priority (lower = higher importance)'),
            keyboardType: TextInputType.number,
            onChanged: (v) { final n = int.tryParse(v); if (n != null) setState(() => _priority = n); },
          ),
          SwitchListTile(
            title: const Text('Pinned (immune to auto-demote/promote)'),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
            contentPadding: EdgeInsets.zero,
          ),
          TextFormField(
            initialValue: _softCapText,
            decoration: const InputDecoration(labelText: 'Soft cap % override (blank = inherit)'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _softCapText = v,
          ),
          TextFormField(
            initialValue: _hardCapText,
            decoration: const InputDecoration(labelText: 'Hard cap % override (blank = inherit)'),
            keyboardType: TextInputType.number,
            onChanged: (v) => _hardCapText = v,
          ),
          const Divider(height: 24),
          const Text('Advanced (forward-compat)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          // F4 multi-region diversity hint (used by SelectReplicas when DiversityRegionRequired=true)
          TextFormField(
            initialValue: _regionText,
            decoration: const InputDecoration(labelText: 'Region (e.g. eu-west, us-east) — F4'),
            onChanged: (v) => _regionText = v.isEmpty ? null : v,
          ),
          // F3 deep archive — zstd compression level on Role=ColdArchive uploads
          DropdownButtonFormField<int?>(
            value: _compressionLevel,
            decoration: const InputDecoration(labelText: 'Compression level (0=off, 1-22=zstd) — F3'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Inherit policy')),
              for (final lvl in [0, 1, 3, 6, 9, 12, 15, 19, 22])
                DropdownMenuItem(value: lvl, child: Text(lvl == 0 ? '0 (no compression)' : 'Level $lvl')),
            ],
            onChanged: (v) => setState(() => _compressionLevel = v),
          ),
          const SizedBox(height: 8),
          // Content-type routing (already supported by SelectReplicas; previously only PATCH-able via raw API)
          Text('Accepts content types', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Text('Empty = inherit policy (accept all)', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, children: [
            for (final type in _contentTypeOptions)
              FilterChip(
                label: Text(type),
                selected: _acceptsContentTypes.contains(type),
                onSelected: (sel) => setState(() {
                  if (sel) { _acceptsContentTypes.add(type); } else { _acceptsContentTypes.remove(type); }
                }),
              ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final patch = <String, dynamic>{
      'role': _role,
      'priority': _priority,
      'pinned': _pinned,
    };
    final sc = int.tryParse(_softCapText ?? '');
    final hc = int.tryParse(_hardCapText ?? '');
    if (sc != null) patch['soft_cap_pct'] = sc;
    if (hc != null) patch['hard_cap_pct'] = hc;
    // s319 #7 forward-compat — backend already accepts these via handlePatch in admin_accounts.go
    if (_regionText != null && _regionText!.isNotEmpty) patch['region'] = _regionText;
    if (_compressionLevel != null) patch['compression_level'] = _compressionLevel;
    if (_acceptsContentTypes.isNotEmpty) patch['accepts_content_types'] = _acceptsContentTypes.toList();
    try {
      await widget.relay.patchAdminAccount(widget.admin['id'] as int, patch);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }
}

// _EditPolicyDialog — overlay PATCH for /admin/policy. Lets the user change replication
// factor, diversity, default soft/hard caps. Other fields kept at server-side defaults.
class _EditPolicyDialog extends StatefulWidget {
  final RelayClient relay;
  final Map<String, dynamic> current;
  const _EditPolicyDialog({required this.relay, required this.current});
  @override
  State<_EditPolicyDialog> createState() => _EditPolicyDialogState();
}

class _EditPolicyDialogState extends State<_EditPolicyDialog> {
  late int _rf;
  late bool _diversity;
  late bool _ageRot;
  late String _softCap;
  late String _hardCap;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rf = widget.current['replication_factor'] as int? ?? 2;
    _diversity = widget.current['diversity_required'] == true;
    _ageRot = widget.current['age_based_rotation'] == true;
    _softCap = (widget.current['soft_cap_default_pct'] ?? 90).toString();
    _hardCap = (widget.current['hard_cap_default_pct'] ?? 98).toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit global account policy'),
      content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('Replication factor')),
          IconButton(icon: const Icon(Icons.remove), onPressed: () => setState(() { if (_rf > 1) _rf--; })),
          Text('$_rf', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => _rf++)),
        ]),
        SwitchListTile(
          title: const Text('Diversity required (replicas on different provider types)'),
          value: _diversity, onChanged: (v) => setState(() => _diversity = v), contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: const Text('Age-based rotation (off by default)'),
          subtitle: const Text('Migrate old files to cold archive accounts'),
          value: _ageRot, onChanged: (v) => setState(() => _ageRot = v), contentPadding: EdgeInsets.zero,
        ),
        TextFormField(
          initialValue: _softCap,
          decoration: const InputDecoration(labelText: 'Default soft cap %'),
          keyboardType: TextInputType.number, onChanged: (v) => _softCap = v,
        ),
        TextFormField(
          initialValue: _hardCap,
          decoration: const InputDecoration(labelText: 'Default hard cap %'),
          keyboardType: TextInputType.number, onChanged: (v) => _hardCap = v,
        ),
      ])),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save')),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final patch = <String, dynamic>{
      'replication_factor': _rf,
      'diversity_required': _diversity,
      'age_based_rotation': _ageRot,
    };
    final sc = int.tryParse(_softCap); if (sc != null) patch['soft_cap_default_pct'] = sc;
    final hc = int.tryParse(_hardCap); if (hc != null) patch['hard_cap_default_pct'] = hc;
    try {
      await widget.relay.patchAdminPolicy(patch);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }
}

// _DrainProgressIndicator polls /admin/accounts/{id}/drain-progress every 5s while widget is mounted.
// Renders a LinearProgressIndicator + "replicas_migrated/replicas_to_migrate (%)" caption.
// Stops polling when in_progress=false (worker reports done) or widget disposed.
// Phase γ continue (s319).
class _DrainProgressIndicator extends StatefulWidget {
  final RelayClient relay;
  final int accountID;
  const _DrainProgressIndicator({required this.relay, required this.accountID});
  @override State<_DrainProgressIndicator> createState() => _DrainProgressIndicatorState();
}

class _DrainProgressIndicatorState extends State<_DrainProgressIndicator> {
  Map<String, dynamic>? _progress;
  String? _error;
  Timer? _poll;
  bool _inProgress = true; // assume in-progress until first response says otherwise

  @override
  void initState() { super.initState(); _fetch(); _poll = Timer.periodic(const Duration(seconds: 5), (_) => _fetch()); }
  @override
  void dispose() { _poll?.cancel(); super.dispose(); }

  Future<void> _fetch() async {
    try {
      final data = await widget.relay.getDrainProgress(widget.accountID);
      if (!mounted) return;
      setState(() {
        _progress = data;
        _error = null;
        _inProgress = data['in_progress'] == true;
        if (!_inProgress) { _poll?.cancel(); _poll = null; } // stop polling once worker reports done
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text('Drain status unavailable: $_error', style: const TextStyle(color: Colors.red, fontSize: 11));
    if (_progress == null) return const LinearProgressIndicator(); // indeterminate while first fetch in flight
    final snap = _progress!['snapshot'] as Map<String, dynamic>?;
    if (snap == null) {
      // Drain initiated but worker hasn't started first sweep yet (waiting for next interval, max 2 min).
      return Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text('Drain initiated — waiting for first sweep (≤2 min)', style: TextStyle(color: Colors.orange.shade700, fontSize: 11)),
      ]);
    }
    final migrated = (snap['replicas_migrated'] as num?)?.toInt() ?? 0;
    final total = (snap['replicas_to_migrate'] as num?)?.toInt() ?? 0;
    final failed = (snap['replicas_failed'] as num?)?.toInt() ?? 0;
    final lastErr = snap['last_err'] as String?;
    final percent = total > 0 ? migrated / total : 0.0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LinearProgressIndicator(value: total > 0 ? percent.clamp(0.0, 1.0) : null, color: Colors.orange),
      const SizedBox(height: 4),
      Text(
        total == 0
          ? 'Drain: 0 copies to migrate (account may have no files)'
          : 'Drain: $migrated / $total copies migrated (${(percent * 100).toStringAsFixed(0)}%)'
              + (failed > 0 ? ' · $failed failed' : ''),
        style: TextStyle(color: Colors.orange.shade800, fontSize: 11),
      ),
      if (lastErr != null && lastErr.isNotEmpty) Text('Last error: $lastErr', style: const TextStyle(color: Colors.red, fontSize: 10)),
    ]);
  }
}

// _ScanStatusLine renders compact P5c scan engine status inline in a tile:
// "Cloud scan: 23 files indexed · 12 min ago" or "Scanning… 47 discovered so far" depending on state.
// s320 Phase 1.
class _ScanStatusLine extends StatelessWidget {
  final Map<String, dynamic> scan;
  const _ScanStatusLine({required this.scan});
  @override
  Widget build(BuildContext context) {
    final state = (scan['state'] ?? 'idle') as String;
    final discovered = (scan['files_discovered'] as num?)?.toInt() ?? 0;
    final indexed = (scan['files_newly_indexed'] as num?)?.toInt() ?? 0;
    final errors = (scan['errors'] as num?)?.toInt() ?? 0;
    final lastErr = scan['last_error'] as String?;
    final lastFinished = scan['last_finished_at'] as String?;
    Color color = Colors.grey.shade600;
    IconData icon = Icons.cloud_done;
    String text;
    if (state == 'running') {
      color = Colors.blue.shade700; icon = Icons.cloud_sync;
      text = 'Scanning cloud… $discovered files discovered';
    } else if (state == 'error') {
      color = Colors.red; icon = Icons.cloud_off;
      text = 'Scan error${lastErr != null ? ": $lastErr" : ""} · tap menu → Scan cloud now';
    } else if (lastFinished != null && lastFinished.isNotEmpty && !lastFinished.startsWith('0001-')) {
      final ago = _formatAgo(DateTime.tryParse(lastFinished));
      final bootstrapped = scan['whole_drive_bootstrapped'] == true;
      final wholeIndexed = (scan['whole_drive_bootstrap_indexed'] as num?)?.toInt() ?? 0;
      text = 'Cloud scan: $discovered indexed${indexed > 0 ? " (+$indexed new)" : ""}'
        '${errors > 0 ? " · $errors errors" : ""} · last scan $ago'
        '${bootstrapped ? " · whole-Drive: $wholeIndexed files" : ""}';
    } else {
      icon = Icons.cloud_queue;
      text = 'Cloud not yet scanned — tap menu → Scan cloud now';
    }
    return Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 11), overflow: TextOverflow.ellipsis)),
    ]));
  }
  static String _formatAgo(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().toUtc().difference(t.toUtc());
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

// _DragHandleHamburger renders a three-bar drag affordance using only Container primitives
// (no Material Icons font dependency). Replaces Icons.drag_handle / Icons.drag_indicator which
// empirically rendered as wrong glyphs on production Flutter web canvaskit (codepoint shift in
// bundled MaterialIcons-Regular.otf — same family of bug as s319 Icons.tune → drawer-looking glyph).
// Cannot fail to paint — pure Container + color, no font lookup.
class _DragHandleHamburger extends StatelessWidget {
  const _DragHandleHamburger();
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22, height: 22,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(3, (_) => Container(
          width: 18, height: 2,
          margin: const EdgeInsets.symmetric(vertical: 1.5),
          decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(1)),
        )),
      ),
    );
  }
}
