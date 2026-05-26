import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/features/relay/relay_screen.dart';

RelayClient _relay(MockClientHandler h) =>
    RelayClient('http://relay.test', client: MockClient(h));

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows empty state when no files', (tester) async {
    final relay = _relay((req) async {
      if (req.url.path == '/files/manifest') {
        return http.Response(
            '{"revision":"r0","unchanged":false,"files":[]}', 200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/files')
        return http.Response('{"files":[]}', 200,
            headers: {'content-type': 'application/json'});
      if (req.url.path == '/providers')
        return http.Response('{"providers":[]}', 200,
            headers: {'content-type': 'application/json'});
      return http.Response('error', 404);
    });
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.textContaining('No files yet'), findsOneWidget);
  });

  testWidgets('shows file list on success', (tester) async {
    final relay = _relay((req) async {
      if (req.url.path == '/files/manifest') {
        return http.Response(
            jsonEncode({
              'revision': 'r1',
              'unchanged': false,
              'files': [
                {
                  'file_id': 'f1',
                  'name': 'photo.jpg',
                  'size': 1024,
                  'hash': 'h1',
                  'created': '2026-04-06T12:00:00Z'
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/files')
        return http.Response(
            jsonEncode({
              'files': [
                {
                  'file_id': 'f1',
                  'name': 'photo.jpg',
                  'size': 1024,
                  'hash': 'h1',
                  'created': '2026-04-06T12:00:00Z'
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'});
      if (req.url.path == '/providers')
        return http.Response('{"providers":[]}', 200,
            headers: {'content-type': 'application/json'});
      return http.Response('error', 404);
    });

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Default view is Grid, which doesn't show names. Switch to List.
      await tester.tap(find.byIcon(Icons.list));
      await tester.pump();

      expect(find.text('photo.jpg'), findsOneWidget);
    });
  });

  testWidgets('falls back to /files when old relay treats manifest as file ID',
      (tester) async {
    final relay = _relay((req) async {
      if (req.url.path == '/files/manifest') {
        return http.Response(
            '{"error":"download: load filemap: open /var/lib/dudenest/maps/manifest.json: no such file or directory"}',
            500,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/files') {
        return http.Response(
            jsonEncode({
              'files': [
                {
                  'file_id': 'f1',
                  'name': 'photo.jpg',
                  'size': 1024,
                  'hash': 'h1',
                  'created': '2026-04-06T12:00:00Z'
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/providers') {
        return http.Response('{"providers":[]}', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('error', 404);
    });

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.list));
      await tester.pump();
      expect(find.text('photo.jpg'), findsOneWidget);
    });
  });

  testWidgets('Files tab shows all cloud files as a list without thumbnails',
      (tester) async {
    final seen = <String>[];
    final relay = _relay((req) async {
      seen.add(req.url.path);
      if (req.url.path == '/files/manifest') {
        return http.Response(
            jsonEncode({
              'revision': 'r2',
              'unchanged': false,
              'files': [
                {
                  'file_id': 'p1',
                  'name': 'photo.jpg',
                  'size': 1024,
                  'folder': 'photos',
                  'created': '2026-04-06T12:00:00Z'
                },
                {
                  'file_id': 'd1',
                  'name': 'report.pdf',
                  'size': 2048,
                  'folder': 'files',
                  'created': '2026-04-06T12:00:00Z'
                }
              ]
            }),
            200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/providers') {
        return http.Response('{"providers":[]}', 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('error', 404);
    });
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay, folder: 'files')));
    await tester.pump();
    await tester.pump();
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.textContaining('JPG'), findsOneWidget);
    expect(find.textContaining('PDF'), findsOneWidget);
    expect(seen.where((p) => p.endsWith('/thumbnail')), isEmpty);
  });
}
