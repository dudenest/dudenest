import 'package:flutter/material.dart';
import '../../core/oauth/google_drive_auth.dart';
import '../../core/storage/direct_engine.dart';
import '../../core/storage/storage_engine.dart';

/// Walking skeleton trybu „Dudenest bez relay" (E3b-2, 2026-07-17).
///
/// Pełny łańcuch end-to-end BEZ relaya: OAuth `drive.file` (Google Identity Services) →
/// [DirectEngine] (Drive REST) → render miniatur. To pierwszy ekran, na którym `dudenest.com`
/// czyta pliki bezpośrednio z Google Drive. Samodzielny (nie zależy od ekranów relay-owych) —
/// docelowo jego logika wejdzie do głównej galerii za feature-flagą [EngineMode.direct].
class DirectGalleryScreen extends StatefulWidget {
  const DirectGalleryScreen({super.key});

  @override
  State<DirectGalleryScreen> createState() => _DirectGalleryScreenState();
}

class _DirectGalleryScreenState extends State<DirectGalleryScreen> {
  StorageEngine? _engine;
  List<Map<String, dynamic>>? _files;
  String? _error;
  bool _loading = false;

  Future<void> _connect() async {
    setState(() { _loading = true; _error = null; });
    try {
      final engine = DirectEngine(accessToken: getDriveAccessToken); // token → Drive, bez relaya
      final files = await engine.listFiles();
      if (!mounted) return;
      setState(() { _engine = engine; _files = files; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Google Drive (direct, bez relaya)')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 40),
            const SizedBox(height: 12),
            Text('Błąd: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _connect, child: const Text('Spróbuj ponownie')),
          ]),
        ),
      );
    }
    final files = _files;
    if (files == null) {
      return Center(
        child: ElevatedButton.icon(
          onPressed: _connect,
          icon: const Icon(Icons.cloud),
          label: const Text('Connect Google Drive'),
        ),
      );
    }
    if (files.isEmpty) {
      return const Center(child: Text('Brak plików utworzonych przez tę aplikację (drive.file).'));
    }
    final engine = _engine!;
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
      itemCount: files.length,
      itemBuilder: (_, i) {
        final id = files[i]['file_id'] as String? ?? '';
        final name = files[i]['name'] as String? ?? '';
        final isMedia = (files[i]['folder'] as String?) == 'photos';
        if (!isMedia || id.isEmpty) {
          return Container(
            color: const Color(0xFF111827),
            child: Center(
              child: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
            ),
          );
        }
        return Image(
          image: engine.thumbnail(id),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFF0D1117),
            child: const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040))),
          ),
        );
      },
    );
  }
}
