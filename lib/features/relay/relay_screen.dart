import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/relay_client.dart';
import '../../core/auth/web_utils.dart';
import '../storage_accounts/accounts_screen.dart';

enum _ViewMode { grid, list, longNames }

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
  _ViewMode _viewMode = _ViewMode.grid;
  double? _storageUsedGb;
  double? _storageTotalGb;
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

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

  // Opens file: fullscreen for images, download for others
  void _openFile(BuildContext ctx, String id, String name) {
    if (_isImage(name)) {
      Navigator.push(ctx, MaterialPageRoute(
        builder: (_) => _FullscreenViewer(
          url: '${widget.relay.baseUrl}/files/$id',
          name: name, relay: widget.relay, fileId: id,
          onDelete: () { Navigator.pop(ctx); _load(); },
        ),
      ));
    } else {
      _download(id, name);
    }
  }

  // ─── Thumbnail grid: tiles flush, 1px separator line, no names ─────────────
  Widget _buildGrid() => GridView.builder(
    padding: EdgeInsets.zero,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3, mainAxisSpacing: 1, crossAxisSpacing: 1,
    ),
    itemCount: _files.length,
    itemBuilder: (ctx, i) {
      final f = _files[i];
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? id;
      final isImg = _isImage(name);
      final isSelected = _selected.contains(id);
      return GestureDetector(
        onTap: () => _selectionMode ? _toggleSelect(id) : _openFile(ctx, id, name),
        onLongPress: () => _toggleSelect(id),  // enter selection mode
        child: Stack(fit: StackFit.expand, children: [
          // Content
          isImg
              ? Image.network('${widget.relay.baseUrl}/files/$id/thumbnail', fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0D1117),
                      child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040)))),
                  loadingBuilder: (_, child, p) => p == null ? child
                      : Container(color: const Color(0xFF0D1117),
                          child: const Center(child: CircularProgressIndicator(strokeWidth: 1))),
                )
              : Container(color: const Color(0xFF111827),
                  child: Center(child: Icon(_fileIcon(name), size: 36, color: const Color(0xFF6080A0)))),
          // Selection overlay (only in selection mode)
          if (_selectionMode) AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            color: isSelected ? Colors.black54 : Colors.black26,
            child: isSelected
                ? const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 36))
                : Padding(
                    padding: const EdgeInsets.all(5),
                    child: Align(alignment: Alignment.topRight,
                      child: Container(width: 22, height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white70, width: 2),
                        ),
                      ),
                    ),
                  ),
          ),
        ]),
      );
    },
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
    _ViewMode.grid => Icons.grid_view,
    _ViewMode.list => Icons.list,
    _ViewMode.longNames => Icons.text_snippet,
  };
  String _modeLabel(_ViewMode m) => switch (m) {
    _ViewMode.grid => 'Thumbnails',
    _ViewMode.list => 'List',
    _ViewMode.longNames => 'Long names',
  };

  static const _kVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  Widget _buildContent() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _ErrorDisplay(error: _error!, onRetry: _load);
    if (_files.isEmpty) return const Center(child: Text('No files yet. Upload something first.'));
    return switch (_viewMode) {
      _ViewMode.grid => _buildGrid(),
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

// ─── Fullscreen image viewer ─────────────────────────────────────────────────
class _FullscreenViewer extends StatelessWidget {
  final String url;
  final String name;
  final RelayClient relay;
  final String fileId;
  final VoidCallback onDelete;
  const _FullscreenViewer({required this.url, required this.name, required this.relay,
      required this.fileId, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: InteractiveViewer(
            minScale: 0.5, maxScale: 8.0,
            child: Image.network(url, fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
              loadingBuilder: (_, child, p) => p == null ? child
                  : const Center(child: CircularProgressIndicator(color: Colors.white54)),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  onPressed: () => Navigator.pop(context)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white54),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete file'), content: Text('Delete "$name"?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
                      ],
                    ),
                  );
                  if (ok == true) { await relay.deleteFile(fileId); onDelete(); }
                },
              ),
            ]),
          ),
        ),
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
