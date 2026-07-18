// ignore_for_file: non_constant_identifier_names — access_token/client_id/scope MUSZĄ mieć
// nazwy snake_case, bo mapują 1:1 na właściwości JS API Google Identity Services.
import 'dart:async';
import 'dart:js_interop';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_config.dart';

// Pozyskanie access tokenu Google Drive (scope drive.file) w przeglądarce przez
// Google Identity Services (GIS) token model. Wymaga skryptu GIS w web/index.html
// (`https://accounts.google.com/gsi/client`).
//
// GIS token model daje access token (~1h, BEZ refresh tokena — ograniczenie klienta
// publicznego w przeglądarce, świadomie zaakceptowane w E0). Odnowienie = ponowne
// requestAccessToken (może wymagać ponownej zgody usera).

extension type _GisTokenResponse(JSObject _) implements JSObject {
  external String? get access_token;
  external String? get error;
  external num? get expires_in; // TTL tokenu w sekundach (~3600); num bo JS może dać double
}

extension type _GisTokenClient(JSObject _) implements JSObject {
  external void requestAccessToken();
}

extension type _GisTokenClientConfig._(JSObject _) implements JSObject {
  external factory _GisTokenClientConfig({
    required String client_id,
    required String scope,
    required JSFunction callback,
  });
}

@JS('google.accounts.oauth2.initTokenClient')
external _GisTokenClient _initTokenClient(_GisTokenClientConfig config);

// Cache tokenu. KRYTYCZNE: `requestAccessToken()` otwiera popup GIS, który przeglądarka blokuje POZA
// user-gesture. DirectEngine woła getDriveAccessToken per-żądanie (miniatury, upload po file-pickerze)
// — bez cache każde takie żądanie próbowałoby otworzyć popup i wisiałoby/padało. Popup pojawia się więc
// tylko przy pierwszym połączeniu (przycisk Connect = gest) i po wygaśnięciu. Token jest też
// persystowany (SharedPreferences → localStorage) → przetrwa reload strony bez ponownego popupu.
// Bezpieczeństwo: to access token drive.file, ~1h TTL, bez refresh — tak jak JWT aplikacji trzymany
// w localStorage; scope wąski, blast radius ograniczony.
String? _cachedToken;
DateTime? _cachedExpiry;
const _kTok = 'drive_access_token';
const _kExp = 'drive_access_token_exp_ms';

bool _valid(String? t, DateTime? e) =>
    t != null && e != null && DateTime.now().isBefore(e.subtract(const Duration(seconds: 60)));

/// Czy istnieje ważny token (w pamięci lub w SharedPreferences). Pozwala DirectModeScreen
/// auto-połączyć się po reloadzie strony BEZ popupu GIS.
Future<bool> hasValidDriveToken() async {
  if (_valid(_cachedToken, _cachedExpiry)) return true;
  final p = await SharedPreferences.getInstance();
  final ms = p.getInt(_kExp);
  return ms != null && _valid(p.getString(_kTok), DateTime.fromMillisecondsSinceEpoch(ms));
}

/// Zwraca access token `drive.file`. Kolejność: cache-w-pamięci → SharedPreferences (przetrwa reload)
/// → popup zgody Google (wymaga user-gesture). Cache'uje wynik w obu warstwach. Rzuca, jeśli GIS
/// niezaładowane lub user odmówił.
Future<String> getDriveAccessToken() async {
  if (_valid(_cachedToken, _cachedExpiry)) return _cachedToken!; // brak popupu (upload/miniatury)
  final prefs = await SharedPreferences.getInstance();
  final pms = prefs.getInt(_kExp);
  if (pms != null) {
    final pt = prefs.getString(_kTok);
    final pe = DateTime.fromMillisecondsSinceEpoch(pms);
    if (_valid(pt, pe)) {
      _cachedToken = pt;
      _cachedExpiry = pe;
      return pt!; // token przetrwał reload → brak popupu
    }
  }
  final completer = Completer<String>();
  void onToken(_GisTokenResponse resp) {
    final t = resp.access_token;
    if (t != null && t.isNotEmpty) {
      _cachedToken = t;
      _cachedExpiry = DateTime.now().add(Duration(seconds: (resp.expires_in ?? 3600).toInt()));
      prefs.setString(_kTok, t);
      prefs.setInt(_kExp, _cachedExpiry!.millisecondsSinceEpoch);
      if (!completer.isCompleted) completer.complete(t);
    } else if (!completer.isCompleted) {
      completer.completeError(
          StateError('GIS token error: ${resp.error ?? "brak access_token"}'));
    }
  }

  final client = _initTokenClient(_GisTokenClientConfig(
    client_id: googleWebClientId,
    scope: driveFileScope,
    callback: onToken.toJS,
  ));
  client.requestAccessToken();
  return completer.future;
}
