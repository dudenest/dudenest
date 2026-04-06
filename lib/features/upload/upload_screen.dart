import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/network/relay_client.dart';

class UploadScreen extends StatefulWidget {
  final RelayClient relay;
  const UploadScreen({super.key, required this.relay});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _uploading = false;
  String? _result;
  String? _error;

  Future<void> _pickAndUpload() async {
    final res = await FilePicker.platform.pickFiles(withData: true);
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    if (file.bytes == null) return;
    setState(() { _uploading = true; _result = null; _error = null; });
    try {
      final fm = await widget.relay.uploadFile(file.name, file.bytes!);
      setState(() {
        _result = 'Uploaded!\nID: ${fm['file_id']}\nSize: ${fm['size']} bytes\nHash: ${(fm['hash'] as String?)?.substring(0, 16)}...';
        _uploading = false;
      });
    } catch (e) {
      setState(() { _error = e.toString(); _uploading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload File')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              onPressed: _uploading ? null : _pickAndUpload,
              icon: _uploading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload_file),
              label: Text(_uploading ? 'Uploading...' : 'Pick file and upload'),
            ),
            if (_result != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(8)),
                child: Text(_result!, style: const TextStyle(fontFamily: 'monospace')),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(8)),
                child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
