import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/core/oauth/google_config.dart';
import 'package:dudenest/core/oauth/google_drive_auth.dart';
import 'package:dudenest/core/storage/direct_engine.dart';
import 'package:dudenest/core/storage/engine_config.dart';
import 'package:dudenest/core/storage/engine_factory.dart';

// Przypina wiązanie OAuth→DirectEngine (E3b). NIE testuje samego GIS (wymaga przeglądarki) —
// tylko że konfiguracja + provider tokenu wpinają się w EngineFactory i budują DirectEngine.
void main() {
  test('googleWebClientId to publiczny web client Google + scope drive.file', () {
    expect(googleWebClientId, endsWith('.apps.googleusercontent.com'));
    expect(driveFileScope, contains('drive.file'));
  });

  test('EngineFactory.direct z getDriveAccessToken → DirectEngine', () {
    final relay = RelayClient('https://relay.dudenest.com');
    // getDriveAccessToken (na VM → stub) przekazany jako referencja, nie wołany tu.
    final e = EngineFactory.build(EngineMode.direct,
        relay: relay, accessToken: getDriveAccessToken);
    expect(e, isA<DirectEngine>());
  });
}
