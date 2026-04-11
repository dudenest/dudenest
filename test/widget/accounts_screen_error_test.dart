import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/features/storage_accounts/accounts_screen.dart';

void main() {
  testWidgets('AccountsScreen displays RelayException details', (tester) async {
    final relay = RelayClient('http://relay.test', client: MockClient((req) async {
      return http.Response('<!DOCTYPE html><html><body>Error Page</body></html>', 401, headers: {'content-type': 'text/html'});
    }));

    await tester.pumpWidget(MaterialApp(home: AccountsScreen(relay: relay)));
    await tester.pump(); // Start loading
    await tester.pumpAndSettle(); // Finish loading with error and animations

    expect(find.textContaining('HTTP 401'), findsOneWidget);
    expect(find.textContaining('Status Code: 401'), findsOneWidget);
    expect(find.textContaining('Error Page'), findsOneWidget);
  });
}
