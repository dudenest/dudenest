import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'gallery_settings.dart';

class TileManifestSnapshot {
  final String revision;
  final List<Map<String, dynamic>> files;
  final DateTime savedAt;
  const TileManifestSnapshot(
      {required this.revision, required this.files, required this.savedAt});
}

class TileManifestCache {
  static String _key(String relayUrl) =>
      'tile_manifest_${base64Url.encode(utf8.encode(relayUrl))}';

  static Future<TileManifestSnapshot?> load(
      String relayUrl, GallerySettings settings) async {
    if (!settings.localTileCacheEnabled) return null;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key(relayUrl));
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final files = List<Map<String, dynamic>>.from(data['files'] ?? []);
      return TileManifestSnapshot(
        revision: data['revision'] as String? ?? '',
        files: files,
        savedAt: DateTime.tryParse(data['saved_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      await p.remove(_key(relayUrl));
      return null;
    }
  }

  static Future<void> save(String relayUrl, String revision,
      List<Map<String, dynamic>> files, GallerySettings settings) async {
    if (!settings.localTileCacheEnabled) return;
    final p = await SharedPreferences.getInstance();
    final pruned = _prune(files, settings);
    final payload = <String, dynamic>{
      'revision': revision,
      'saved_at': DateTime.now().toUtc().toIso8601String(),
      'files': pruned,
    };
    var raw = jsonEncode(payload);
    while (raw.length > settings.localTileCacheMaxBytes &&
        payload['files'] is List &&
        (payload['files'] as List).length > 100) {
      final list = payload['files'] as List;
      list.removeRange((list.length * 0.9).floor(), list.length);
      raw = jsonEncode(payload);
    }
    if (raw.length <= settings.localTileCacheMaxBytes) {
      await p.setString(_key(relayUrl), raw);
    }
  }

  static List<Map<String, dynamic>> _prune(
      List<Map<String, dynamic>> files, GallerySettings settings) {
    final copy = List<Map<String, dynamic>>.from(files);
    copy.sort((a, b) => _dateOf(b).compareTo(_dateOf(a)));
    if (copy.length <= settings.localTileCacheMaxItems) return copy;
    return copy.sublist(0, settings.localTileCacheMaxItems);
  }

  static DateTime _dateOf(Map<String, dynamic> f) {
    final s = f['taken_at'] as String? ?? f['created'] as String? ?? '';
    return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
