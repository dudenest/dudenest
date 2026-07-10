import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/network/rh_validate.dart';

void main() {
  group('email (login text)', () {
    test('accepts valid', () {
      expect(validateRhField('text', 'demo@example.com'), isNull);
      expect(validateRhField('text', 'a.b_c+d@sub.example.co'), isNull);
      expect(validateRhField('text', 'demo123@example.com'), isNull);
    });
    test('rejects malformed', () {
      expect(validateRhField('text', 'demo'), isNotNull); // no @
      expect(validateRhField('text', 'demo@@x.com'), isNotNull); // two @
      expect(validateRhField('text', 'de mo@x.com'), isNotNull); // space
      expect(
          validateRhField('text', ' demo@x.com'), isNotNull); // leading space
      expect(
          validateRhField('text', 'demo@x.com '), isNotNull); // trailing space
      expect(validateRhField('text', '1demo@x.com'),
          isNotNull); // starts with digit
      expect(
          validateRhField('text', '.demo@x.com'), isNotNull); // starts with dot
      expect(validateRhField('text', 'demo@localhost'),
          isNotNull); // no dot in domain
      expect(validateRhField('text', 'demo!@x.com'), isNotNull); // bad char
      expect(validateRhField('text', 'demo@x..com'), isNotNull); // double dot
      expect(validateRhField('text', 'demo@example.c0m'),
          isNotNull); // digit in TLD
      expect(validateRhField('text', 'demo@example.123'),
          isNotNull); // numeric TLD
      expect(validateRhField('text', ''), isNotNull); // empty
    });
    test('login may be a phone', () {
      expect(validateRhField('text', '+48123456789'), isNull);
      expect(validateRhField('text', '+48 12'),
          isNotNull); // 4 digits — too short as phone
    });
  });

  group('password', () {
    test('non-empty, no spaces', () {
      expect(validateRhField('password', 'x'), isNull);
      expect(validateRhField('password', 'NoSpaces123!'), isNull);
      expect(validateRhField('password', 'ünïcode!@#\$%'), isNull);
      expect(validateRhField('password', 'has space'), isNotNull);
      expect(validateRhField('password', ' leading'), isNotNull);
      expect(validateRhField('password', 'trailing '), isNotNull);
      expect(validateRhField('password', ''), isNotNull);
    });
  });

  group('phone (tel)', () {
    test('digits + country code', () {
      expect(validateRhField('tel', '+48123456789'), isNull);
      expect(validateRhField('tel', '+1 (415) 555-2671'),
          isNull); // formatting stripped
      expect(validateRhField('tel', '123456789'), isNull); // 9 digits ok
    });
    test('rejects letters / too short / too long', () {
      expect(validateRhField('tel', '+48 abc'), isNotNull);
      expect(validateRhField('tel', '12345'), isNotNull); // 5 digits
      expect(
          validateRhField('tel', '+1234567890123456'), isNotNull); // 16 digits
      expect(validateRhField('tel', ''), isNotNull);
    });
  });

  group('SMS code', () {
    test('6-8 digits only', () {
      expect(validateRhField('code', '123456'), isNull);
      expect(validateRhField('code', '12 34 56'), isNull); // spaces stripped
    });
    test('rejects letters / wrong length', () {
      expect(validateRhField('code', '12345'), isNotNull); // too short
      expect(validateRhField('code', '123456789'), isNotNull); // too long
      expect(validateRhField('code', 'G-1234'), isNotNull); // letters
      expect(validateRhField('code', ''), isNotNull);
    });
  });

  test('unknown kind → only non-empty', () {
    expect(validateRhField('captcha_image', 'abc'), isNull);
    expect(validateRhField('captcha_image', ''), isNotNull);
  });
}
