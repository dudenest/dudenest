import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/features/relay/relay_screen.dart';

RelayClient _relay(MockClientHandler h) =>
    RelayClient('http://relay.test', client: MockClient(h));

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows empty state when no files', (tester) async {
    final relay = _relay((req) async {
      if (req.url.path == '/files') return http.Response('{"files":[]}', 200, headers: {'content-type': 'application/json'});
      if (req.url.path == '/providers') return http.Response('{"providers":[]}', 200, headers: {'content-type': 'application/json'});
      return http.Response('error', 404);
    });
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pump(); await tester.pump();
    expect(find.textContaining('No files yet'), findsOneWidget);
  });

  testWidgets('shows file list on success', (tester) async {
    final relay = _relay((req) async {
      if (req.url.path == '/files') return http.Response(
        jsonEncode({'files': [{'file_id': 'f1', 'name': 'photo.jpg', 'size': 1024, 'hash': 'h1', 'created': '2026-04-06T12:00:00Z'}]}),
        200, headers: {'content-type': 'application/json'});
      if (req.url.path == '/providers') return http.Response('{"providers":[]}', 200, headers: {'content-type': 'application/json'});
      return http.Response('error', 404);
    });

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
      await tester.pump(); // Start loading
      await tester.pump(); // Finish loading
      
      // Default view is Grid, which doesn't show names. Switch to List.
      await tester.tap(find.byIcon(Icons.list));
      await tester.pump();

      expect(find.text('photo.jpg'), findsOneWidget);
    });
  });
}
