import 'package:flutter/material.dart';
import '../../core/network/relay_client.dart';
import '../../core/auth/web_utils.dart';

enum _ViewMode { list, longNames, grid }

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
  _ViewMode _viewMode = _ViewMode.list;

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
      await downloadBytes(name, bytes); // web: blob download; native: save to temp
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pobrano: $name')));
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); });
    }
  }

  Future<void> _confirmDelete(String fileId, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń plik'),
        content: Text('Czy na pewno usunąć "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.relay.deleteFile(fileId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Usunięto: $name'),
          backgroundColor: Colors.green,
        ));
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
    IconButton(icon: const Icon(Icons.download), tooltip: 'Pobierz', onPressed: () => _download(id, name)),
    IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: 'Usuń', onPressed: () => _confirmDelete(id, name)),
  ]);

  // ─── List view (names truncated with ellipsis) ──────────────────────────────
  Widget _buildList() => ListView.builder(
    itemCount: _files.length,
    itemBuilder: (ctx, i) {
      final f = _files[i];
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? id;
      return ListTile(
        leading: Icon(_fileIcon(name)),
        title: Text(name, overflow: TextOverflow.ellipsis),
        subtitle: Text('${_formatSize(f['size'])} · ${id.length >= 8 ? '${id.substring(0, 8)}…' : id}'),
        trailing: _actionRow(id, name),
      );
    },
  );

  // ─── Long names view (full filename, wrapping) ──────────────────────────────
  Widget _buildLongNames() => ListView.builder(
    itemCount: _files.length,
    itemBuilder: (ctx, i) {
      final f = _files[i];
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? id;
      return ListTile(
        leading: Icon(_fileIcon(name)),
        title: Text(name), // no overflow — wraps naturally
        subtitle: Text(_formatSize(f['size'])),
        trailing: _actionRow(id, name),
        isThreeLine: name.length > 35,
      );
    },
  );

  // ─── Grid / thumbnail view ──────────────────────────────────────────────────
  // Images: fetched from relay GET /files/{id}
  // Videos & other: icon placeholder
  // Tap = download; long-press = delete confirmation
  // TODO relay: add GET /files/{id}/thumbnail for efficient small previews
  Widget _buildGrid() => GridView.builder(
    padding: const EdgeInsets.all(8),
    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 160,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemCount: _files.length,
    itemBuilder: (ctx, i) {
      final f = _files[i];
      final id = f['file_id'] as String? ?? '';
      final name = f['name'] as String? ?? id;
      final isImg = _isImage(name);
      return GestureDetector(
        onTap: () => _download(id, name),
        onLongPress: () => _confirmDelete(id, name),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            Expanded(
              child: isImg
                  ? Image.network(
                      '${widget.relay.baseUrl}/files/$id',
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 40)),
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : Center(child: Icon(_fileIcon(name), size: 48, color: Colors.grey)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(name, style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis, maxLines: 2, textAlign: TextAlign.center),
            ),
          ]),
        ),
      );
    },
  );

  IconData _modeIcon(_ViewMode m) => switch (m) {
    _ViewMode.list => Icons.list,
    _ViewMode.longNames => Icons.text_snippet,
    _ViewMode.grid => Icons.grid_view,
  };

  String _modeLabel(_ViewMode m) => switch (m) {
    _ViewMode.list => 'Lista',
    _ViewMode.longNames => 'Długie nazwy',
    _ViewMode.grid => 'Miniatury',
  };

  static const _kVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          // Version badge — top-right corner, always visible
          Tooltip(
            message: 'Wersja aplikacji',
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_kVersion,
                style: TextStyle(fontSize: 10, fontFamily: 'monospace',
                    color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
            ),
          ),
          for (final mode in _ViewMode.values)
            IconButton(
              icon: Icon(_modeIcon(mode), color: _viewMode == mode ? scheme.primary : null),
              tooltip: _modeLabel(mode),
              onPressed: () => setState(() => _viewMode = mode),
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load, tooltip: 'Odśwież'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Error: $_error', style: const TextStyle(color: Colors.red)))
              : _files.isEmpty
                  ? const Center(child: Text('No files yet. Upload something first.'))
                  : switch (_viewMode) {
                      _ViewMode.list => _buildList(),
                      _ViewMode.longNames => _buildLongNames(),
                      _ViewMode.grid => _buildGrid(),
                    },
    );
  }
}
