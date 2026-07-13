import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/network/relay_client.dart';
import '../../main.dart';

typedef UploadFilePicker = Future<FilePickerResult?> Function();

class _UploadJob {
  final String name;
  final int size;
  final Uint8List bytes;
  final double estimatedSecs; // ~300 KB/s GDrive estimate
  double progress = 0.0; // 0.0..1.0
  bool done = false;
  String? error;
  _UploadJob(this.name, this.size, this.bytes)
      : estimatedSecs = (size / (300 * 1024)).clamp(1.5, 120.0);
}

class UploadScreen extends StatefulWidget {
  final RelayClient? relay;
  final int autoPickNonce;
  final UploadFilePicker? picker;
  const UploadScreen(
      {super.key, required this.relay, this.autoPickNonce = 0, this.picker});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final List<_UploadJob> _jobs = [];
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (widget.autoPickNonce > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_pick());
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant UploadScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.autoPickNonce != oldWidget.autoPickNonce) {
      unawaited(_pick());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        _ticker?.cancel();
        return;
      }
      bool anyActive = false;
      setState(() {
        for (final j in _jobs) {
          if (j.done || j.error != null) continue;
          anyActive = true;
          j.progress = (j.progress + 0.9 / j.estimatedSecs * 0.1)
              .clamp(0.0, 0.9); // advance per 100ms
        }
      });
      if (!anyActive) _ticker?.cancel();
    });
  }

  Future<void> _uploadJob(_UploadJob job) async {
    try {
      final relay = widget.relay;
      if (relay == null) {
        throw 'Relay is required before uploading. Install or assign a relay in Settings.';
      }
      final strategy = DudenestApp.of(context).storageStrategy;
      await relay.uploadFile(job.name, job.bytes, strategy: strategy);
      if (mounted) {
        setState(() {
          job.progress = 1.0;
          job.done = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          job.error = e.toString();
        });
      }
    }
  }

  Future<void> _pick() async {
    final res = await (widget.picker ??
        () => FilePicker.platform
            .pickFiles(withData: true, allowMultiple: true))();
    if (res == null || res.files.isEmpty) return;
    final newJobs = res.files
        .where((f) => f.bytes != null)
        .map((f) => _UploadJob(f.name, f.size, f.bytes!))
        .toList();
    if (newJobs.isEmpty) return;
    setState(() => _jobs.addAll(newJobs));
    _startTicker();
    for (final job in newJobs) {
      _uploadJob(job);
    } // fire-and-forget, updates state on complete
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final hasActive = _jobs.any((j) => !j.done && j.error == null);
    final hasDone = _jobs.any((j) => j.done || j.error != null);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Upload'),
        actions: [
          if (hasDone && !hasActive)
            TextButton(
              onPressed: () => setState(
                  () => _jobs.removeWhere((j) => j.done || j.error != null)),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.upload_file),
              label: const Text('Pick files'),
            ),
          ),
        ),
        Expanded(
          child: _jobs.isEmpty
              ? const Center(child: Text('No uploads yet'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _jobs.length,
                  itemBuilder: (ctx, i) =>
                      _JobCard(job: _jobs[i], fmtSize: _fmtSize),
                ),
        ),
      ]),
    );
  }
}

class _JobCard extends StatelessWidget {
  final _UploadJob job;
  final String Function(int) fmtSize;
  const _JobCard({required this.job, required this.fmtSize});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(job.name,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Text(fmtSize(job.size), style: theme.textTheme.bodySmall),
            ]),
            const SizedBox(height: 8),
            if (job.done) ...[
              Row(children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.primary, size: 16),
                const SizedBox(width: 6),
                Text('Uploaded',
                    style: TextStyle(
                        color: theme.colorScheme.primary, fontSize: 13)),
              ]),
            ] else if (job.error != null) ...[
              Row(children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(job.error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ] else ...[
              LinearProgressIndicator(
                value: job.progress,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              const SizedBox(height: 4),
              Text('${(job.progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
