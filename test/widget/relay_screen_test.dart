import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/features/relay/relay_screen.dart';

RelayClient _relay(MockClientHandler h) =>
    RelayClient('http://relay.test', client: MockClient(h));

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows empty state when no files', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'files': []}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.text('No files yet. Upload something first.'), findsOneWidget);
  });

  testWidgets('shows file list on success', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'files': [
          {'file_id': 'abcdef1234567890', 'name': 'photo.jpg', 'size': 2097152, 'hash': 'abc', 'created': '2026-04-06T12:00:00Z'}
        ]}), 200, headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.text('photo.jpg'), findsOneWidget);
    expect(find.byIcon(Icons.download), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
  });

  testWidgets('shows error on relay failure', (tester) async {
    final relay = _relay((_) async => http.Response('error', 500));
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Error:'), findsOneWidget);
  });

  testWidgets('delete button shows confirmation dialog', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'files': [
          {'file_id': 'abcdef1234567890', 'name': 'photo.jpg', 'size': 1024}
        ]}), 200, headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Usuń plik'), findsOneWidget);
    expect(find.text('Anuluj'), findsOneWidget);
    expect(find.text('Usuń'), findsOneWidget);
  });

  testWidgets('cancel delete does not remove file', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'files': [
          {'file_id': 'abcdef1234567890', 'name': 'photo.jpg', 'size': 1024}
        ]}), 200, headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anuluj'));
    await tester.pumpAndSettle();
    expect(find.text('photo.jpg'), findsOneWidget); // file still visible
  });

  testWidgets('view mode icons are displayed', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'files': []}), 200, headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(RelayScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.list), findsOneWidget);
    expect(find.byIcon(Icons.text_snippet), findsOneWidget);
    expect(find.byIcon(Icons.grid_view), findsOneWidget);
  });
}
