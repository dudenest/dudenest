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
    final completer = Completer<http.Response>();
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
    expect(find.text('No storage accounts'), findsOneWidget);
    expect(find.text('Add Account'), findsWidgets);
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

  testWidgets('FAB opens Add Account sheet', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': []}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    expect(find.text('Add Storage Account'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('MEGA.nz'), findsOneWidget);
  });

  testWidgets('Add Account sheet shows method selection after provider pick', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': []}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Login Method'), findsOneWidget);
    expect(find.text('Login via your browser'), findsOneWidget);
    expect(find.text('Relay browser (automated)'), findsOneWidget);
  });

  testWidgets('Method E credentials form shows email/password/phone fields', (tester) async {
    // Method E (WebView auto-fill) only on non-web platforms — skip on web CI
    // In test environment kIsWeb=false so the option should appear
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': []}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Auto-fill in app'), findsOneWidget); // Method E button
    await tester.tap(find.text('Auto-fill in app'));
    await tester.pumpAndSettle();
    expect(find.text('Enter Credentials'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Phone (for 2FA, optional)'), findsOneWidget);
  });

  testWidgets('Method E Continue button disabled without email', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': []}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Google Drive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Auto-fill in app'));
    await tester.pumpAndSettle();
    final continueBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue').last
    );
    expect(continueBtn.onPressed, isNull); // disabled — email empty
  });
}
