import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/core/storage/direct_engine.dart';
import 'package:dudenest/core/storage/engine_config.dart';
import 'package:dudenest/core/storage/engine_factory.dart';
import 'package:dudenest/core/storage/storage_engine.dart';

// Przypina feature flag przełączania silników (E3b prep, 2026-07-17).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EngineConfig', () {
    test('default = relay gdy nic nie zapisane', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await EngineConfig.load(), EngineMode.relay);
    });

    test('save → load roundtrip', () async {
      SharedPreferences.setMockInitialValues({});
      await EngineConfig.save(EngineMode.direct);
      expect(await EngineConfig.load(), EngineMode.direct);
    });

    test('parse śmieci → relay (odporność)', () {
      expect(EngineConfig.parse('nonsense'), EngineMode.relay);
      expect(EngineConfig.parse(null), EngineMode.relay);
      expect(EngineConfig.parse('direct'), EngineMode.direct);
    });
  });

  group('EngineFactory', () {
    test('relay → zwraca przekazany silnik (identyczny obiekt)', () {
      final relay = RelayClient('https://relay.dudenest.com');
      final e = EngineFactory.build(EngineMode.relay, relay: relay);
      expect(identical(e, relay), isTrue);
    });

    test('direct z tokenem → DirectEngine', () {
      final relay = RelayClient('https://relay.dudenest.com');
      final StorageEngine e = EngineFactory.build(EngineMode.direct,
          relay: relay, accessToken: () async => 'TOK');
      expect(e, isA<DirectEngine>());
    });

    test('direct bez tokenu → rzuca (nie psuje po cichu)', () {
      final relay = RelayClient('https://relay.dudenest.com');
      expect(
        () => EngineFactory.build(EngineMode.direct, relay: relay),
        throwsA(isA<StateError>()),
      );
    });
  });
}
