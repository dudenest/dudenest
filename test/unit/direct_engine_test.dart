import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dudenest/core/storage/direct_engine.dart';
import 'package:dudenest/core/storage/drive_image_provider.dart';
import 'package:dudenest/core/storage/storage_engine.dart';

// Przypina kontrakt E3: DirectEngine mapuje odpowiedzi Google Drive REST na kształt pól,
// którego używają ekrany (zgodny z relayem), wysyła token OAuth i paginuje.
// Token i http są WSTRZYKIWANE → zero realnego OAuth/sieci w teście.
void main() {
  DirectEngine engineReturning(http.Client client) =>
      DirectEngine(accessToken: () async => 'TESTTOKEN', client: client);

  test('DirectEngine implements StorageEngine', () {
    final StorageEngine e = engineReturning(MockClient((_) async => http.Response('{}', 200)));
    expect(e, isA<DirectEngine>());
  });

  test('listFiles: mapuje pola Drive + klasyfikuje photos/files + wysyła Bearer', () async {
    String? seenAuth;
    final client = MockClient((req) async {
      seenAuth = req.headers['Authorization'];
      return http.Response(jsonEncode({
        'files': [
          {
            'id': 'f1', 'name': 'photo.jpg', 'size': '12345',
            'mimeType': 'image/jpeg', 'createdTime': '2026-01-01T00:00:00Z',
            'thumbnailLink': 'https://lh3.googleusercontent.com/abc=s220',
            'imageMediaMetadata': {'width': 4000, 'height': 3000, 'time': '2025:12:25 10:00:00'},
          },
          {
            'id': 'f2', 'name': 'doc.pdf', 'size': '999',
            'mimeType': 'application/pdf', 'createdTime': '2026-02-02T00:00:00Z',
          },
        ],
      }), 200, headers: {'content-type': 'application/json'});
    });

    final files = await engineReturning(client).listFiles();
    expect(seenAuth, 'Bearer TESTTOKEN');
    expect(files.length, 2);

    final a = files[0];
    expect(a['file_id'], 'f1');
    expect(a['name'], 'photo.jpg');
    expect(a['size'], 12345); // String w Drive → int w kontrakcie
    expect(a['size'], isA<int>());
    expect(a['folder'], 'photos');
    expect(a['taken_at'], '2025:12:25 10:00:00'); // EXIF time ma priorytet nad createdTime
    expect(a['width'], 4000);

    final b = files[1];
    expect(b['folder'], 'files'); // pdf → files
    expect(b['taken_at'], '2026-02-02T00:00:00Z'); // brak EXIF → fallback createdTime
  });

  test('uploadFile: ustawia mimeType z rozszerzenia (nie octet-stream)', () async {
    late String seenBody;
    final client = MockClient((req) async {
      seenBody = req.body;
      return http.Response(
          jsonEncode({'id': 'u1', 'name': 'doc.pdf', 'mimeType': 'application/pdf', 'createdTime': 't'}),
          200, headers: {'content-type': 'application/json'});
    });
    final res = await engineReturning(client).uploadFile('doc.pdf', Uint8List.fromList([1, 2, 3]));
    expect(seenBody.contains('"mimeType":"application/pdf"'), isTrue); // metadata
    expect(seenBody.contains('Content-Type: application/pdf'), isTrue); // część media
    expect(seenBody.contains('application/octet-stream'), isFalse); // znany typ → NIE octet-stream
    expect(res['file_id'], 'u1');
  });

  test('listFiles: paginacja po nextPageToken', () async {
    var call = 0;
    final client = MockClient((req) async {
      call++;
      if (call == 1) {
        return http.Response(jsonEncode({
          'nextPageToken': 'PAGE2',
          'files': [{'id': 'a', 'name': 'a', 'size': '1', 'mimeType': 'image/png', 'createdTime': 't'}],
        }), 200, headers: {'content-type': 'application/json'});
      }
      // strona 2 — żądanie MUSI nieść pageToken
      expect(req.url.queryParameters['pageToken'], 'PAGE2');
      return http.Response(jsonEncode({
        'files': [{'id': 'b', 'name': 'b', 'size': '2', 'mimeType': 'image/png', 'createdTime': 't'}],
      }), 200, headers: {'content-type': 'application/json'});
    });

    final files = await engineReturning(client).listFiles();
    expect(call, 2);
    expect(files.map((f) => f['file_id']), ['a', 'b']);
  });

  test('downloadFile: alt=media + Bearer, zwraca bajty', () async {
    final client = MockClient((req) async {
      expect(req.url.path, contains('/files/xyz'));
      expect(req.url.queryParameters['alt'], 'media');
      expect(req.headers['Authorization'], 'Bearer TESTTOKEN');
      return http.Response.bytes(Uint8List.fromList([1, 2, 3, 4]), 200);
    });
    final bytes = await engineReturning(client).downloadFile('xyz');
    expect(bytes, [1, 2, 3, 4]);
  });

  test('deleteFile: DELETE (204 OK)', () async {
    var method = '';
    final client = MockClient((req) async {
      method = req.method;
      return http.Response('', 204);
    });
    await engineReturning(client).deleteFile('gone');
    expect(method, 'DELETE');
  });

  test('patchMeta: serializuje nie-stringi do appProperties', () async {
    Map<String, dynamic>? sentProps;
    final client = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      sentProps = body['appProperties'] as Map<String, dynamic>;
      return http.Response(jsonEncode({'appProperties': sentProps}), 200,
          headers: {'content-type': 'application/json'});
    });
    await engineReturning(client).patchMeta('f', {'caption': 'hi', 'favorite': true});
    expect(sentProps!['caption'], 'hi'); // String zostaje
    expect(sentProps!['favorite'], 'true'); // bool → String (wymóg Drive)
  });

  test('błąd HTTP → StorageException', () async {
    final client = MockClient((_) async => http.Response('nope', 403));
    expect(() => engineReturning(client).listFiles(), throwsA(isA<StorageException>()));
  });

  test('thumbnail/preview/original: różne cacheKey (nie kolidują w imageCache)', () {
    final e = engineReturning(MockClient((_) async => http.Response('{}', 200)));
    final t = e.thumbnail('f1') as DriveImageProvider;
    final p = e.preview('f1') as DriveImageProvider;
    final o = e.original('f1') as DriveImageProvider;
    expect({t.cacheKey, p.cacheKey, o.cacheKey}.length, 3);
    expect(t.cacheKey, contains('f1'));
  });

  test('thumbnail bez thumbnailLink → fallback na oryginał (alt=media)', () async {
    // Świeżo wgrany plik: Drive nie ma jeszcze thumbnailLink → thumbnail MUSI pokazać oryginał,
    // nie broken_image. Metadata zwraca brak linku, alt=media zwraca bajty.
    var mediaHit = false;
    final client = MockClient((req) async {
      if (req.url.queryParameters['alt'] == 'media') {
        mediaHit = true;
        return http.Response.bytes(Uint8List.fromList([9, 9, 9]), 200);
      }
      return http.Response(jsonEncode({}), 200, headers: {'content-type': 'application/json'});
    });
    final tp = engineReturning(client).thumbnail('f1') as DriveImageProvider;
    final bytes = await tp.loader();
    expect(mediaHit, true); // poszło po oryginał
    expect(bytes, [9, 9, 9]); // fallback zwrócił bajty, nie pusto
  });

  test('thumbnail: lh3 zawodzi (403) → fallback na oryginał', () async {
    // thumbnailLink ISTNIEJE, ale pobranie z lh3 zwraca 403 (np. wymaga cookies) → i tak oryginał.
    var mediaHit = false;
    final client = MockClient((req) async {
      final host = req.url.host;
      if (host.contains('googleusercontent.com')) return http.Response('forbidden', 403);
      if (req.url.queryParameters['alt'] == 'media') {
        mediaHit = true;
        return http.Response.bytes(Uint8List.fromList([7, 7]), 200);
      }
      // metadata → zwraca link do lh3
      return http.Response(jsonEncode({'thumbnailLink': 'https://lh3.googleusercontent.com/x=s220'}),
          200, headers: {'content-type': 'application/json'});
    });
    final bytes = await (engineReturning(client).thumbnail('f9') as DriveImageProvider).loader();
    expect(mediaHit, true); // lh3 403 → spadło na oryginał
    expect(bytes, [7, 7]);
  });
}
