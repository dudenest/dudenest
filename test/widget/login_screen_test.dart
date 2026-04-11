import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/features/auth/login_screen.dart';

void main() {
  testWidgets('shows all 3 OAuth buttons', (tester) async {
    // Set a large enough surface size to avoid overflows in tests
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with GitHub'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
  });

  testWidgets('all OAuth buttons are tappable', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.text('Continue with Google'), warnIfMissed: false);
    await tester.tap(find.text('Continue with GitHub'), warnIfMissed: false);
    await tester.tap(find.text('Continue with Apple'), warnIfMissed: false);
    await tester.pump();
  });

  testWidgets('shows terms of service notice', (tester) async {
    tester.view.physicalSize = const Size(1200, 1200);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.textContaining('agree to the Terms of Service'), findsOneWidget);
  });
}
