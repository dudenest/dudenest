import 'direct_engine.dart';
import 'engine_config.dart';
import 'storage_engine.dart';

/// Buduje właściwy [StorageEngine] dla wybranego [EngineMode] (feature flag).
///
/// Zaprojektowany tak, by E3b (podłączenie OAuth) był JEDYNĄ brakującą częścią:
/// - tryb `relay` → zwraca przekazany [relay] (dziś RelayClient) — zero zmian.
/// - tryb `direct` → buduje [DirectEngine] z wstrzykniętym providerem tokenu.
///   [accessToken] jest wymagany dla direct i dostarczy go warstwa OAuth (E3b).
///   Do tego czasu wywołanie direct bez tokenu jawnie rzuca (nie „po cichu psuje").
class EngineFactory {
  static StorageEngine build(
    EngineMode mode, {
    required StorageEngine relay,
    Future<String> Function()? accessToken,
  }) {
    switch (mode) {
      case EngineMode.relay:
        return relay;
      case EngineMode.direct:
        if (accessToken == null) {
          throw StateError(
              'EngineMode.direct wymaga providera accessToken (warstwa OAuth — E3b). '
              'Dopóki OAuth nie jest podłączony, tryb direct jest niedostępny.');
        }
        return DirectEngine(accessToken: accessToken);
    }
  }
}
