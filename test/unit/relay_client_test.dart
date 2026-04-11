import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dudenest/core/network/relay_client.dart';

RelayClient _client(MockClientHandler handler) =>
    RelayClient('http://relay.test', client: MockClient(handler));

void main() {
  group('RelayClient.getProviders', () {
    test('parses provider list', () async {
      final c = _client((req) async => http.Response(
            jsonEncode({'providers': [{'id': 'gdrive_1', 'email': 'a@b.com', 'quota_total_gb': 15.0, 'quota_used_gb': 0.5, 'available': true}]}),
            200, headers: {'content-type': 'application/json'}));
      final providers = await c.getProviders();
      expect(providers.length, 1);
      expect(providers[0]['email'], 'a@b.com');
      expect(providers[0]['quota_total_gb'], 15.0);
    });

    test('throws RelayException on 401', () async {
      final c = _client((req) async => http.Response('unauthorized', 401));
      expect(() => c.getProviders(), throwsA(isA<RelayException>().having((e) => e.statusCode, 'statusCode', 401)));
    });

    test('throws RelayException on HTML response', () async {
      final c = _client((req) async => http.Response('<!DOCTYPE html><html>...</html>', 200, headers: {'content-type': 'text/html'}));
      expect(() => c.getProviders(), throwsA(isA<RelayException>().having((e) => e.message, 'message', contains('Expected JSON'))));
    });

    test('returns empty list when providers key absent', () async {
      final c = _client((req) async => http.Response(jsonEncode({}), 200,
          headers: {'content-type': 'application/json'}));
      final providers = await c.getProviders();
      expect(providers, isEmpty);
    });
  });

  group('RelayClient.listFiles', () {
    test('parses file list', () async {
      final c = _client((req) async => http.Response(
            jsonEncode({'files': [
              {'file_id': 'abc123', 'name': 'photo.jpg', 'size': 2048, 'hash': 'deadbeef', 'created': '2026-04-06T12:00:00Z'}
            ]}),
            200, headers: {'content-type': 'application/json'}));
      final files = await c.listFiles();
      expect(files.length, 1);
      expect(files[0]['file_id'], 'abc123');
      expect(files[0]['name'], 'photo.jpg');
    });

    test('throws RelayException on 500', () async {
      final c = _client((req) async => http.Response('server error', 500));
      expect(() => c.listFiles(), throwsA(isA<RelayException>().having((e) => e.statusCode, 'statusCode', 500)));
    });
  });

  group('RelayClient.downloadFile', () {
    test('returns bytes on success', () async {
      final expected = Uint8List.fromList([1, 2, 3, 4]);
      final c = _client((req) async => http.Response.bytes(expected, 200));
      final bytes = await c.downloadFile('abc123');
      expect(bytes, equals(expected));
    });

    test('throws RelayException on 404', () async {
      final c = _client((req) async => http.Response('not found', 404));
      expect(() => c.downloadFile('missing'), throwsA(isA<RelayException>().having((e) => e.statusCode, 'statusCode', 404)));
    });
  });

  group('RelayClient.deleteFile', () {
    test('completes on 200', () async {
      final c = _client((req) async => http.Response(
          jsonEncode({'status': 'deleted', 'file_id': 'abc123'}), 200,
          headers: {'content-type': 'application/json'}));
      await expectLater(c.deleteFile('abc123'), completes);
    });

    test('throws RelayException on non-200', () async {
      final c = _client((req) async => http.Response('error', 500));
      expect(() => c.deleteFile('abc123'), throwsA(isA<RelayException>().having((e) => e.statusCode, 'statusCode', 500)));
    });
  });
}
