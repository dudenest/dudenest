import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/storage/storage_engine.dart';
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
  /// Silnik storage gotowy do uploadu (relay: `RelayClient`; direct: dopiero po connect → null).
  final StorageEngine? engine;

  /// Connect-gate dla trybu direct: gdy `engine==null` i `onConnect!=null`, ekran pokazuje
  /// „Connect Google Drive"; naciśnięcie (user-gesture → popup GIS) buduje `DirectEngine` i zwraca go.
  /// `null` = brak bramy (ścieżka relay). Zwraca `null`, gdy user anuluje. Szew testowy zarazem.
  final Future<StorageEngine?> Function()? onConnect;
  final int autoPickNonce;
  final UploadFilePicker? picker;
  const UploadScreen(
      {super.key,
      required this.engine,
      this.onConnect,
      this.autoPickNonce = 0,
      this.picker});
  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final List<_UploadJob> _jobs = [];
  Timer? _ticker;
  StorageEngine? _engine; // relay: od razu = widget.engine; direct: po connect
  bool _connecting = false;
  String? _connectError;

  @override
  void initState() {
    super.initState();
    _engine = widget.engine;
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
    // Zmiana silnika z zewnątrz (przypisano relay, albo przełączono relay↔direct) → zresetuj stan.
    // Direct zawsze przekazuje engine==null, więc zwykłe rebuildy NIE gubią połączonego _engine.
    if (!identical(widget.engine, oldWidget.engine)) {
      _engine = widget.engine;
      _connectError = null;
    }
    if (widget.autoPickNonce != oldWidget.autoPickNonce) {
      unawaited(_pick());
    }
  }

  // Direct connect-gate: user-gesture buduje DirectEngine (popup GIS w oknie gestu). Token NIE jest
  // tu przechowywany — DirectEngine trzyma tylko funkcję getDriveAccessToken (wiązanie per-uid w niej).
  Future<void> _connect() async {
    final onConnect = widget.onConnect;
    if (onConnect == null || _connecting) return;
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    try {
      final e = await onConnect();
      if (!mounted) return;
      setState(() {
        _engine = e; // null = user anulował → zostajemy na bramie
        _connecting = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _connectError = '$err';
        _connecting = false;
      });
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
      final engine = _engine;
      if (engine == null) {
        throw 'Relay is required before uploading. Install or assign a relay in Settings.';
      }
      // Defensywnie: bez przodka DudenestApp (np. w teście) użyj domyślnej 'Replica' — jedynej
      // wspieranej od relay v0.21.0 — zamiast rzucać. W produkcji przodek zawsze jest.
      final strategy =
          context.findAncestorStateOfType<DudenestAppState>()?.storageStrategy ?? 'Replica';
      await engine.uploadFile(job.name, job.bytes, strategy: strategy);
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
    // Direct przed connect: nie otwieraj pickera (brama). Relay bez silnika: zachowanie legacy —
    // picker otwiera się, a job failuje z „Relay is required" (parytet ze starą ścieżką relay).
    if (_engine == null && widget.onConnect != null) return;
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
      // Brama connect TYLKO dla direct (onConnect!=null). Relay-path — także bez relaya — zawsze
      // pokazuje UI uploadu; brak relaya failuje per-job (parytet ze starą ścieżką relay).
      body: (_engine == null && widget.onConnect != null) ? _gate() : _uploadBody(),
    );
  }

  // Direct connect-gate: „Connect Google Drive" (+ retry po błędzie).
  Widget _gate() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_connectError != null) ...[
            const Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 40),
            const SizedBox(height: 12),
            Text('Połączenie z Google Drive nie powiodło się.\n$_connectError',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ],
          ElevatedButton.icon(
            onPressed: _connecting ? null : _connect,
            icon: _connecting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud),
            label:
                Text(_connectError != null ? 'Połącz ponownie' : 'Connect Google Drive'),
          ),
        ]),
      ),
    );
  }

  Widget _uploadBody() => Column(children: [
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
      ]);
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
