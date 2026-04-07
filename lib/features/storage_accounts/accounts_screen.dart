import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../core/network/relay_client.dart';

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
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => _AddAccountSheet(relay: widget.relay),
          );
          _load(); // refresh after add
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
                          leading: Icon(Icons.cloud, color: available ? Colors.green : Colors.grey),
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

  Widget _emptyState(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
      const SizedBox(height: 16),
      const Text('No storage accounts', style: TextStyle(fontSize: 16)),
      const SizedBox(height: 8),
      const Text('Add a Google Drive account to start storing files.',
          textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      ElevatedButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Add Google Drive'),
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

// ─── Add Account Sheet — step-by-step OAuth via relay browser automation ─────
class _AddAccountSheet extends StatefulWidget {
  final RelayClient relay;
  const _AddAccountSheet({required this.relay});
  @override
  State<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends State<_AddAccountSheet> {
  _AddStep _step = _AddStep.selectProvider;
  String? _sessionId;
  Map<String, dynamic>? _currentStep; // relay step response
  bool _busy = false;
  String? _error;
  final _ctrl = TextEditingController();

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _startSession(String provider) async {
    setState(() { _busy = true; _error = null; });
    try {
      final step = await widget.relay.startAuthSession(provider);
      setState(() {
        _sessionId = step['session_id'] as String?;
        _currentStep = step;
        _step = _AddStep.authFlow;
        _busy = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _busy = false; });
    }
  }

  Future<void> _submitField() async {
    final sid = _sessionId;
    final stepData = _currentStep;
    if (sid == null || stepData == null) return;
    final fields = stepData['fields'] as List? ?? [];
    if (fields.isEmpty) return;
    final field = fields.first as Map<String, dynamic>;
    final selector = field['selector'] as String? ?? '';
    setState(() { _busy = true; _error = null; });
    try {
      final next = await widget.relay.authInput(sid, selector, _ctrl.text.trim());
      _ctrl.clear();
      if ((next['status'] as String?) == 'done') {
        setState(() { _step = _AddStep.done; _busy = false; });
      } else {
        setState(() { _currentStep = next; _busy = false; });
      }
    } catch (e) {
      setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9, minChildSize: 0.4, maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: switch (_step) {
          _AddStep.selectProvider => _buildProviderSelect(scrollCtrl),
          _AddStep.authFlow => _buildAuthFlow(scrollCtrl),
          _AddStep.done => _buildDone(),
        },
      ),
    );
  }

  Widget _buildProviderSelect(ScrollController scrollCtrl) => ListView(
    controller: scrollCtrl,
    padding: const EdgeInsets.all(24),
    children: [
      const Text('Add Storage Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Connect a cloud storage provider. Files will be encrypted and split across providers on your relay.',
          style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 24),
      if (_error != null) ...[
        Text(_error!, style: const TextStyle(color: Colors.red)),
        const SizedBox(height: 12),
      ],
      ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4285F4)))),
        title: const Text('Google Drive'),
        subtitle: const Text('15 GB free · OAuth via relay browser'),
        trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.chevron_right),
        onTap: _busy ? null : () => _startSession('gdrive'),
      ),
      const Divider(),
      ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.storage, color: Colors.grey)),
        title: const Text('OneDrive', style: TextStyle(color: Colors.grey)),
        subtitle: const Text('Coming soon'),
        enabled: false,
      ),
      ListTile(
        leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.storage, color: Colors.grey)),
        title: const Text('MEGA', style: TextStyle(color: Colors.grey)),
        subtitle: const Text('50 GB free · Coming soon'),
        enabled: false,
      ),
    ],
  );

  Widget _buildAuthFlow(ScrollController scrollCtrl) {
    final stepData = _currentStep ?? {};
    final status = stepData['status'] as String? ?? '';
    final fields = (stepData['fields'] as List? ?? []).cast<Map<String, dynamic>>();
    final screenshotB64 = stepData['screenshot_b64'] as String?;
    final field = fields.isNotEmpty ? fields.first : null;
    final fieldType = field?['type'] as String? ?? 'text';
    final fieldLabel = field?['label'] as String? ?? 'Enter value';
    final isInfo = fieldType == 'info';

    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(24),
      children: [
        Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new), padding: EdgeInsets.zero,
              onPressed: () { widget.relay.authClose(_sessionId ?? ''); Navigator.pop(context); }),
          const SizedBox(width: 8),
          const Text('Google Drive Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 16),
        // Screenshot from relay browser
        if (screenshotB64 != null && screenshotB64.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(base64Decode(screenshotB64), height: 240, fit: BoxFit.cover,
                gaplessPlayback: true),
          ),
          const SizedBox(height: 16),
        ],
        if (_error != null) ...[
          Text(_error!, style: const TextStyle(color: Colors.red)),
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
          ElevatedButton(onPressed: _busy ? null : _submitField, child: const Text('Continue')),
        ] else if (field != null) ...[
          Text(fieldLabel, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            obscureText: fieldType == 'password',
            keyboardType: fieldType == 'number' || fieldType == 'tel' ? TextInputType.phone : TextInputType.emailAddress,
            decoration: InputDecoration(hintText: fieldLabel, border: const OutlineInputBorder()),
            onSubmitted: (_) => _busy ? null : _submitField(),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _submitField,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Continue'),
          ),
        ],
        if (status.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Status: $status', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ],
    );
  }

  Widget _buildDone() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 64),
        const SizedBox(height: 16),
        const Text('Account Connected!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Google Drive has been added to your relay storage.', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ]),
    ),
  );
}

enum _AddStep { selectProvider, authFlow, done }
