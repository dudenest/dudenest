import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/auth/user_model.dart';

void main() {
  test('fromJson full data', () {
    final u = AuthUser.fromJson({
      'id': 'google:123', 'email': 'a@b.com',
      'name': 'Test User', 'avatar_url': 'https://pic.example.com/a.jpg',
      'provider': 'google',
    });
    expect(u.id, 'google:123');
    expect(u.email, 'a@b.com');
    expect(u.name, 'Test User');
    expect(u.avatarUrl, 'https://pic.example.com/a.jpg');
    expect(u.provider, 'google');
  });

  test('fromJson missing optional fields', () {
    final u = AuthUser.fromJson({'id': 'github:1', 'email': 'x@y.com', 'provider': 'github'});
    expect(u.name, isNull);
    expect(u.avatarUrl, isNull);
    expect(u.provider, 'github');
  });

  test('fromJson missing provider defaults to unknown', () {
    final u = AuthUser.fromJson({'id': 'abc', 'email': 'a@b.com'});
    expect(u.provider, 'unknown');
  });

  test('toJson roundtrip', () {
    final u = AuthUser(id: 'g:1', email: 'a@b.com', name: 'Test', avatarUrl: 'https://pic', provider: 'google');
    final u2 = AuthUser.fromJson(u.toJson());
    expect(u2.id, u.id);
    expect(u2.email, u.email);
    expect(u2.name, u.name);
    expect(u2.avatarUrl, u.avatarUrl);
    expect(u2.provider, u.provider);
  });

  test('toJson null fields', () {
    final u = AuthUser(id: 'a:1', email: 'a@a.com', provider: 'apple');
    final j = u.toJson();
    expect(j['name'], isNull);
    expect(j['avatar_url'], isNull);
  });
}
