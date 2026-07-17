import 'package:shared_preferences/shared_preferences.dart';

/// Wybór silnika storage (feature flag, W4 „Direct Mode obok relaya").
///
/// - [relay]  — dzisiejszy model: aplikacja rozmawia z relayem (RelayClient). DOMYŚLNY.
/// - [direct] — DirectEngine: bezpośrednio Google Drive REST, bez relaya (E3).
///
/// Flaga jest per-użytkownik (SharedPreferences), przełączalna w runtime — plan zakłada
/// migrację per konto, nie globalny przełącznik (`RELAY-REMOVAL-FLUTTER-FIRST-PLAN.md` W4).
enum EngineMode { relay, direct }

class EngineConfig {
  static const _key = 'engine_mode';

  /// Odczyt trybu z SharedPreferences. Nieznana/pusta wartość → [EngineMode.relay] (bezpieczny default).
  static Future<EngineMode> load() async {
    final p = await SharedPreferences.getInstance();
    return parse(p.getString(_key));
  }

  /// Zapis trybu.
  static Future<void> save(EngineMode mode) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, mode.name);
  }

  /// Parsowanie odporne na śmieci — cokolwiek nie-znanego → relay.
  static EngineMode parse(String? s) => EngineMode.values.firstWhere(
        (e) => e.name == s,
        orElse: () => EngineMode.relay,
      );
}
