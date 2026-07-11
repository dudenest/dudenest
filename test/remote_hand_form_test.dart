import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dudenest/core/network/remote_hand.dart';
import 'package:dudenest/features/storage_accounts/remote_hand_form.dart';

class FakeTransport implements RhTransport {
  final _c = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<Map<String, dynamic>> get raw => _c.stream;
  @override
  void send(Map<String, dynamic> m) => sent.add(m);
  void emit(Map<String, dynamic> m) => _c.add(m);
}

void main() {
  testWidgets(
      'renders prompt fields, enables Continue once ready, submits input',
      (tester) async {
    final t = FakeTransport();
    final rh = RemoteHand(ws: t, sessionId: 's1');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RemoteHandForm(controller: rh))));

    // connecting → spinner, no fields yet
    expect(find.byType(TextField), findsNothing);

    // relay greets + asks for a (non-sensitive) login field
    t.emit({'type': 'rh_hello', 'session_id': 's1', 'relay_pubkey': 'PK'});
    t.emit({
      'type': 'rh_prompt',
      'session_id': 's1',
      'step': 'email',
      'title': 'Sign in',
      'fields': [
        {'name': 'login', 'label': 'Email or phone', 'kind': 'text'}
      ],
    });
    await tester.pump();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email or phone'),
        findsOneWidget); // label rendered
    expect(find.byType(TextField), findsOneWidget);

    // Invalid format → Continue stays disabled, no send
    await tester.enterText(find.byType(TextField), 'not-an-email');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(t.sent, isEmpty);

    // Valid → Continue enabled, sends
    await tester.enterText(find.byType(TextField), 'demo@example.com');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(t.sent, hasLength(1));
    expect(t.sent.single['type'], 'rh_input');
    expect(t.sent.single['values'], {'login': 'demo@example.com'});
  });

  testWidgets('shows success banner on rh_state success', (tester) async {
    final t = FakeTransport();
    final rh = RemoteHand(ws: t, sessionId: 's1');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RemoteHandForm(controller: rh))));
    t.emit({
      'type': 'rh_state',
      'session_id': 's1',
      'state': 'success',
      'message': 'demo@example.com'
    });
    await tester.pump();
    expect(find.text('Account connected'), findsOneWidget);
  });

  testWidgets('shows captcha image when prompt carries one', (tester) async {
    final t = FakeTransport();
    final rh = RemoteHand(ws: t, sessionId: 's1');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RemoteHandForm(controller: rh))));
    t.emit({'type': 'rh_hello', 'session_id': 's1', 'relay_pubkey': 'PK'});
    // 1x1 transparent PNG
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
    t.emit({
      'type': 'rh_prompt',
      'session_id': 's1',
      'step': 'captcha_static',
      'title': 'Solve',
      'image': png,
      'fields': [
        {'name': 'captcha', 'label': 'Type', 'kind': 'captcha_image'}
      ],
    });
    await tester.pump();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('blocks spaces in login and password fields', (tester) async {
    final t = FakeTransport();
    final rh = RemoteHand(ws: t, sessionId: 's1');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RemoteHandForm(controller: rh))));
    t.emit({'type': 'rh_hello', 'session_id': 's1', 'relay_pubkey': 'PK'});
    t.emit({
      'type': 'rh_prompt',
      'session_id': 's1',
      'step': 'credentials',
      'title': 'Sign in',
      'fields': [
        {'name': 'login', 'label': 'Email', 'kind': 'text'},
        {
          'name': 'password',
          'label': 'Password',
          'kind': 'password',
          'sensitive': true
        },
      ],
    });
    await tester.pump();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'demo @example.com');
    await tester.enterText(fields.at(1), 'pass word');
    await tester.pump();
    expect(find.text('demo@example.com'), findsOneWidget);
    expect(find.text('password'), findsOneWidget);
  });

  testWidgets('renders Google warning prompts in red', (tester) async {
    final t = FakeTransport();
    final rh = RemoteHand(ws: t, sessionId: 's1');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RemoteHandForm(controller: rh))));
    t.emit({'type': 'rh_hello', 'session_id': 's1', 'relay_pubkey': 'PK'});
    t.emit({
      'type': 'rh_prompt',
      'session_id': 's1',
      'step': 'email',
      'title': "Couldn't find that account — check the email",
      'level': 'warning',
      'fields': [
        {'name': 'login', 'label': 'Email', 'kind': 'text'},
      ],
    });
    await tester.pump();
    final text = tester.widget<Text>(
        find.text("Couldn't find that account — check the email"));
    expect(text.style?.color, Colors.red);
  });

  testWidgets('renders send-code confirmation without phone field', (tester) async {
    final t = FakeTransport();
    final rh = RemoteHand(ws: t, sessionId: 's1');
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RemoteHandForm(controller: rh))));
    t.emit({'type': 'rh_hello', 'session_id': 's1', 'relay_pubkey': 'PK'});
    t.emit({
      'type': 'rh_prompt',
      'session_id': 's1',
      'step': 'send_code',
      'title': 'Google will send a verification code to your phone',
      'fields': [],
    });
    await tester.pump();
    expect(find.text('Google will send a verification code to your phone'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(t.sent.single['step'], 'send_code');
    expect(t.sent.single['values'], <String, String>{});
  });
}
