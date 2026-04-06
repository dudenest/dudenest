import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/features/storage_accounts/accounts_screen.dart';

RelayClient _relay(MockClientHandler h) =>
    RelayClient('http://relay.test', client: MockClient(h));

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows loading indicator initially', (tester) async {
    final completer = Completer<http.Response>(); // never completes — stays loading
    final relay = RelayClient('http://relay.test',
        client: MockClient((_) => completer.future));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(http.Response('{"providers":[]}', 200,
        headers: {'content-type': 'application/json'}));
  });

  testWidgets('shows empty state when no providers', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': []}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.text('No accounts. Add a Google Drive account on the relay.'), findsOneWidget);
  });

  testWidgets('shows provider list on success', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': [
          {'id': 'gdrive_1', 'email': 'user@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.2, 'available': true, 'type': 'gdrive'}
        ]}), 200, headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.text('user@gmail.com'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('shows error on relay failure', (tester) async {
    final relay = _relay((_) async => http.Response('error', 503));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Error:'), findsOneWidget);
  });
}
