import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/network/relay_client.dart';
import '../../core/oauth/oauth_service.dart';

class AccountsScreen extends StatefulWidget {
  final RelayClient relay;
  const AccountsScreen({super.key, required this.relay});
  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final providers = await widget.relay.getProviders();
      setState(() { _providers = providers; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Accounts'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _providers.isEmpty
                  ? _emptyState(context)
                  : ListView.builder(
                      itemCount: _providers.length,
                      itemBuilder: (ctx, i) {
                        final p = _providers[i];
                        final used = (p['quota_used_gb'] as num?)?.toStringAsFixed(1) ?? '?';
                        final total = (p['quota_total_gb'] as num?)?.toStringAsFixed(1) ?? '?';
                        final available = p['available'] == true;
                        return ListTile(
                          leading: _providerIcon(p['type'] as String? ?? 'gdrive', available),
                          title: Text(p['email'] ?? p['id'] ?? 'Unknown'),
                          subtitle: Text('${p['type'] ?? 'gdrive'} · $used GB / $total GB used'),
                          trailing: available
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : const Icon(Icons.error, color: Colors.red),
                        );
                      },
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

// ─── Add Account Sheet ────────────────────────────────────────────────────────

enum _AddStep { selectProvider, selectMethod, oauthFlow, browserFlow, webviewCredentials, webviewFlow, done }
enum _AuthMethod { flutterOAuth, browserAuth, webviewOAuth }

class _AddAccountSheet extends StatefulWidget {
  final RelayClient relay;
  const _AddAccountSheet({required this.relay});
  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  _AddStep _step = _AddStep.selectProvider;
  _AuthMethod _method = _AuthMethod.flutterOAuth;
  String _selectedProvider = 'gdrive';

  // OAuth (Method A) state
  bool _oauthBusy = false;
  String? _oauthEmail;
  String? _oauthError;

  // Browser Auth (Method B) state — chromedp
  String? _sessionId;
  Map<String, dynamic>? _currentStep;
  bool _browserBusy = false;
  String? _browserError;
  final _ctrl = TextEditingController();

  // WebView Auth (Method E) state — in-app WebView with auto-fill
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  WebViewController? _webviewCtrl;
  bool _webviewBusy = false;
  String? _webviewError;

  @override
  void dispose() { _ctrl.dispose(); _emailCtrl.dispose(); _passwordCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

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

  // ── Method B: Browser Auth (chromedp on relay) ──

  Future<void> _startBrowserSession() async {
    setState(() { _browserBusy = true; _browserError = null; });
    try {
      final step = await widget.relay.startAuthSession(_selectedProvider);
      setState(() {
        _sessionId = step['session_id'] as String?;
        _currentStep = step;
        _step = _AddStep.browserFlow;
        _browserBusy = false;
      });
    } catch (e) {
      setState(() { _browserError = e.toString(); _browserBusy = false; });
    }
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

  // Step 3B: Browser Auth (chromedp) — screenshot + field fill
  Widget _buildBrowserFlow(ScrollController sc) {
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
        "var e=document.querySelector('input[type=email]'); if(e){e.value='${email.replaceAll("'", "\\'")}';e.dispatchEvent(new Event('input',{bubbles:true}));}");
      await Future.delayed(const Duration(milliseconds: 400));
      await ctrl.runJavaScript(
        "var b=document.querySelector('#identifierNext button,button[jsname=LgbsSe]'); if(b)b.click();");
    } else if (url.contains('accounts.google.com') && url.contains('challenge/pwd')) {
      // Password step
      await ctrl.runJavaScript(
        "var p=document.querySelector('input[type=password]'); if(p){p.value='${password.replaceAll("'", "\\'")}';p.dispatchEvent(new Event('input',{bubbles:true}));}");
      await Future.delayed(const Duration(milliseconds: 400));
      await ctrl.runJavaScript(
        "var b=document.querySelector('#passwordNext button,button[jsname=LgbsSe]'); if(b)b.click();");
    } else if (url.contains('accounts.google.com') && (url.contains('challenge') || url.contains('totp') || url.contains('phone'))) {
      // 2FA step — phone number if available
      if (phone.isNotEmpty) {
        await ctrl.runJavaScript(
          "var p=document.querySelector('input[type=tel],input[name=phoneNumber]'); if(p){p.value='${phone.replaceAll("'", "\\'")}';p.dispatchEvent(new Event('input',{bubbles:true}));}");
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
