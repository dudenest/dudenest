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
  void initState() {
    super.initState();
    _load();
  }

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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _providers.isEmpty
                  ? const Center(child: Text('No accounts. Add a Google Drive account on the relay.'))
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
                          subtitle: Text('${p['type'] ?? ''} · $used GB / $total GB used'),
                          trailing: available
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : const Icon(Icons.error, color: Colors.red),
                        );
                      },
                    ),
    );
  }
}
