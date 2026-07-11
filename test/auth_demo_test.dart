import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/auth/user_model.dart';

void main() {
  group('AuthUser demo flag', () {
    test('parses demo:true from /auth/demo response shape', () {
      final u = AuthUser.fromJson(
          {'id': 'demo-uid', 'email': 'demo@dudenest.com', 'name': 'Demo', 'provider': 'demo', 'demo': true});
      expect(u.demo, isTrue);
      expect(u.provider, 'demo');
      expect(u.email, 'demo@dudenest.com');
    });

    test('defaults demo to false for normal OAuth users', () {
      final u = AuthUser.fromJson(
          {'id': 'google:1', 'email': 'a@b.c', 'provider': 'google'});
      expect(u.demo, isFalse);
    });

    test('round-trips demo through toJson/fromJson', () {
      final u = AuthUser(id: 'x', email: 'e', provider: 'demo', demo: true);
      expect(AuthUser.fromJson(u.toJson()).demo, isTrue);
    });
  });
}
