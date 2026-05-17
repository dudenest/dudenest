import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/relay_client.dart';
import '../../core/auth/web_utils.dart';
import '../storage_accounts/accounts_screen.dart';
import '../files/gallery_screen.dart';
import '../files/gallery_settings.dart';
import '../files/media_viewer.dart';

enum _ViewMode { gallery, list, longNames }

class RelayScreen extends StatefulWidget {
  final RelayClient relay;
  const RelayScreen({super.key, required this.relay});
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    GallerySettings.load().then((s) { if (mounted) setState(() => _gallerySettings = s); });
  }

  static const _imageExts = {'jpg','jpeg','png','gif','webp','bmp','heic','heif'};  // svg excluded: no native decode in Flutter web
  static const _videoExts = {'mp4','mov','avi','mkv','webm','m4v','3gp'};

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _selected.clear(); });
    try {
      final files = await widget.relay.listFiles();
      setState(() { _files = files; _loading = false; });
    } catch (e) {
      setState(() { _error = e; _loading = false; });
    }
    // Load storage stats non-blocking (best-effort)
    widget.relay.getProviders().then((providers) {
      final used = providers.fold<double>(0, (s, p) => s + ((p['quota_used_gb'] as num?)?.toDouble() ?? 0));
      final total = providers.fold<double>(0, (s, p) => s + ((p['quota_total_gb'] as num?)?.toDouble() ?? 0));
      if (mounted) setState(() { _storageUsedGb = used; _storageTotalGb = total; });
    }).catchError((_) {});  // non-critical — ignore errors
  }

  Future<void> _download(String fileId, String name) async {
    try {
      final bytes = await widget.relay.downloadFile(fileId);
      await downloadBytes(name, bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded: $name')));
    } catch (e) {
      if (mounted) setState(() { _error = e; });
    }
  }

  Future<void> _confirmDelete(String fileId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file'),
        content: Text('Delete "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.relay.deleteFile(fileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted'), backgroundColor: Colors.green));
        _load();
      }
    } catch (e) {
      if (mounted) setState(() { _error = e; });
    }
  }

  String _formatSize(dynamic bytes) {
    if (bytes == null) return '?';
    final n = bytes as num;
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  bool _isImage(String name) => _imageExts.contains(name.split('.').last.toLowerCase());
  bool _isVideo(String name) => _videoExts.contains(name.split('.').last.toLowerCase());
  IconData _fileIcon(String name) {
    if (_isImage(name)) return Icons.image;
    if (_isVideo(name)) return Icons.play_circle_outline;
    return Icons.insert_drive_file;
  }

  Widget _actionRow(String id, String name) => Row(mainAxisSize: MainAxisSize.min, children: [
    IconButton(icon: const Icon(Icons.download), tooltip: 'Download', onPressed: () => _download(id, name)),
    IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: 'Delete', onPressed: () => _confirmDelete(id, name)),
  ]);

  void _toggleSelect(String id) => setState(() {
    if (_selected.contains(id)) _selected.remove(id); else _selected.add(id);
  });

  Future<void> _deleteSelected() async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete files'),
        content: Text('Delete $count file${count == 1 ? '' : 's'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final ids = Set<String>.from(_selected);
    setState(() => _selected.clear());
    int failed = 0;
    for (final id in ids) {
      try { await widget.relay.deleteFile(id); } catch (_) { failed++; }
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
              icon: Icon(Icons.photo_album_outlined, color: fg.withValues(alpha: 0.5)),
              tooltip: 'Add to album — coming soon',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add to album — coming soon'), duration: Duration(seconds: 1))),
            ),
            IconButton(
              icon: Icon(Icons.share_outlined, color: fg.withValues(alpha: 0.5)),
              tooltip: 'Share — coming soon',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Share — coming soon'), duration: Duration(seconds: 1))),
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
    if (_isImage(name)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          '${widget.relay.baseUrl}/files/$id/thumbnail',
          headers: widget.relay.headers,
          width: sz, height: sz, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => SizedBox(width: sz, height: sz,
              child: Center(child: Icon(_fileIcon(name)))),
          loadingBuilder: (_, child, p) => p == null ? child
              : const SizedBox(width: sz, height: sz,
                  child: Center(child: CircularProgressIndicator(strokeWidth: 1))),
        ),
      );
    }
    return SizedBox(width: sz, height: sz, child: Center(child: Icon(_fileIcon(name))));
  }

  // Opens file in MediaViewer (images + videos inline) or downloads others.
  void _openFile(BuildContext ctx, String id, String name) {
    if (_isImage(name) || _isVideo(name)) {
      // Sort files by taken_at/created (newest first) — matches gallery display order for consistent swipe navigation.
      final sorted = [..._files]..sort((a, b) {
        DateTime dateOf(Map<String, dynamic> f) {
          final t = f['taken_at'] as String? ?? f['created'] as String? ?? '';
          return DateTime.tryParse(t) ?? DateTime(2000);
        }
        return dateOf(b).compareTo(dateOf(a));
      });
      final idx = sorted.indexWhere((f) => f['file_id'] == id);
      Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => MediaViewer(
          files: sorted,
          initialIndex: idx < 0 ? 0 : idx,
          relay: widget.relay,
          onDelete: () { Navigator.pop(ctx); _load(); },
        ),
      ));
    } else {
      _download(id, name);
    }
  }

  // ─── Gallery view: wraps GalleryScreen (Justified/Masonry/Square/List) ──────
  Widget _buildGallery() => GalleryScreen(
    files: _files,
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
  Widget _buildList() => ListView.builder(
    itemCount: _files.length,
    itemBuilder: (ctx, i) {
      final f = _files[i];
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? id;
      final isSelected = _selected.contains(id);
      return ListTile(
        selected: isSelected,
        leading: _buildLeading(name, id),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: Text('${_formatSize(f['size'])} · ${id.length >= 8 ? '${id.substring(0, 8)}...' : id}'),
        trailing: _selectionMode
            ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Theme.of(ctx).colorScheme.primary : Colors.grey)
            : _actionRow(id, name),
        onTap: () => _selectionMode ? _toggleSelect(id) : _openFile(ctx, id, name),
        onLongPress: () => _toggleSelect(id),
      );
    },
  );

  // ─── Long names view ────────────────────────────────────────────────────────
  Widget _buildLongNames() => ListView.builder(
    itemCount: _files.length,
    itemBuilder: (ctx, i) {
      final f = _files[i];
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
            ? Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isSelected ? Theme.of(ctx).colorScheme.primary : Colors.grey)
            : _actionRow(id, name),
        onTap: () => _selectionMode ? _toggleSelect(id) : _openFile(ctx, id, name),
        onLongPress: () => _toggleSelect(id),
      );
    },
  );

  IconData _modeIcon(_ViewMode m) => switch (m) {
    _ViewMode.gallery => Icons.photo_library_outlined,
    _ViewMode.list => Icons.list,
    _ViewMode.longNames => Icons.text_snippet,
  };
  String _modeLabel(_ViewMode m) => switch (m) {
    _ViewMode.gallery => 'Gallery',
    _ViewMode.list => 'List',
    _ViewMode.longNames => 'Long names',
  };
  IconData _galleryLayoutIcon(GalleryViewMode m) => switch (m) {
    GalleryViewMode.justified => Icons.view_agenda_outlined,
    GalleryViewMode.masonry => Icons.dashboard_outlined,
    GalleryViewMode.square => Icons.grid_on,
    GalleryViewMode.list => Icons.list,
  };

  Future<void> _openGallerySettings() async {
    final result = await showModalBottomSheet<GallerySettings>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _GallerySettingsSheet(initial: _gallerySettings),
    );
    if (result != null && mounted) {
      await result.save();
      setState(() => _gallerySettings = result);
    }
  }

  static const _kVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      if (_error is RelayException && (_error as RelayException).statusCode == 503) {
        return _WelcomeScreen(relay: widget.relay);
      }
      return _ErrorDisplay(error: _error!, onRetry: _load);
    }
    if (_files.isEmpty) return const Center(child: Text('No files yet. Upload something first.'));
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
            : const Text('Files'),
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
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => AccountsScreen(relay: widget.relay))),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                  child: Text('${_storageUsedGb!.toStringAsFixed(1)}/${_storageTotalGb!.toStringAsFixed(1)} GB',
                      style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                          color: scheme.onSecondaryContainer, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          Tooltip(
            message: 'App version — view on GitHub',
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse('https://github.com/dudenest/dudenest'),
                  mode: LaunchMode.externalApplication),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(_kVersion, style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                    color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
          if (!_selectionMode) ...[
            for (final mode in _ViewMode.values)
              IconButton(
                icon: Icon(_modeIcon(mode), color: _viewMode == mode ? scheme.primary : null),
                tooltip: _modeLabel(mode),
                onPressed: () => setState(() => _viewMode = mode),
              ),
            if (_viewMode == _ViewMode.gallery)
              IconButton(
                icon: const Icon(Icons.tune),
                tooltip: 'Gallery settings',
                onPressed: _openGallerySettings,
              ),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
          ],
        ],
      ),
      body: Stack(children: [
        Padding(
          padding: EdgeInsets.only(bottom: _selectionMode ? 56 : 0),
          child: _buildContent(),
        ),
        if (_selectionMode) Positioned(bottom: 0, left: 0, right: 0, child: _buildSelectionBar()),
      ]),
    );
  }
}

// ─── Error Display Widget (Duplicated from accounts_screen for consistency) ───

class _ErrorDisplay extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const _ErrorDisplay({required this.error, required this.onRetry});

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
          Text('Error: $msg', style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          if (code != null) ...[
            const SizedBox(height: 8),
            Text('Status Code: $code', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (body != null && body.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(body.length > 500 ? body.substring(0, 500) + '...' : body,
                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace'), maxLines: 10, overflow: TextOverflow.ellipsis),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
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
          Text('☁️', style: const TextStyle(fontSize: 64)),
          const SizedBox(height: 24),
          Text('Welcome to Dudenest!',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Text(
            'Your relay is ready.\nConnect a cloud account to start storing files securely.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('Add Cloud Account'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => AccountsScreen(relay: relay))),
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
  void initState() { super.initState(); _s = GallerySettings(
    viewMode: widget.initial.viewMode,
    justifiedRowHeight: widget.initial.justifiedRowHeight,
    masonryColumns: widget.initial.masonryColumns,
    groupByDate: widget.initial.groupByDate,
    showDateHeaders: widget.initial.showDateHeaders,
    showDateScrubbar: widget.initial.showDateScrubbar,
  ); }

  void _apply() => Navigator.pop(context, _s);

  GallerySettings _with({
    GalleryViewMode? viewMode,
    double? justifiedRowHeight,
    int? masonryColumns,
    bool? groupByDate,
    bool? showDateHeaders,
    bool? showDateScrubbar,
  }) => GallerySettings(
    viewMode: viewMode ?? _s.viewMode,
    justifiedRowHeight: justifiedRowHeight ?? _s.justifiedRowHeight,
    masonryColumns: masonryColumns ?? _s.masonryColumns,
    groupByDate: groupByDate ?? _s.groupByDate,
    showDateHeaders: showDateHeaders ?? _s.showDateHeaders,
    showDateScrubbar: showDateScrubbar ?? _s.showDateScrubbar,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final layouts = [
      (GalleryViewMode.justified, Icons.view_agenda_outlined, 'Justified'),
      (GalleryViewMode.masonry,   Icons.dashboard_outlined,   'Masonry'),
      (GalleryViewMode.square,    Icons.grid_on,              'Square'),
      (GalleryViewMode.list,      Icons.list,                 'List'),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(color: scheme.outlineVariant, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(children: [
              Text('Gallery settings', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              FilledButton(onPressed: _apply, child: const Text('Apply')),
            ]),
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Layout', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 10),
              Row(children: layouts.map((t) {
                final (mode, icon, label) = t;
                final selected = _s.viewMode == mode;
                return Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _s = _with(viewMode: mode)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? scheme.primary : Colors.transparent, width: 2),
                      ),
                      child: Column(children: [
                        Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                        const SizedBox(height: 4),
                        Text(label, style: TextStyle(
                          fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? scheme.primary : scheme.onSurfaceVariant)),
                      ]),
                    ),
                  ),
                ));
              }).toList()),
              const SizedBox(height: 16),
              if (_s.viewMode == GalleryViewMode.justified) ...[
                Text('Row height: ${_s.justifiedRowHeight.round()} px',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                Slider(
                  value: _s.justifiedRowHeight, min: 120, max: 320, divisions: 10,
                  label: '${_s.justifiedRowHeight.round()} px',
                  onChanged: (v) => setState(() => _s = _with(justifiedRowHeight: v)),
                ),
              ],
              if (_s.viewMode == GalleryViewMode.masonry) ...[
                Text('Columns: ${_s.masonryColumns}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
                Slider(
                  value: _s.masonryColumns.toDouble(), min: 2, max: 4, divisions: 2,
                  label: '${_s.masonryColumns}',
                  onChanged: (v) => setState(() => _s = _with(masonryColumns: v.round())),
                ),
              ],
              SwitchListTile.adaptive(
                dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Group by date'),
                value: _s.groupByDate,
                onChanged: (v) => setState(() => _s = _with(groupByDate: v)),
              ),
              SwitchListTile.adaptive(
                dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Show date headers'),
                value: _s.showDateHeaders,
                onChanged: (v) => setState(() => _s = _with(showDateHeaders: v)),
              ),
              SwitchListTile.adaptive(
                dense: true, contentPadding: EdgeInsets.zero,
                title: const Text('Show timeline scrubbar'),
                value: _s.showDateScrubbar,
                onChanged: (v) => setState(() => _s = _with(showDateScrubbar: v)),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        ]),
      ),
    );
  }
}
