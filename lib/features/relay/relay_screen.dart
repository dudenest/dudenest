import 'package:flutter/material.dart';
import '../../core/network/relay_client.dart';
import '../../core/auth/web_utils.dart';

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
  String? _error;
  _ViewMode _viewMode = _ViewMode.grid;

  static const _imageExts = {'jpg','jpeg','png','gif','webp','bmp','heic','heif','svg'};
  static const _videoExts = {'mp4','mov','avi','mkv','webm','m4v','3gp'};

  @override
  void initState() { super.initState(); _load(); }

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
    try {
      final bytes = await widget.relay.downloadFile(fileId);
      await downloadBytes(name, bytes);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded: $name')));
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
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
      if (mounted) setState(() { _error = e.toString(); });
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

  // ─── Thumbnail grid: tiles flush, 1px separator line, no names ─────────────
  Widget _buildGrid() => GridView.builder(
    padding: EdgeInsets.zero,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3,
      mainAxisSpacing: 1,
      crossAxisSpacing: 1,
    ),
    itemCount: _files.length,
    itemBuilder: (ctx, i) {
      final f = _files[i];
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? id;
      final isImg = _isImage(name);
      return GestureDetector(
        onTap: () {
          if (isImg) {
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
        },
        onLongPress: () => _confirmDelete(id, name),
        child: isImg
            ? Image.network('${widget.relay.baseUrl}/files/$id', fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xFF0D1117),
                    child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040)))),
                loadingBuilder: (_, child, p) => p == null ? child
                    : Container(color: const Color(0xFF0D1117),
                        child: const Center(child: CircularProgressIndicator(strokeWidth: 1))),
              )
            : Container(color: const Color(0xFF111827),
                child: Center(child: Icon(_fileIcon(name), size: 36, color: const Color(0xFF6080A0)))),
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
      return ListTile(
        leading: Icon(_fileIcon(name)),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: Text('${_formatSize(f['size'])} · ${id.length >= 8 ? '${id.substring(0, 8)}...' : id}'),
        trailing: _actionRow(id, name),
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
      return ListTile(
        leading: Icon(_fileIcon(name)),
        title: Text(name),
        subtitle: Text(_formatSize(f['size'])),
        trailing: _actionRow(id, name),
        isThreeLine: name.length > 35,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          Tooltip(message: 'App version',
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(_kVersion, style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                  color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
            ),
          ),
          for (final mode in _ViewMode.values)
            IconButton(
              icon: Icon(_modeIcon(mode), color: _viewMode == mode ? scheme.primary : null),
              tooltip: _modeLabel(mode),
              onPressed: () => setState(() => _viewMode = mode),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _files.isEmpty
                  ? const Center(child: Text('No files yet. Upload something first.'))
                  : switch (_viewMode) {
                      _ViewMode.grid => _buildGrid(),
                      _ViewMode.list => _buildList(),
                      _ViewMode.longNames => _buildLongNames(),
                    },
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
