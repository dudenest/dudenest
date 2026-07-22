import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/analytics/analytics.dart';
import 'package:dudenest/core/auth/auth_service.dart';

void main() {
  test('maps supported tabs to stable virtual paths and titles', () {
    expect(analyticsPathForTab(0), '/photos');
    expect(analyticsTitleForTab(1), 'Files');
    expect(analyticsPathForTab(3), '/settings');
  });

  test('does not expose unsupported tabs as a PII-bearing path', () {
    expect(analyticsPathForTab(2), '/photos');
    expect(analyticsTitleForTab(99), 'Photos');
  });

  test('builds a full PII-free virtual page location', () {
    expect(analyticsVirtualLocation('https://dudenest.com', '/photos'), 'https://dudenest.com/photos');
    expect(analyticsVirtualLocation('https://dudenest.com', '/settings'), isNot(contains('?')));
  });

  test('tracks pending login only for Google', () {
    expect(shouldTrackGoogleLogin('google'), isTrue);
    expect(shouldTrackGoogleLogin('github'), isFalse);
    expect(shouldTrackGoogleLogin('apple'), isFalse);
    expect(shouldTrackGoogleLogin(null), isFalse);
  });
}
