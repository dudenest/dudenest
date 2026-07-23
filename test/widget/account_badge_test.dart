import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/features/files/account_badge.dart';

// Przypina etykietę konta na kafelku (MP1b, punkt UX z testu runtime): email z account_id, brak → nic.
void main() {
  test('labelFor: email z account_id (provider:email)', () {
    expect(AccountBadge.labelFor({'account_id': 'google:me@x.com'}), 'me@x.com');
    expect(AccountBadge.labelFor({'account_id': 'onedrive:a@b.co'}), 'a@b.co');
  });

  test('labelFor: brak/pusty account_id → null (ścieżka relay nic nie pokazuje)', () {
    expect(AccountBadge.labelFor({}), isNull);
    expect(AccountBadge.labelFor({'account_id': ''}), isNull);
    expect(AccountBadge.labelFor({'account_id': 'google:'}), isNull);
  });

  testWidgets('renderuje email gdy account_id jest', (t) async {
    await t.pumpWidget(const MaterialApp(
        home: Stack(children: [AccountBadge(file: {'account_id': 'google:me@x.com'})])));
    expect(find.text('me@x.com'), findsOneWidget);
  });

  testWidgets('nic nie renderuje bez account_id', (t) async {
    await t.pumpWidget(const MaterialApp(home: Stack(children: [AccountBadge(file: {})])));
    expect(find.byType(Text), findsNothing);
  });
}
