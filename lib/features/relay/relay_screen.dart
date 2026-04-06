import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/network/relay_client.dart';

// Files screen — list uploaded files, download, delete
class RelayScreen extends StatefulWidget {
  final RelayClient relay;
  const RelayScreen({super.key, required this.relay});
  @override
  State<RelayScreen> createState() => _RelayScreenState();
}

class _RelayScreenState extends State<RelayScreen> {
  List<Map<String, dynamic>> _files = [];
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
      final files = await widget.relay.listFiles();
      setState(() { _files = files; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _download(String fileId, String name) async {
    setState(() { _error = null; });
    try {
      final bytes = await widget.relay.downloadFile(fileId);
      // Save to temp file and show snackbar
      final tmpPath = '${Directory.systemTemp.path}/$name';
      await File(tmpPath).writeAsBytes(bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $tmpPath')));
    } catch (e) {
      setState(() { _error = e.toString(); });
    }
  }

  Future<void> _delete(String fileId) async {
    try {
      await widget.relay.deleteFile(fileId);
      _load();
    } catch (e) {
      setState(() { _error = e.toString(); });
    }
  }

  String _formatSize(dynamic bytes) {
    if (bytes == null) return '?';
    final n = bytes as num;
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Files'), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _files.isEmpty
                  ? const Center(child: Text('No files yet. Upload something first.'))
                  : ListView.builder(
                      itemCount: _files.length,
                      itemBuilder: (ctx, i) {
                        final f = _files[i];
                        final id = f['file_id'] as String? ?? '';
                        final name = f['name'] as String? ?? id;
                        return ListTile(
                          leading: const Icon(Icons.insert_drive_file),
                          title: Text(name),
                          subtitle: Text('${_formatSize(f['size'])} · ID: ${id.substring(0, 8)}...'),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(icon: const Icon(Icons.download), onPressed: () => _download(id, name)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _delete(id)),
                          ]),
                        );
                      },
                    ),
    );
  }
}
