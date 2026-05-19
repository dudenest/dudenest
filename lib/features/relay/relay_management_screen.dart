// relay_management_screen.dart — shows user's registered relays and backup status.
// Calls api.dudenest.com/api/v1/relays (backend proxies to dudenest-backup /user/relays).
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/auth/auth_service.dart';

const _apiBase = 'https://api.dudenest.com';

class RelayManagementScreen extends StatefulWidget {
  const RelayManagementScreen({super.key});
  @override
  State<RelayManagementScreen> createState() => _RelayManagementScreenState();
}

class _RelayManagementScreenState extends State<RelayManagementScreen> {
  List<Map<String, dynamic>> _relays = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final token = AuthService().token;
      final resp = await http.get(
        Uri.parse('$_apiBase/api/v1/relays'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      setState(() { _relays = List<Map<String, dynamic>>.from(data['relays'] ?? []); _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _showBackup(String relayID) async {
    showDialog(context: context, builder: (_) => const AlertDialog(
      title: Text('Loading...'),
      content: Center(child: CircularProgressIndicator()),
    ));
    try {
      final token = AuthService().token;
      final resp = await http.get(
        Uri.parse('$_apiBase/api/v1/relays/$relayID/backup'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      Navigator.pop(context); // close loading dialog
      if (resp.statusCode == 404) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No backup found for this relay')));
        return;
      }
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      showDialog(context: context, builder: (ctx) => AlertDialog(
        title: Text('Backup: ${relayID.substring(0, 8)}...'),
        content: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          _infoRow('Version', '${data['backup_version'] ?? '-'}'),
          _infoRow('Saved at', '${data['created_at'] ?? '-'}'),
          _infoRow('Providers', (data['provider_ids'] as List?)?.join(', ') ?? '-'),
          const SizedBox(height: 8),
          const Text('File maps (maps_json):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
            child: SingleChildScrollView(child: Text(
              const JsonEncoder.withIndent('  ').convert(jsonDecode(data['maps_json'] ?? '[]')),
              style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
            )),
          ),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ));
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 80, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontFamily: 'monospace'))),
    ]),
  );

  String _fmt(String? iso) {
    if (iso == null) return 'never';
    try { return iso.replaceFirst('T', ' ').substring(0, 16); } catch (_) { return iso; }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Relays'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _load, child: const Text('Retry')),
                ]))
              : _relays.isEmpty
                  ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.router, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No relays registered yet.', style: TextStyle(color: Colors.grey)),
                      SizedBox(height: 8),
                      Text('Install and start a relay to see it here.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ]))
                  : ListView.separated(
                      itemCount: _relays.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final r = _relays[i];
                        final id = r['relay_id'] as String? ?? '';
                        final lastBackup = _fmt(r['last_backup_at'] as String?);
                        final lastSeen = _fmt(r['last_seen_at'] as String?);
                        final version = r['relay_version'] as String? ?? '?';
                        final hasBackup = r['last_backup_at'] != null;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: hasBackup ? Colors.green.withOpacity(0.15) : Colors.orange.withOpacity(0.15),
                            child: Icon(Icons.router, color: hasBackup ? Colors.green : Colors.orange),
                          ),
                          title: Text('relay ${id.length >= 8 ? id.substring(0, 8) : id}...',
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'v$version · backup: $lastBackup · seen: $lastSeen',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: hasBackup
                              ? IconButton(
                                  icon: const Icon(Icons.cloud_download),
                                  tooltip: 'View backup',
                                  onPressed: () => _showBackup(id),
                                )
                              : const Tooltip(message: 'No backup yet', child: Icon(Icons.cloud_off, color: Colors.grey)),
                        );
                      },
                    ),
    );
  }
}
