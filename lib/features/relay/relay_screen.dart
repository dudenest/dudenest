import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/relay_client.dart';
import '../../core/auth/web_utils.dart';
import '../../core/auth/auth_service.dart';
import '../storage_accounts/accounts_screen.dart';
import '../upload/upload_screen.dart';
import '../files/gallery_screen.dart';
import '../files/gallery_settings.dart';
import '../files/files_view_settings.dart'; // s329 Feature 5: /Files filter+sort+group
import '../files/files_grouped_view.dart';   // s329 Feature 5: grouped section renderer
import '../files/media_viewer.dart';
import '../files/tile_manifest_cache.dart';

enum _ViewMode { gallery, list, longNames }

/// folder: null = show all (legacy "Files" tab); "photos" = only media (P3 Photos tab);
/// "files" = only non-media (P3 Files tab). Filter is applied client-side via _matchesFolder()
/// which checks the backend-supplied `f['folder']` field (relay v0.13.0+) and falls back to
/// extension-based detection for older relays / pre-v0.11.0 uploads with stale `files/` location.
class RelayScreen extends StatefulWidget {
  final RelayClient relay;
  final String? folder; // "photos" | "files" | null
  const RelayScreen({super.key, required this.relay, this.folder});
  @override
  State<RelayScreen> createState() => _RelayScreenState();
}

class _RelayScreenState extends State<RelayScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _loading = true;
  Object? _error;
  _ViewMode _viewMode = _ViewMode.gallery;
  double? _storageUsedGb;
  double? _storageTotalGb;
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;
  GallerySettings _gallerySettings = GallerySettings();
  FilesViewSettings _filesViewSettings = const FilesViewSettings(); // s329 Feature 5

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    GallerySettings.load().then((s) {
      if (!mounted) return;
      _applyCacheLimits(s);
      setState(() => _gallerySettings = s);
    });
    if (widget.folder == 'files') {
      FilesViewSettings.load().then((s) { // s329 Feature 5: hydrate persisted /Files view state
        if (!mounted) return;
        setState(() => _filesViewSettings = s);
      });
    }
  }

  static const _imageExts = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'avif',
    'bmp',
    'heic',
    'heif'
  }; // svg excluded: no native decode in Flutter web (avif/heic OK: rendered via Drive lh3/relay thumbs)
  static const _videoExts = {'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', '3gp'};

  /// Determines whether file `f` belongs in this screen given widget.folder filter.
  /// Source-of-truth order:
  ///   1. `f['folder']` from relay v0.13.0+ — exact match.
  ///   2. Filename extension fallback for relays <v0.13.0 (no folder field) AND for legacy
  ///      pre-v0.11.0 uploads where backend may report folder="files" even for images
  ///      (those were routed to /files/ before content-type detection landed).
  bool _matchesFolder(Map<String, dynamic> f) {
    if (widget.folder == null) return true;
    if (widget.folder == 'files') return true;
    final backendFolder = f['folder'] as String?;
    final ext = ((f['name'] as String? ?? '').split('.').lastOrNull ?? '')
        .toLowerCase();
    final isMediaByExt = _imageExts.contains(ext) || _videoExts.contains(ext);
    final isMedia =
        backendFolder == 'photos' || (backendFolder != 'files' && isMediaByExt);
    return widget.folder == 'photos' ? isMedia : !isMedia;
  }

  List<Map<String, dynamic>> get _visibleFiles =>
      _files.where(_matchesFolder).toList(growable: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _applyCacheLimits(GallerySettings s) {
    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSize = s.thumbnailMemoryCacheItems;
    cache.maximumSizeBytes = s.thumbnailMemoryCacheMb * 1024 * 1024;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
    });
    final settings = await GallerySettings.load();
    _applyCacheLimits(settings);
    if (mounted) setState(() => _gallerySettings = settings);
    final cached = await TileManifestCache.load(widget.relay.baseUrl, settings);
    if (cached != null && cached.files.isNotEmpty && mounted) {
      setState(() {
        _files = cached.files;
        _loading = false;
      });
    }
    try {
      var revision = cached?.revision ?? '';
      var files = cached?.files ?? <Map<String, dynamic>>[];
      try {
        final manifest = await widget.relay.fileManifest(since: revision);
        final unchanged = manifest['unchanged'] == true;
        revision = manifest['revision'] as String? ?? revision;
        if (!unchanged) {
          files = List<Map<String, dynamic>>.from(manifest['files'] ?? []);
        }
      } on RelayException catch (e) {
        final legacyManifestMiss = e.statusCode == 404 ||
            (e.statusCode == 500 &&
                (e.body ?? '').contains('load filemap') &&
                (e.body ?? '').contains('manifest'));
        if (!legacyManifestMiss) rethrow;
        files = await widget.relay.listFiles(); // older relay compatibility
        revision = '';
      }
      await TileManifestCache.save(
          widget.relay.baseUrl, revision, files, settings);
      if (mounted) {
        setState(() {
          _files = files;
          _loading = false;
        });
      }
    } catch (e) {
      if (cached == null || cached.files.isEmpty) {
        if (mounted) {
          setState(() {
            _error = e;
            _loading = false;
          });
        }
      }
    }
    // Load storage stats non-blocking (best-effort)
    widget.relay.getProviders().then((providers) {
      final used = providers.fold<double>(
          0, (s, p) => s + ((p['quota_used_gb'] as num?)?.toDouble() ?? 0));
      final total = providers.fold<double>(
          0, (s, p) => s + ((p['quota_total_gb'] as num?)?.toDouble() ?? 0));
      if (mounted)
        setState(() {
          _storageUsedGb = used;
          _storageTotalGb = total;
        });
    }).catchError((_) {}); // non-critical — ignore errors
  }

  Future<void> _download(String fileId, String name) async {
    try {
      final bytes = await widget.relay.downloadFile(fileId);
      await downloadBytes(name, bytes);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Downloaded: $name')));
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e;
        });
    }
  }

  Future<void> _confirmDelete(String fileId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.relay.deleteFile(fileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Deleted'), backgroundColor: Colors.green));
        _load();
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e;
        });
    }
  }

  String _formatSize(dynamic bytes) {
    if (bytes == null) return '?';
    final n = bytes as num;
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  bool _isImage(String name) =>
      _imageExts.contains(name.split('.').last.toLowerCase());
  bool _isVideo(String name) =>
      _videoExts.contains(name.split('.').last.toLowerCase());
  IconData _fileIcon(String name) {
    if (_isImage(name)) return Icons.image;
    if (_isVideo(name)) return Icons.play_circle_outline;
    return Icons.insert_drive_file;
  }

  Widget _actionRow(String id, String name) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download',
            onPressed: () => _download(id, name)),
        IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(id, name)),
      ]);

  void _toggleSelect(String id) => setState(() {
        if (_selected.contains(id))
          _selected.remove(id);
        else
          _selected.add(id);
      });

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete files'),
        content: Text('Delete $count file${count == 1 ? '' : 's'}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = Set<String>.from(_selected);
    setState(() => _selected.clear());
    int failed = 0;
    for (final id in ids) {
      try {
        await widget.relay.deleteFile(id);
      } catch (_) {
        failed++;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed == 0
          ? 'Deleted $count file${count == 1 ? '' : 's'}'
          : '\$failed of $count deletions failed'),
      backgroundColor: failed == 0 ? Colors.green : Colors.red,
    ));
    _load();
  }

  Widget _buildSelectionBar() {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onSurfaceVariant;
    return Material(
      elevation: 4,
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            const SizedBox(width: 16),
            Text('${_selected.length} selected',
                style: TextStyle(fontWeight: FontWeight.w500, color: fg)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.photo_album, color: fg.withValues(alpha: 0.5)),
              tooltip: 'Add to album — coming soon',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Add to album — coming soon'),
                      duration: Duration(seconds: 1))),
            ),
            IconButton(
              icon: Icon(Icons.share, color: fg.withValues(alpha: 0.5)),
              tooltip: 'Share — coming soon',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Share — coming soon'),
                      duration: Duration(seconds: 1))),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete selected',
              onPressed: _deleteSelected,
            ),
            IconButton(
              icon: Icon(Icons.close, color: fg),
              tooltip: 'Cancel selection',
              onPressed: () => setState(() => _selected.clear()),
            ),
            const SizedBox(width: 4),
          ]),
        ),
      ),
    );
  }

  // Small leading thumbnail for list views (images: thumbnail; others: icon)
  Widget _buildLeading(String name, String id) {
    const sz = 44.0;
    if (widget.folder == 'files') {
      return SizedBox(
          width: sz, height: sz, child: Center(child: Icon(_fileIcon(name))));
    }
    if (_isImage(name)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image(
          image: widget.relay.thumbnail(id),
          width: sz,
          height: sz,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(
              width: sz,
              height: sz,
              child: Center(child: Icon(_fileIcon(name)))),
          loadingBuilder: (_, child, p) => p == null
              ? child
              : const SizedBox(
                  width: sz,
                  height: sz,
                  child:
                      Center(child: CircularProgressIndicator(strokeWidth: 1))),
        ),
      );
    }
    return SizedBox(
        width: sz, height: sz, child: Center(child: Icon(_fileIcon(name))));
  }

  // Opens file in MediaViewer (images + videos inline) or downloads others.
  void _openFile(BuildContext ctx, String id, String name) {
    if (widget.folder == 'files' && !(_isImage(name) || _isVideo(name))) {
      _download(id, name);
      return;
    }
    if (_isImage(name) || _isVideo(name)) {
      // Sort files by taken_at/created (newest first) — matches gallery display order for consistent swipe navigation.
      // Use _visibleFiles so the swipe set respects the active Photos/Files filter.
      final sorted = [..._visibleFiles]..sort((a, b) {
          DateTime dateOf(Map<String, dynamic> f) {
            final t = f['taken_at'] as String? ?? f['created'] as String? ?? '';
            return DateTime.tryParse(t) ?? DateTime(2000);
          }

          return dateOf(b).compareTo(dateOf(a));
        });
      final idx = sorted.indexWhere((f) => f['file_id'] == id);
      Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => MediaViewer(
              files: sorted,
              initialIndex: idx < 0 ? 0 : idx,
              relay: widget.relay,
              onDelete: () {
                Navigator.pop(ctx);
                _load();
              },
            ),
          ));
    } else {
      _download(id, name);
    }
  }

  // ─── Gallery view: wraps GalleryScreen (Justified/Masonry/Square/List) ──────
  Widget _buildGallery() => GalleryScreen(
        files: _visibleFiles,
        relay: widget.relay,
        settings: _gallerySettings,
        selected: _selected,
        selectionMode: _selectionMode,
        onOpen: (id, name) => _openFile(context, id, name),
        onToggleSelect: _toggleSelect,
        isImage: _isImage,
        isVideo: _isVideo,
        fileIcon: _fileIcon,
      );

  // ─── List view ──────────────────────────────────────────────────────────────
  Widget _buildList() {
    final files = _visibleFiles;
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (ctx, i) {
        final f = files[i];
        final id = f['file_id'] as String? ?? '';
        final name = f['name'] as String? ?? id;
        final ext = _extensionLabel(name);
        final isSelected = _selected.contains(id);
        return ListTile(
          selected: isSelected,
          leading: _buildLeading(name, id),
          title: Text(name, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${ext.isEmpty ? 'file' : ext} · ${_formatSize(f['size'])} · ${id.length >= 8 ? '${id.substring(0, 8)}...' : id}'),
          trailing: _selectionMode
              ? Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(ctx).colorScheme.primary
                      : Colors.grey)
              : _actionRow(id, name),
          onTap: () =>
              _selectionMode ? _toggleSelect(id) : _openFile(ctx, id, name),
          onLongPress: () => _toggleSelect(id),
        );
      },
    );
  }

  // s329 Feature 5: grouped/sorted/filtered Files view. groupAndSort() is a pure helper
  // (unit-tested in test/unit/files_view_settings_test.dart); this just wires _filesViewSettings
  // into FilesGroupedView and reuses _buildList's ListTile rendering for individual files.
  Widget _buildGroupedFiles() {
    final groups = groupAndSort(_visibleFiles, _filesViewSettings);
    Widget tile(BuildContext ctx, Map<String, dynamic> f) {
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? id;
      final ext = _extensionLabel(name);
      final isSelected = _selected.contains(id);
      return ListTile(
        selected: isSelected, dense: true,
        leading: _buildLeading(name, id),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: Text('${ext.isEmpty ? 'file' : ext} · ${_formatSize(f['size'])}'),
        trailing: _selectionMode
            ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Theme.of(ctx).colorScheme.primary : Colors.grey)
            : _actionRow(id, name),
        onTap: () => _selectionMode ? _toggleSelect(id) : _openFile(ctx, id, name),
        onLongPress: () => _toggleSelect(id),
      );
    }
    final s = _filesViewSettings;
    final hasFilters = s.searchQuery.isNotEmpty || s.typeFilters.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasFilters) Container( // s329 Feature 5: active filter strip — visible cue + tap to edit
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (s.searchQuery.isNotEmpty) InputChip(
            avatar: const Icon(Icons.search, size: 16),
            label: Text('"${s.searchQuery}"'),
            onDeleted: () => _saveFilesViewSettings(s.copyWith(searchQuery: '')),
          ),
          for (final t in s.typeFilters) InputChip(
            label: Text(t[0].toUpperCase() + t.substring(1)),
            onDeleted: () => _saveFilesViewSettings(s.copyWith(typeFilters: {...s.typeFilters}..remove(t))),
          ),
        ]),
      ),
      Expanded(child: FilesGroupedView(groups: groups, itemBuilder: tile)),
    ]);
  }

  Future<void> _openFilesFilters() async {
    final updated = await showModalBottomSheet<FilesViewSettings>(
      context: context, isScrollControlled: true, useSafeArea: true,
      builder: (_) => FilesFilterSheet(initial: _filesViewSettings),
    );
    if (updated != null) _saveFilesViewSettings(updated);
  }

  void _saveFilesViewSettings(FilesViewSettings s) {
    setState(() => _filesViewSettings = s);
    s.save(); // fire-and-forget — local-only persistence, no error path
  }

  String _extensionLabel(String name) {
    final parts = name.split('.');
    if (parts.length < 2 || parts.last.isEmpty) return 'file';
    return parts.last.toUpperCase();
  }

  // ─── Long names view ────────────────────────────────────────────────────────
  Widget _buildLongNames() {
    final files = _visibleFiles;
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (ctx, i) {
        final f = files[i];
        final id = f['file_id'] as String? ?? '';
        final name = f['name'] as String? ?? id;
        final isSelected = _selected.contains(id);
        return ListTile(
          selected: isSelected,
          leading: _buildLeading(name, id),
          title: Text(name),
          subtitle: Text(_formatSize(f['size'])),
          isThreeLine: name.length > 35,
          trailing: _selectionMode
              ? Icon(
                  isSelected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(ctx).colorScheme.primary
                      : Colors.grey)
              : _actionRow(id, name),
          onTap: () =>
              _selectionMode ? _toggleSelect(id) : _openFile(ctx, id, name),
          onLongPress: () => _toggleSelect(id),
        );
      },
    );
  }

  IconData _modeIcon(_ViewMode m) => switch (m) {
        _ViewMode.gallery => Icons.image,
        _ViewMode.list => Icons.list,
        _ViewMode.longNames => Icons.text_snippet,
      };
  String _modeLabel(_ViewMode m) => switch (m) {
        _ViewMode.gallery => 'Gallery',
        _ViewMode.list => 'List',
        _ViewMode.longNames => 'Long names',
      };
  IconData _galleryLayoutIcon(GalleryViewMode m) => switch (m) {
        GalleryViewMode.justified => Icons.view_stream,
        GalleryViewMode.masonry => Icons.dashboard,
        GalleryViewMode.square => Icons.grid_on,
        GalleryViewMode.list => Icons.list,
      };

  Future<void> _openGallerySettings() async {
    final result = await showModalBottomSheet<GallerySettings>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GallerySettingsSheet(initial: _gallerySettings),
    );
    if (result != null && mounted) {
      await result.save();
      setState(() => _gallerySettings = result);
    }
  }

  static const _kVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      if (_error is RelayException &&
          (_error as RelayException).statusCode == 503) {
        return _WelcomeScreen(relay: widget.relay);
      }
      return _ErrorDisplay(
          error: _error!,
          onRetry: _load,
          onBack: () => setState(() => _error = null));
    }
    if (_visibleFiles.isEmpty)
      return _NoFilesEmptyState(relay: widget.relay, onUploaded: _load);
    if (widget.folder == 'files') {
      // s329 Feature 5: grouped view (default) — uses _filesViewSettings (group/sort/filter/search).
      // longNames mode kept as the alternative flat-list rendering for users preferring no grouping.
      return _viewMode == _ViewMode.longNames
          ? _buildLongNames()
          : _buildGroupedFiles();
    }
    return switch (_viewMode) {
      _ViewMode.gallery => _buildGallery(),
      _ViewMode.list => _buildList(),
      _ViewMode.longNames => _buildLongNames(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _selectionMode
            ? Text('${_selected.length} selected')
            : Text(widget.folder == 'photos'
                ? 'Photos'
                : (widget.folder == 'files' ? 'Files' : 'Files')),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: () => setState(() => _selected.clear()),
              )
            : null,
        actions: [
          if (_storageUsedGb != null && _storageTotalGb != null)
            Tooltip(
              message: 'Storage used — tap to manage accounts',
              child: GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => AccountsScreen(relay: widget.relay))),
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(
                      '${_storageUsedGb!.toStringAsFixed(1)}/${_storageTotalGb!.toStringAsFixed(1)} GB',
                      style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: scheme.onSecondaryContainer,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          if (AuthService().isDemo)
            const _DemoBadge()  // demo mode: slow green fade "DEMO" replaces the version chip
          else
            Tooltip(
              message: 'App version — view on GitHub',
              child: GestureDetector(
                onTap: () => launchUrl(
                    Uri.parse('https://github.com/dudenest/dudenest'),
                    mode: LaunchMode.externalApplication),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(_kVersion,
                      style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          if (!_selectionMode) ...[
            for (final mode in widget.folder == 'files'
                ? const [_ViewMode.list]
                : const [_ViewMode.gallery, _ViewMode.list])
              IconButton(
                icon: Icon(_modeIcon(mode),
                    color: _viewMode == mode ? scheme.primary : null),
                tooltip: _modeLabel(mode),
                onPressed: () => setState(() => _viewMode = mode),
              ),
            if (widget.folder != 'files' && _viewMode == _ViewMode.gallery)
              IconButton(
                icon: const Icon(Icons.more_vert),
                tooltip: 'Gallery settings',
                onPressed: _openGallerySettings,
              ),
            if (widget.folder == 'files') IconButton( // s329 Feature 5: open group/sort/filter sheet
              icon: const Icon(Icons.tune),
              tooltip: 'Group, sort, filter',
              onPressed: _openFilesFilters,
            ),
            IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _load,
                tooltip: 'Refresh'),
          ],
        ],
      ),
      body: Stack(children: [
        Padding(
          padding: EdgeInsets.only(bottom: _selectionMode ? 56 : 0),
          child: _buildContent(),
        ),
        if (_selectionMode)
          Positioned(bottom: 0, left: 0, right: 0, child: _buildSelectionBar()),
      ]),
      // Upload is reachable from every section, not just the empty state — when photos/files
      // already exist the empty-state button is gone, so this FAB keeps upload one tap away.
      floatingActionButton: (!_selectionMode &&
              !_loading &&
              _error == null &&
              _visibleFiles.isNotEmpty)
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.push(context,
                    MaterialPageRoute(builder: (_) => UploadScreen(engine: widget.relay)));
                _load(); // refresh /files when the user returns
              },
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload'),
            )
          : null,
    );
  }
}

// ─── Error Display Widget (Duplicated from accounts_screen for consistency) ───

class _ErrorDisplay extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final VoidCallback? onBack;
  const _ErrorDisplay(
      {required this.error, required this.onRetry, this.onBack});

  @override
  Widget build(BuildContext context) {
    String msg = error.toString();
    String? body;
    int? code;
    if (error is RelayException) {
      final re = error as RelayException;
      msg = re.message;
      code = re.statusCode;
      body = re.body;
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: $msg',
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          if (code != null) ...[
            const SizedBox(height: 8),
            Text('Status Code: $code',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(
                  body.length > 500 ? body.substring(0, 500) + '...' : body,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                  maxLines: 10,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
          const SizedBox(height: 24),
          Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: onBack ??
                      () {
                        if (Navigator.of(context).canPop())
                          Navigator.of(context).pop();
                      },
                  child: const Text('Back'),
                ),
                ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
              ]),
        ]),
      ),
    );
  }
}

// ─── No files yet (cloud account exists, index empty) ───────────────────────
// Distinct from _WelcomeScreen: this is shown when /files succeeds with []
// (provider authorized, just nothing uploaded/indexed yet). Offers two actions:
// upload the first file, or wire up another cloud account.

class _NoFilesEmptyState extends StatelessWidget {
  final RelayClient relay;
  final VoidCallback onUploaded;
  const _NoFilesEmptyState({required this.relay, required this.onUploaded});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_done, size: 64, color: scheme.primary),
          const SizedBox(height: 24),
          Text('No files yet',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            'Your cloud account is connected. Upload your first file, or connect another cloud account to expand storage.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload'),
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => UploadScreen(engine: relay)));
              onUploaded(); // refresh /files when user returns
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.cloud),
            label: const Text('Add Cloud Account'),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AccountsScreen(relay: relay))),
          ),
        ]),
      ),
    );
  }
}

// ─── Welcome / Onboarding Screen (shown on 503 relay standby) ────────────────

class _WelcomeScreen extends StatelessWidget {
  final RelayClient relay;
  const _WelcomeScreen({required this.relay});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.cloud_outlined, size: 64, color: scheme.primary),
          const SizedBox(height: 24),
          Text('Welcome to Dudenest!',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            'Your relay is ready.\nConnect a cloud account to start storing files securely.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.cloud),
            label: const Text('Add Cloud Account'),
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => AccountsScreen(relay: relay))),
          ),
        ]),
      ),
    );
  }
}

// ─── Gallery Settings Bottom Sheet ───────────────────────────────────────────

class _GallerySettingsSheet extends StatefulWidget {
  final GallerySettings initial;
  const _GallerySettingsSheet({required this.initial});
  @override
  State<_GallerySettingsSheet> createState() => _GallerySettingsSheetState();
}

class _GallerySettingsSheetState extends State<_GallerySettingsSheet> {
  late GallerySettings _s;

  @override
  void initState() {
    super.initState();
    _s = GallerySettings(
      viewMode: widget.initial.viewMode,
      justifiedRowHeight: widget.initial.justifiedRowHeight,
      autoResizeRowHeight: widget.initial.autoResizeRowHeight,
      masonryColumns: widget.initial.masonryColumns,
      groupByDate: widget.initial.groupByDate,
      showDateHeaders: widget.initial.showDateHeaders,
      showDateScrubbar: widget.initial.showDateScrubbar,
      localTileCacheEnabled: widget.initial.localTileCacheEnabled,
      localTileCacheMaxItems: widget.initial.localTileCacheMaxItems,
      localTileCacheMaxBytes: widget.initial.localTileCacheMaxBytes,
      thumbnailMemoryCacheMb: widget.initial.thumbnailMemoryCacheMb,
      thumbnailMemoryCacheItems: widget.initial.thumbnailMemoryCacheItems,
    );
  }

  void _apply() => Navigator.pop(context, _s);

  GallerySettings _with({
    GalleryViewMode? viewMode,
    double? justifiedRowHeight,
    bool? autoResizeRowHeight,
    int? masonryColumns,
    bool? groupByDate,
    bool? showDateHeaders,
    bool? showDateScrubbar,
    bool? localTileCacheEnabled,
    int? localTileCacheMaxItems,
    int? localTileCacheMaxBytes,
    int? thumbnailMemoryCacheMb,
    int? thumbnailMemoryCacheItems,
  }) =>
      GallerySettings(
        viewMode: viewMode ?? _s.viewMode,
        justifiedRowHeight: justifiedRowHeight ?? _s.justifiedRowHeight,
        autoResizeRowHeight: autoResizeRowHeight ?? _s.autoResizeRowHeight,
        masonryColumns: masonryColumns ?? _s.masonryColumns,
        groupByDate: groupByDate ?? _s.groupByDate,
        showDateHeaders: showDateHeaders ?? _s.showDateHeaders,
        showDateScrubbar: showDateScrubbar ?? _s.showDateScrubbar,
        localTileCacheEnabled:
            localTileCacheEnabled ?? _s.localTileCacheEnabled,
        localTileCacheMaxItems:
            localTileCacheMaxItems ?? _s.localTileCacheMaxItems,
        localTileCacheMaxBytes:
            localTileCacheMaxBytes ?? _s.localTileCacheMaxBytes,
        thumbnailMemoryCacheMb:
            thumbnailMemoryCacheMb ?? _s.thumbnailMemoryCacheMb,
        thumbnailMemoryCacheItems:
            thumbnailMemoryCacheItems ?? _s.thumbnailMemoryCacheItems,
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layouts = [
      (GalleryViewMode.justified, Icons.view_stream, 'Justified'),
      (GalleryViewMode.masonry, Icons.dashboard, 'Masonry'),
      (GalleryViewMode.square, Icons.grid_on, 'Square'),
      (GalleryViewMode.list, Icons.list, 'List'),
    ];
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(children: [
              Text('Gallery settings',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton(onPressed: _apply, child: const Text('Apply')),
            ]),
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Layout',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Row(
                  children: layouts.map((t) {
                final (mode, icon, label) = t;
                final selected = _s.viewMode == mode;
                return Expanded(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _s = _with(viewMode: mode)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color:
                                selected ? scheme.primary : Colors.transparent,
                            width: 2),
                      ),
                      child: Column(children: [
                        Icon(icon,
                            color: selected
                                ? scheme.primary
                                : scheme.onSurfaceVariant),
                        const SizedBox(height: 4),
                        Text(label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: selected
                                    ? scheme.primary
                                    : scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 16),
              if (_s.viewMode == GalleryViewMode.justified) ...[
                // s329 Feature 6: auto-resize toggle + extended slider range 20-400 (was 120-320).
                // When auto ON, the slider value is grayed out and serves only as the maximum cap
                // for viewport-derived row height. When OFF, slider value is used as fixed targetH.
                SwitchListTile.adaptive(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Auto-resize with browser window'),
                  subtitle: const Text('Tiles scale proportionally to viewport — no jump-back on resize'),
                  value: _s.autoResizeRowHeight,
                  onChanged: (v) => setState(() => _s = _with(autoResizeRowHeight: v)),
                ),
                Text(
                    _s.autoResizeRowHeight
                        ? 'Max row height (auto): ${_s.justifiedRowHeight.round()} px'
                        : 'Row height (fixed): ${_s.justifiedRowHeight.round()} px',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                Slider(
                  value: _s.justifiedRowHeight.clamp(GallerySettings.minRowHeight, GallerySettings.maxRowHeight),
                  min: GallerySettings.minRowHeight, // 20 — user request 2026-05-30
                  max: GallerySettings.maxRowHeight, // 400 — extended from 320
                  divisions: ((GallerySettings.maxRowHeight - GallerySettings.minRowHeight) / 10).round(), // 10px steps → 38 divisions
                  label: '${_s.justifiedRowHeight.round()} px',
                  onChanged: (v) =>
                      setState(() => _s = _with(justifiedRowHeight: v)),
                ),
              ],
              if (_s.viewMode == GalleryViewMode.masonry) ...[
                Text('Columns: ${_s.masonryColumns}',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                Slider(
                  value: _s.masonryColumns.toDouble(),
                  min: 2,
                  max: 4,
                  divisions: 2,
                  label: '${_s.masonryColumns}',
                  onChanged: (v) =>
                      setState(() => _s = _with(masonryColumns: v.round())),
                ),
              ],
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Group by date'),
                value: _s.groupByDate,
                onChanged: (v) => setState(() => _s = _with(groupByDate: v)),
              ),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Show date headers'),
                value: _s.showDateHeaders,
                onChanged: (v) =>
                    setState(() => _s = _with(showDateHeaders: v)),
              ),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Show timeline scrubbar'),
                value: _s.showDateScrubbar,
                onChanged: (v) =>
                    setState(() => _s = _with(showDateScrubbar: v)),
              ),
              const Divider(height: 24),
              SwitchListTile.adaptive(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Local tile cache'),
                value: _s.localTileCacheEnabled,
                onChanged: (v) =>
                    setState(() => _s = _with(localTileCacheEnabled: v)),
              ),
              Text('Tile cache: ${_s.localTileCacheMaxItems} items',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Slider(
                value: _s.localTileCacheMaxItems.toDouble(),
                min: 500,
                max: 20000,
                divisions: 39,
                label: '${_s.localTileCacheMaxItems}',
                onChanged: (v) => setState(
                    () => _s = _with(localTileCacheMaxItems: v.round())),
              ),
              Text(
                  'Tile cache size: ${(_s.localTileCacheMaxBytes / 1024 / 1024).round()} MB',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Slider(
                value: (_s.localTileCacheMaxBytes / 1024 / 1024).toDouble(),
                min: 2,
                max: 64,
                divisions: 31,
                label:
                    '${(_s.localTileCacheMaxBytes / 1024 / 1024).round()} MB',
                onChanged: (v) => setState(() => _s =
                    _with(localTileCacheMaxBytes: v.round() * 1024 * 1024)),
              ),
              Text('Thumbnail memory LRU: ${_s.thumbnailMemoryCacheMb} MB',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Slider(
                value: _s.thumbnailMemoryCacheMb.toDouble(),
                min: 32,
                max: 512,
                divisions: 15,
                label: '${_s.thumbnailMemoryCacheMb} MB',
                onChanged: (v) => setState(
                    () => _s = _with(thumbnailMemoryCacheMb: v.round())),
              ),
              Text('Thumbnail LRU items: ${_s.thumbnailMemoryCacheItems}',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
              Slider(
                value: _s.thumbnailMemoryCacheItems.toDouble(),
                min: 200,
                max: 5000,
                divisions: 24,
                label: '${_s.thumbnailMemoryCacheItems}',
                onChanged: (v) => setState(
                    () => _s = _with(thumbnailMemoryCacheItems: v.round())),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
  }
}

// Slowly-pulsing green "DEMO" badge shown in place of the version chip in demo mode.
class _DemoBadge extends StatefulWidget {
  const _DemoBadge();
  @override
  State<_DemoBadge> createState() => _DemoBadgeState();
}

class _DemoBadgeState extends State<_DemoBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);
  late final Animation<double> _fade =
      Tween<double>(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
            color: const Color(0x2234C759),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF34C759))),
        child: const Text('DEMO',
            style: TextStyle(
                fontSize: 11,
                letterSpacing: 1.5,
                color: Color(0xFF34C759),
                fontWeight: FontWeight.w700)),
      ),
    );
  }
}
