import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dudenest/core/storage/direct_account.dart';
import 'package:dudenest/features/storage_accounts/direct_accounts_screen.dart';

// Przypina UI multi-konta (MP1b): lista kont, „Add Google account" = redirect zgody, delete = DELETE.
// AccountsService wstrzyknięty z fake http + przechwyconym redirectem → zero sieci/przekierowania.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'auth_token': 'JWT123'}));

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('renderuje listę kont (email + provider)', (t) async {
    final client = MockClient((req) async {
      expect(req.headers['Authorization'], 'Bearer JWT123');
      return http.Response(
          jsonEncode([
            {'account_id': 'google:a@x.com', 'provider': 'google', 'email': 'a@x.com'},
            {'account_id': 'google:b@x.com', 'provider': 'google', 'email': 'b@x.com'},
          ]),
          200,
          headers: {'content-type': 'application/json'});
    });
    await t.pumpWidget(wrap(DirectAccountsScreen(service: AccountsService(client: client))));
    await t.pumpAndSettle();
    expect(find.text('a@x.com'), findsOneWidget);
    expect(find.text('b@x.com'), findsOneWidget);
    expect(find.text('Add Google account'), findsOneWidget);
  });

  testWidgets('pusta lista → empty state', (t) async {
    final client = MockClient((_) async => http.Response('[]', 200));
    await t.pumpWidget(wrap(DirectAccountsScreen(service: AccountsService(client: client))));
    await t.pumpAndSettle();
    expect(find.textContaining('No Google accounts connected'), findsOneWidget);
  });

  testWidgets('„Add Google account" → redirect zgody per provider (token + return_url)', (t) async {
    String? redirected;
    final client = MockClient((_) async => http.Response('[]', 200));
    final svc = AccountsService(
      client: client,
      redirect: (u) => redirected = u,
      origin: () => 'https://dudenest.com/photos?x=1',
    );
    await t.pumpWidget(wrap(DirectAccountsScreen(service: svc)));
    await t.pumpAndSettle();
    await t.tap(find.text('Add Google account'));
    await t.pumpAndSettle();
    expect(redirected, isNotNull);
    expect(redirected, contains('/auth/google/connect'));
    expect(redirected, contains('token=JWT123'));
    expect(redirected, contains('return_url=${Uri.encodeComponent('https://dudenest.com/photos')}')); // bez query
  });

  testWidgets('delete → confirm → DELETE + re-list (znika z listy)', (t) async {
    var deleted = false;
    final client = MockClient((req) async {
      if (req.method == 'DELETE') {
        expect(req.url.path, contains(Uri.encodeComponent('google:a@x.com')));
        deleted = true;
        return http.Response('', 204);
      }
      // GET accounts: przed delete 1 konto, po delete puste
      return http.Response(
          jsonEncode(deleted
              ? []
              : [
                  {'account_id': 'google:a@x.com', 'provider': 'google', 'email': 'a@x.com'}
                ]),
          200,
          headers: {'content-type': 'application/json'});
    });
    await t.pumpWidget(wrap(DirectAccountsScreen(service: AccountsService(client: client))));
    await t.pumpAndSettle();
    expect(find.text('a@x.com'), findsOneWidget);
    await t.tap(find.byIcon(Icons.delete_outline));
    await t.pumpAndSettle();
    expect(find.text('Remove account'), findsOneWidget); // dialog confirm
    await t.tap(find.widgetWithText(TextButton, 'Remove'));
    await t.pumpAndSettle();
    expect(deleted, isTrue);
    expect(find.text('a@x.com'), findsNothing);
    expect(find.textContaining('No Google accounts connected'), findsOneWidget);
  });
}
