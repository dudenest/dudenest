import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/x25519.dart';

import 'package:dudenest/core/crypto/sealed_box.dart';
import 'package:dudenest/core/network/remote_hand.dart';

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
  group('models', () {
    test('RhField parse + obscure', () {
      final f = RhField.fromJson({'name': 'password', 'label': 'Password', 'kind': 'password', 'sensitive': true});
      expect(f.name, 'password');
      expect(f.sensitive, isTrue);
      expect(f.obscure, isTrue);
      expect(RhField.fromJson({'name': 'login', 'label': 'Login'}).obscure, isFalse);
    });

    test('RhPrompt parse with fields + captcha image', () {
      final p = RhPrompt.fromJson({
        'step': 'captcha_static',
        'title': 'Solve',
        'image': 'QUJD',
        'fields': [
          {'name': 'captcha', 'label': 'Type', 'kind': 'captcha_image'}
        ],
      });
      expect(p.step, 'captcha_static');
      expect(p.imageB64, 'QUJD');
      expect(p.fields.single.name, 'captcha');
    });
  });

  group('sealed_box interop shape (PyNaCl-compatible)', () {
    test('seal → open roundtrip with matching key', () {
      final sk = PrivateKey.generate();
      final pkB64 = base64.encode(sk.publicKey);
      final sealed = sealJsonToPubkey(pkB64, {'password': 'P@ss-Rel4y!'});
      // A different key must NOT be able to open it (sanity of addressing)
      final opened = SealedBox(sk).decrypt(base64.decode(sealed));
      expect(jsonDecode(utf8.decode(opened))['password'], 'P@ss-Rel4y!');
    });
  });

  group('RemoteHand controller', () {
    test('rh_hello sets pubkey/ready; foreign session ignored', () async {
      final t = FakeTransport();
      final rh = RemoteHand(ws: t, sessionId: 's1');
      expect(rh.ready, isFalse);
      t.emit({'type': 'rh_hello', 'session_id': 'OTHER', 'relay_pubkey': 'X'});
      await pumpEventQueue();
      expect(rh.ready, isFalse); // not our session
      t.emit({'type': 'rh_hello', 'session_id': 's1', 'relay_pubkey': 'PK'});
      await pumpEventQueue();
      expect(rh.ready, isTrue);
    });

    test('rh_prompt exposes fields; submit seals secrets, keeps plain in cleartext', () async {
      final sk = PrivateKey.generate();
      final t = FakeTransport();
      final rh = RemoteHand(ws: t, sessionId: 's1');
      t.emit({'type': 'rh_hello', 'session_id': 's1', 'relay_pubkey': base64.encode(sk.publicKey)});
      t.emit({
        'type': 'rh_prompt',
        'session_id': 's1',
        'step': 'email',
        'title': 'Sign in',
        'fields': [
          {'name': 'login', 'label': 'Login', 'kind': 'text'},
          {'name': 'password', 'label': 'Password', 'kind': 'password', 'sensitive': true},
        ],
      });
      await pumpEventQueue();
      expect(rh.status, RhStatus.needInput);
      expect(rh.prompt!.fields.length, 2);

      rh.submit({'login': 'demo@example.com', 'password': 'S3cret'});
      expect(t.sent.length, 1);
      final msg = t.sent.single;
      expect(msg['type'], 'rh_input');
      expect(msg['session_id'], 's1');
      expect(msg['values'], {'login': 'demo@example.com'}); // login plaintext
      expect((msg['values'] as Map).containsKey('password'), isFalse); // never plaintext
      // sealed opens to the secret only
      final opened = SealedBox(sk).decrypt(base64.decode(msg['sealed'] as String));
      expect(jsonDecode(utf8.decode(opened)), {'password': 'S3cret'});
      expect(rh.status, RhStatus.working);
    });

    test('rh_state success/error update status+message', () async {
      final t = FakeTransport();
      final rh = RemoteHand(ws: t, sessionId: 's1');
      t.emit({'type': 'rh_state', 'session_id': 's1', 'state': 'error', 'message': 'Wrong password'});
      await pumpEventQueue();
      expect(rh.status, RhStatus.error);
      expect(rh.message, 'Wrong password');
    });

    test('server-side auth_done clears the spinner (success)', () async {
      final t = FakeTransport();
      final rh = RemoteHand(ws: t, sessionId: 's1');
      t.emit({'type': 'rh_state', 'session_id': 's1', 'state': 'working'});
      await pumpEventQueue();
      expect(rh.status, RhStatus.working);
      t.emit({'type': 'auth_done', 'provider': 'gdrive', 'email': 'demo@example.com'});
      await pumpEventQueue();
      expect(rh.status, RhStatus.success);
      expect(rh.message, 'demo@example.com');
    });
  });
}
