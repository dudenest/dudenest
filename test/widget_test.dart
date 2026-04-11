import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/main.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DudenestApp());
    // Since it starts at LoginScreen (AuthService token is null in tests),
    // we should see the login buttons.
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with GitHub'), findsOneWidget);
  });
}
