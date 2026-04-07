import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/features/auth/login_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows app name and tagline', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    expect(find.text('Dudenest'), findsOneWidget);
    expect(find.text('Private encrypted cloud storage'), findsOneWidget);
  });

  testWidgets('shows cloud icon', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    expect(find.byIcon(Icons.cloud_done), findsOneWidget);
  });

  testWidgets('shows all 3 OAuth buttons', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with GitHub'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });

  testWidgets('all OAuth buttons are tappable', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    for (final label in ['Continue with Google', 'Continue with GitHub', 'Continue with Apple']) {
      final btn = tester.widget<OutlinedButton>(
        find.ancestor(of: find.text(label), matching: find.byType(OutlinedButton)));
      expect(btn.onPressed, isNotNull, reason: '$label button should be enabled');
    }
  });

  testWidgets('shows terms of service notice', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    expect(find.textContaining('Terms of Service'), findsOneWidget);
  });
}
