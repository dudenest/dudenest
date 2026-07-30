import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/oauth/google_drive_auth.dart';
import '../../core/storage/aggregate_engine.dart';
import '../../core/storage/direct_account.dart';
import '../../core/storage/storage_engine.dart';
import 'gallery_screen.dart';
import 'gallery_settings.dart';
import 'native_media.dart';
import 'video_player_widget.dart';

/// Tryb „Dudenest bez relay" wpięty w główną galerię za flagą `EngineMode.direct` (E3c).
///
/// Zakładki Photos/Files renderują pliki BEZPOŚREDNIO z Google Drive ([DirectEngine]), bez relaya.
/// Reużywa [GalleryScreen] (już `StorageEngine`-agnostyczny — ten sam render co ścieżka relay).
/// Connect-gate + stan błędu/retry są celowe: token GIS żyje ~1h BEZ refresh, więc wygaśnięcie
/// degraduje do „połącz ponownie", nie do pustego/zepsutego grida. `engineBuilder` to szew testowy.
class DirectModeScreen extends StatefulWidget {
  final String folder; // 'photos' | 'files'
  final StorageEngine Function()? engineBuilder; // szew testowy; default → AggregateEngine.fromAccounts (multi-konto)
  final Future<FilePickerResult?> Function()? filePicker; // szew testowy; default → FilePicker.platform
  const DirectModeScreen({super.key, required this.folder, this.engineBuilder, this.filePicker});
  @override
  State<DirectModeScreen> createState() => _DirectModeScreenState();
}

// Lokalne helpery rodzaju pliku (RelayScreen/media_viewer mają własne kopie — świadoma, drobna
// duplikacja, by NIE dotykać ścieżki relay; ewentualny wspólny util = osobny dług).
const _imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'avif', 'bmp', 'heic', 'heif'};
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
  final Set<String> _selected = {}; // multi-select do usuwania (parytet z relay path)
  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // Auto-połączenie po wejściu → /photos ładuje się OD RAZU (parytet z relayem), bez klikania Connect.
    // Tylko realna ścieżka GIS (engineBuilder==null; w testach pomijane).
    if (widget.engineBuilder == null) _autoConnect();
  }

  // Połącz bez klikania: token bierzemy z backendu (odnawia refresh po stronie serwera — ciche,
  // bez popupu). Sukces → połącz od razu (/photos jak relay). 404 not_connected (albo offline) →
  // NIC nie robimy → pokazuje się brama „Connect" (redirect zgody). Weryfikację konta robi backend.
  Future<void> _autoConnect() async {
    try {
      await getDriveAccessToken(); // backend GET; rzuca gdy brak refresh tokena
      if (mounted && _files == null && !_loading) _connect();
    } catch (_) {
      // not_connected / offline → brama Connect (redirect)
    }
  }

  // Photos = tylko renderowalne media (po ROZSZERZENIU, jak RelayScreen — deterministyczne, niezależne
  // od tego jaki mime Drive nadał uploadowi); Files = wszystko. Rozszerzenia nierenderowalne w Flutter
  // web (avif/heic/svg) świadomie POZA _imageExts → nie pokazujemy pustych kafelków w Photos.
  bool _matchesFolder(Map<String, dynamic> f) {
    if (widget.folder == 'files') return true;
    final ext = (f['name'] as String? ?? '').split('.').last.toLowerCase();
    return _imageExts.contains(ext) || _videoExts.contains(ext);
  }

  Future<void> _connect() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Multi-konto (MP1b): domyślnie agregat wszystkich kont direct usera (merge listFiles, routing per
      // account_id). Test wstrzykuje engineBuilder (fake). AccountsService cache'uje tokeny per konto.
      final engine = widget.engineBuilder != null
          ? widget.engineBuilder!.call()
          : await AggregateEngine.fromAccounts(AccountsService());
      final all = await engine.listFiles(); // konta → Drive REST wprost, bez relaya
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
    setState(() { _loading = true; _error = null; _selected.clear(); });
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
            SnackBar(content: Text('Uploaded ${jobs.length} file(s) to Google Drive.')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _toggleSelect(String id) => setState(() {
        if (!_selected.remove(id)) _selected.add(id);
      });

  // Usuń zaznaczone WPROST z Google Drive (DirectEngine.deleteFile → Drive REST) → re-list.
  // Parytet z relay path (_deleteSelected w relay_screen). Confirm dialog bo operacja destrukcyjna.
  Future<void> _deleteSelected() async {
    final count = _selected.length;
    if (count == 0) return;
    final engine = _engine;
    if (engine == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete files'),
        content: Text('Delete $count file(s) from Google Drive?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = Set<String>.from(_selected);
    setState(() { _loading = true; _error = null; _selected.clear(); });
    int failed = 0;
    for (final id in ids) {
      try {
        await engine.deleteFile(id);
      } catch (_) {
        failed++;
      }
    }
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? 'Deleted $count file(s).'
          : '$failed of $count deletions failed.'),
      backgroundColor: failed == 0 ? Colors.green : Colors.red,
    ));
  }

  // Tap → pełny podgląd przez NATYWNY element przeglądarki (blob URL): obraz KAŻDEGO formatu (avif/heic
  // też — CanvasKit ich nie dekoduje, przeglądarka tak) oraz wideo. Bajty tokenem (downloadFile).
  void _openMedia(String id, String name) {
    final engine = _engine;
    if (engine == null) return;
    final isVid = _isVideo(name);
    if (!_isImage(name) && !isVid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Preview for this file type is not supported yet.')));
      return;
    }
    final f = _files?.firstWhere((e) => e['file_id'] == id, orElse: () => const <String, dynamic>{});
    final mime = (f?['mime'] as String?)?.isNotEmpty == true
        ? f!['mime'] as String
        : (isVid ? 'video/mp4' : 'application/octet-stream');
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => _DirectMediaViewer(
            engine: engine, fileId: id, title: name, mime: mime, isVideo: isVid)));
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.folder == 'files' ? 'Files (direct)' : 'Photos (direct)';
    final selecting = _selectionMode;
    return Scaffold(
      appBar: selecting
          ? AppBar(
              leading: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear selection',
                  onPressed: () => setState(() => _selected.clear())),
              title: Text('${_selected.length} selected'),
              actions: [
                IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    tooltip: 'Delete',
                    onPressed: _loading ? null : _deleteSelected),
              ])
          : AppBar(title: Text(title), actions: [
              if (_files != null)
                IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _loading ? null : _reload),
            ]),
      body: _body(),
      floatingActionButton: (_files != null && !selecting)
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
      return const Center(child: Text('No files created by this app (drive.file).'));
    }
    return GalleryScreen(
      files: files,
      relay: _engine!,
      settings: GallerySettings(),
      selected: _selected,
      selectionMode: _selectionMode,
      onOpen: _openMedia,
      onToggleSelect: _toggleSelect,
      isImage: _isImage,
      isVideo: _isVideo,
      fileIcon: _fileIcon,
      // Etykiety kont na kafelkach tylko przy realnym multi-koncie (>1) — inaczej szum dla 1 konta.
      showAccountBadges: _engine is AggregateEngine && (_engine as AggregateEngine).accountCount > 1,
    );
  }

  // Connect = pełnostronicowy REDIRECT do backendu (zgoda Google przez redirect, NIE popup). Po
  // powrocie (?drive=connected) apka startuje i _autoConnect dostaje token z backendu → /photos.
  // Szew testowy: gdy wstrzyknięto engineBuilder (test) łączymy nim wprost (bez redirectu).
  void _onConnectPressed() {
    if (widget.engineBuilder != null) {
      _connect();
      return;
    }
    connectDrive();
  }

  Widget _connectGate() => Center(
        child: ElevatedButton.icon(
          onPressed: _onConnectPressed,
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
            Text('Could not connect to Google Drive.\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _connect, child: const Text('Reconnect')),
          ]),
        ),
      );
}

// Pełnoekranowy podgląd bez relaya przez NATYWNY element przeglądarki. Pobiera bajty tokenem
// (downloadFile) → blob URL → <img> (każdy format, w tym avif/heic) lub <video>. Blob zwalniany w dispose.
class _DirectMediaViewer extends StatefulWidget {
  final StorageEngine engine;
  final String fileId;
  final String title;
  final String mime;
  final bool isVideo;
  const _DirectMediaViewer(
      {required this.engine,
      required this.fileId,
      required this.title,
      required this.mime,
      required this.isVideo});
  @override
  State<_DirectMediaViewer> createState() => _DirectMediaViewerState();
}

class _DirectMediaViewerState extends State<_DirectMediaViewer> {
  String? _url;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.engine.downloadFile(widget.fileId); // surowe bajty, tokenem
      final url = makeObjectUrl(bytes, widget.mime);
      if (!mounted) {
        revokeObjectUrl(url);
        return;
      }
      setState(() => _url = url);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    final u = _url;
    if (u != null) revokeObjectUrl(u); // zwolnij pamięć bloba
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.title), backgroundColor: Colors.black),
        body: Center(child: _body()),
      );

  Widget _body() {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load media.\n$_error',
            style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
      );
    }
    final url = _url;
    if (url == null) return const CircularProgressIndicator();
    if (widget.isVideo) return VideoPlayerWidget(videoUrl: url, headers: const {});
    return NativeImageView(objectUrl: url);
  }
}
