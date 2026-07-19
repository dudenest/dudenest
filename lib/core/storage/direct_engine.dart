import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/widgets.dart' show ImageProvider;
import 'package:http/http.dart' as http;
import 'drive_image_provider.dart';
import 'storage_engine.dart';

/// DirectEngine — [StorageEngine] rozmawiający BEZPOŚREDNIO z Google Drive REST v3,
/// bez relaya. To jest silnik trybu „Dudenest bez relay" (E3, 2026-07-17).
///
/// Zakres OAuth: `drive.file` (decyzja B, `RELAY-REMOVAL-FLUTTER-FIRST-PLAN.md §1.4b`) —
/// widzi TYLKO pliki utworzone/otwarte przez tę aplikację. Zero CASA, zero limitu 100 userów.
/// CORS Drive API z przeglądarki zweryfikowany empirycznie w E0 (łącznie z `alt=media` i uploadem).
///
/// Token dostępu jest WSTRZYKIWANY ([accessToken]) — engine nie wie, jak go zdobyć (to robi warstwa
/// OAuth w E3b). Dzięki temu jest w pełni testowalny bez realnego OAuth (fake token + fake http).
///
/// Mapuje odpowiedzi Drive na kontrakt pól, którego używają ekrany (zgodny z relayem):
/// `file_id, name, size, mime, created, taken_at, width, height, folder`.
class DirectEngine implements StorageEngine {
  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _uploadApi = 'https://www.googleapis.com/upload/drive/v3';
  // Pola żądane z Drive — muszą pokrywać kontrakt _mapFile.
  static const _fileFields =
      'id,name,size,mimeType,createdTime,thumbnailLink,imageMediaMetadata(width,height,time)';

  final Future<String> Function() _accessToken;
  final http.Client _http;

  /// Cache thumbnailLink per file_id (wypełniany przy listFiles) — pozwala [thumbnail]/[preview]
  /// pobrać miniaturę bez dodatkowego roundtripu po metadane.
  final Map<String, String> _thumbLinks = {};

  DirectEngine({
    required Future<String> Function() accessToken,
    http.Client? client,
  })  : _accessToken = accessToken,
        _http = client ?? http.Client();

  Future<Map<String, String>> _authHeaders() async =>
      {'Authorization': 'Bearer ${await _accessToken()}'};

  Map<String, dynamic> _decode(http.Response r, String ctx) {
    if (r.statusCode != 200) {
      throw StorageException('$ctx: HTTP ${r.statusCode}',
          statusCode: r.statusCode, body: r.body);
    }
    if (r.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Mapuje jeden obiekt Drive `files.*` na kontrakt pól używany przez ekrany.
  Map<String, dynamic> _mapFile(Map<String, dynamic> f) {
    final mime = (f['mimeType'] as String?) ?? '';
    final img = (f['imageMediaMetadata'] as Map<String, dynamic>?) ?? const {};
    final link = f['thumbnailLink'] as String?;
    final id = f['id'] as String? ?? '';
    if (link != null && id.isNotEmpty) _thumbLinks[id] = link;
    final isMedia = mime.startsWith('image/') || mime.startsWith('video/');
    return {
      'file_id': id,
      'name': f['name'],
      'size': int.tryParse('${f['size'] ?? 0}') ?? 0,
      'mime': mime,
      'created': f['createdTime'],
      'taken_at': img['time'] ?? f['createdTime'],
      'width': img['width'],
      'height': img['height'],
      'folder': isMedia ? 'photos' : 'files',
    };
  }

  // Zgadnij mime z rozszerzenia (Drive nadaje octet-stream, gdy nie podamy). Fallback bezpieczny.
  static const _mimeByExt = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png', 'gif': 'image/gif',
    'webp': 'image/webp', 'avif': 'image/avif', 'bmp': 'image/bmp', 'heic': 'image/heic',
    'heif': 'image/heif', 'svg': 'image/svg+xml',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska',
    'webm': 'video/webm', 'm4v': 'video/x-m4v', '3gp': 'video/3gpp',
    'pdf': 'application/pdf', 'txt': 'text/plain', 'zip': 'application/zip', 'json': 'application/json',
  };
  static String _mimeFor(String name) =>
      _mimeByExt[name.split('.').last.toLowerCase()] ?? 'application/octet-stream';

  @override
  Future<List<Map<String, dynamic>>> listFiles() async {
    final headers = await _authHeaders();
    final out = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.parse('$_api/files').replace(queryParameters: {
        'q': 'trashed=false',
        'spaces': 'drive',
        'pageSize': '1000',
        'fields': 'nextPageToken,files($_fileFields)',
        if (pageToken != null) 'pageToken': pageToken,
      });
      final data = _decode(await _http.get(uri, headers: headers), 'files.list');
      for (final f in (data['files'] as List? ?? const [])) {
        out.add(_mapFile(f as Map<String, dynamic>));
      }
      pageToken = data['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return out;
  }

  @override
  Future<Map<String, dynamic>> fileManifest({String? since}) async {
    // Drive nie ma manifestu z rewizjami — zwracamy pełną listę pod tym samym kształtem,
    // co relay (`{files, revision, unchanged}`), więc ekrany działają bez zmian.
    final files = await listFiles();
    return {'files': files, 'revision': '', 'unchanged': false};
  }

  @override
  Future<Map<String, dynamic>> uploadFile(String filename, Uint8List bytes,
      {String strategy = 'Replica'}) async {
    // Drive multipart upload (metadata + media w jednym żądaniu). mimeType z rozszerzenia — bez tego
    // Drive zapisuje octet-stream → zła klasyfikacja media/plik i brak miniatur.
    final mime = _mimeFor(filename);
    final boundary = 'dudenest${DateTime.now().microsecondsSinceEpoch}';
    final meta = jsonEncode({'name': filename, 'mimeType': mime});
    final body = <int>[];
    void add(String s) => body.addAll(utf8.encode(s));
    add('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n');
    add('$meta\r\n');
    add('--$boundary\r\nContent-Type: $mime\r\n\r\n');
    body.addAll(bytes);
    add('\r\n--$boundary--');
    final resp = await _http.post(
      Uri.parse('$_uploadApi/files?uploadType=multipart&fields=$_fileFields'),
      headers: {
        ...await _authHeaders(),
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    return _mapFile(_decode(resp, 'files.create'));
  }

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    final resp = await _http.get(
        Uri.parse('$_api/files/$fileId?alt=media'),
        headers: await _authHeaders());
    if (resp.statusCode != 200) {
      throw StorageException('files.get(media) $fileId: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode, body: resp.body);
    }
    return resp.bodyBytes;
  }

  @override
  Future<void> deleteFile(String fileId) async {
    final resp = await _http.delete(Uri.parse('$_api/files/$fileId'),
        headers: await _authHeaders());
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw StorageException('files.delete $fileId: HTTP ${resp.statusCode}',
          statusCode: resp.statusCode, body: resp.body);
    }
  }

  @override
  Future<Map<String, dynamic>> getFileMap(String fileId) async {
    // W modelu direct plik żyje w Drive użytkownika — pojedyncza „replika". Zwracamy minimalny
    // kształt zgodny z tym, czego oczekuje storage visualizer (lista lokalizacji).
    final data = _decode(
        await _http.get(
            Uri.parse('$_api/files/$fileId?fields=$_fileFields'),
            headers: await _authHeaders()),
        'files.get $fileId');
    final f = _mapFile(data);
    return {
      'file_id': fileId,
      'name': f['name'],
      'size': f['size'],
      'replicas': [
        {'provider': 'gdrive', 'location': fileId, 'strategy': 'Direct'}
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getMeta(String fileId) async {
    // Nasze metadane (ulubione/albumy/podpis) trzymamy w Drive `appProperties` (string→string).
    final data = _decode(
        await _http.get(
            Uri.parse('$_api/files/$fileId?fields=appProperties'),
            headers: await _authHeaders()),
        'files.get(meta) $fileId');
    return (data['appProperties'] as Map<String, dynamic>?) ?? {};
  }

  @override
  Future<Map<String, dynamic>> patchMeta(
      String fileId, Map<String, dynamic> patch) async {
    // Drive appProperties wymaga wartości String — serializujemy nie-stringi.
    final props = patch.map((k, v) =>
        MapEntry(k, v is String ? v : jsonEncode(v)));
    final resp = await _http.patch(
      Uri.parse('$_api/files/$fileId?fields=appProperties'),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'appProperties': props}),
    );
    final data = _decode(resp, 'files.update(meta) $fileId');
    return (data['appProperties'] as Map<String, dynamic>?) ?? {};
  }

  // ── ImageProvidery ────────────────────────────────────────────────────────
  // Miniatura/podgląd: Drive `thumbnailLink` (podpisany URL lh3.googleusercontent.com, CORS `*`
  // zweryfikowany w E0) z podmienionym rozmiarem `=sN`. Oryginał: alt=media z tokenem.

  @override
  ImageProvider thumbnail(String fileId) =>
      DriveImageProvider('$fileId#thumb220', () => _thumbBytes(fileId, 220));

  @override
  ImageProvider preview(String fileId) =>
      DriveImageProvider('$fileId#preview1024', () => _thumbBytes(fileId, 1024));

  @override
  ImageProvider original(String fileId) =>
      DriveImageProvider('$fileId#original', () => downloadFile(fileId));

  Future<Uint8List> _thumbBytes(String fileId, int size) async {
    try {
      var link = _thumbLinks[fileId];
      if (link == null) {
        final data = _decode(
            await _http.get(
                Uri.parse('$_api/files/$fileId?fields=thumbnailLink'),
                headers: await _authHeaders()),
            'files.get(thumb) $fileId');
        link = data['thumbnailLink'] as String?;
        if (link != null) _thumbLinks[fileId] = link;
      }
      if (link != null) {
        // thumbnailLink = podpisany URL lh3 z suffiksem rozmiaru `=sN`.
        final sized = link.replaceFirst(RegExp(r'=s\d+(-c)?$'), '=s$size');
        final resp = await _http.get(Uri.parse(sized));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) return resp.bodyBytes;
      }
    } catch (_) {
      // każdy błąd (metadata/lh3/CORS) → fallback niżej
    }
    // Fallback na oryginał (alt=media, sprawdzony): gdy brak thumbnailLink (świeży upload) LUB lh3
    // zawiodło (CORS/403/pusty). Gwarantuje render miniatury zamiast broken_image; cover-fit skaluje.
    return downloadFile(fileId);
  }
}
