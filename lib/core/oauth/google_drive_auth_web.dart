// ignore_for_file: non_constant_identifier_names — access_token/client_id/scope MUSZĄ mieć
// nazwy snake_case, bo mapują 1:1 na właściwości JS API Google Identity Services.
import 'dart:async';
import 'dart:js_interop';
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

// Cache tokenu (in-memory). KRYTYCZNE: `requestAccessToken()` otwiera popup GIS, który przeglądarka
// blokuje POZA user-gesture. DirectEngine woła getDriveAccessToken per-żądanie (miniatury, upload po
// file-pickerze) — bez cache każde takie żądanie próbowałoby otworzyć popup i wisiałoby/padało. Popup
// pojawia się więc tylko przy pierwszym połączeniu (przycisk Connect = gest) i po wygaśnięciu tokenu.
String? _cachedToken;
DateTime? _cachedExpiry;

/// Zwraca access token `drive.file`. Zwraca token z cache, jeśli ważny (margines 60s); w przeciwnym
/// razie otwiera popup zgody Google (wymaga user-gesture) i cache'uje wynik. Rzuca, jeśli GIS
/// niezaładowane lub user odmówił.
Future<String> getDriveAccessToken() {
  final tok = _cachedToken;
  final exp = _cachedExpiry;
  if (tok != null && exp != null &&
      DateTime.now().isBefore(exp.subtract(const Duration(seconds: 60)))) {
    return Future.value(tok); // reużycie — brak popupu (kluczowe dla upload/miniatur)
  }
  final completer = Completer<String>();
  void onToken(_GisTokenResponse resp) {
    final t = resp.access_token;
    if (t != null && t.isNotEmpty) {
      _cachedToken = t;
      _cachedExpiry = DateTime.now().add(Duration(seconds: (resp.expires_in ?? 3600).toInt()));
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
