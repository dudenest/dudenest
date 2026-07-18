import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/oauth/google_drive_auth.dart';
import '../../core/storage/direct_engine.dart';
import '../../core/storage/storage_engine.dart';
import 'gallery_screen.dart';
import 'gallery_settings.dart';

/// Tryb „Dudenest bez relay" wpięty w główną galerię za flagą `EngineMode.direct` (E3c).
///
/// Zakładki Photos/Files renderują pliki BEZPOŚREDNIO z Google Drive ([DirectEngine]), bez relaya.
/// Reużywa [GalleryScreen] (już `StorageEngine`-agnostyczny — ten sam render co ścieżka relay).
/// Connect-gate + stan błędu/retry są celowe: token GIS żyje ~1h BEZ refresh, więc wygaśnięcie
/// degraduje do „połącz ponownie", nie do pustego/zepsutego grida. `engineBuilder` to szew testowy.
class DirectModeScreen extends StatefulWidget {
  final String folder; // 'photos' | 'files'
  final StorageEngine Function()? engineBuilder; // default → DirectEngine(getDriveAccessToken)
  final Future<FilePickerResult?> Function()? filePicker; // szew testowy; default → FilePicker.platform
  const DirectModeScreen({super.key, required this.folder, this.engineBuilder, this.filePicker});
  @override
  State<DirectModeScreen> createState() => _DirectModeScreenState();
}

// Lokalne helpery rodzaju pliku (RelayScreen/media_viewer mają własne kopie — świadoma, drobna
// duplikacja, by NIE dotykać ścieżki relay; ewentualny wspólny util = osobny dług).
const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'};
const _videoExts = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp', 'wmv', 'flv'};
bool _isImage(String n) => _imageExts.contains(n.split('.').last.toLowerCase());
bool _isVideo(String n) => _videoExts.contains(n.split('.').last.toLowerCase());
IconData _fileIcon(String n) => _isImage(n)
    ? Icons.image
    : _isVideo(n)
        ? Icons.play_circle_outline
        : Icons.insert_drive_file;

class _DirectModeScreenState extends State<DirectModeScreen> {
  StorageEngine? _engine;
  List<Map<String, dynamic>>? _files;
  String? _error;
  bool _loading = false;

  // Photos = tylko media (backend `folder` lub rozszerzenie); Files = wszystko (parytet z RelayScreen).
  bool _matchesFolder(Map<String, dynamic> f) {
    if (widget.folder == 'files') return true;
    final backend = f['folder'] as String?;
    final ext = (f['name'] as String? ?? '').split('.').last.toLowerCase();
    return backend == 'photos' || _imageExts.contains(ext) || _videoExts.contains(ext);
  }

  Future<void> _connect() async {
    setState(() { _loading = true; _error = null; });
    try {
      final engine = widget.engineBuilder?.call() ?? DirectEngine(accessToken: getDriveAccessToken);
      final all = await engine.listFiles(); // OAuth GIS → Drive REST, bez relaya
      final files = all.where(_matchesFolder).toList(growable: false);
      if (!mounted) return;
      setState(() { _engine = engine; _files = files; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; }); // obejmuje 401 po wygaśnięciu tokenu → retry
    }
  }

  // Ponowne wylistowanie ISTNIEJĄCYM silnikiem (reużywa token) — po uploadzie i przy „Odśwież".
  Future<void> _reload() async {
    final engine = _engine;
    if (engine == null) return _connect();
    setState(() { _loading = true; _error = null; });
    try {
      final files = (await engine.listFiles()).where(_matchesFolder).toList(growable: false);
      if (!mounted) return;
      setState(() { _files = files; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  // Upload plików WPROST do Google Drive (DirectEngine, bez relaya) → re-list. User-gesture (FAB).
  Future<void> _upload() async {
    final engine = _engine;
    if (engine == null) return;
    final pick = widget.filePicker ??
        () => FilePicker.platform.pickFiles(withData: true, allowMultiple: true);
    final res = await pick();
    final jobs = res?.files.where((f) => f.bytes != null).toList() ?? const [];
    if (jobs.isEmpty) return; // anulowano / brak bajtów
    setState(() { _loading = true; _error = null; });
    try {
      for (final f in jobs) {
        await engine.uploadFile(f.name, f.bytes!);
      }
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Wgrano ${jobs.length} plik(ów) do Google Drive.')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  // MVP: tap na obrazie → pełny podgląd przez StorageEngine.original. Wideo/pliki nie-obrazowe odroczone.
  void _openImage(String id, String name) {
    final engine = _engine;
    if (engine == null || !_isImage(name)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Podgląd wideo i plików nie-obrazowych: wkrótce (tryb direct MVP).')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => _DirectImageViewer(image: engine.original(id), title: name)));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.folder == 'files' ? 'Files (direct)' : 'Photos (direct)';
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [
        if (_files != null)
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Odśwież', onPressed: _loading ? null : _reload),
      ]),
      body: _body(),
      floatingActionButton: _files != null
          ? FloatingActionButton.extended(
              onPressed: _loading ? null : _upload,
              icon: const Icon(Icons.upload),
              label: const Text('Upload'))
          : null,
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorState();
    final files = _files;
    if (files == null) return _connectGate();
    if (files.isEmpty) {
      return const Center(child: Text('Brak plików utworzonych przez tę aplikację (drive.file).'));
    }
    return GalleryScreen(
      files: files,
      relay: _engine!,
      settings: GallerySettings(),
      selected: const <String>{},
      selectionMode: false,
      onOpen: _openImage,
      onToggleSelect: (_) {},
      isImage: _isImage,
      isVideo: _isVideo,
      fileIcon: _fileIcon,
    );
  }

  Widget _connectGate() => Center(
        child: ElevatedButton.icon(
          onPressed: _connect,
          icon: const Icon(Icons.cloud),
          label: const Text('Connect Google Drive'),
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, color: Colors.orangeAccent, size: 40),
            const SizedBox(height: 12),
            Text('Połączenie z Google Drive nie powiodło się.\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _connect, child: const Text('Połącz ponownie')),
          ]),
        ),
      );
}

// Minimalny pełnoekranowy podgląd obrazu (bez relaya) — bajty z Drive przez StorageEngine.original.
class _DirectImageViewer extends StatelessWidget {
  final ImageProvider image;
  final String title;
  const _DirectImageViewer({required this.image, required this.title});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(title), backgroundColor: Colors.black),
        body: Center(
          child: InteractiveViewer(
            child: Image(
              image: image,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white24, size: 64),
            ),
          ),
        ),
      );
}
