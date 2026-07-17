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

/// Zwraca świeży access token `drive.file`. Otwiera popup zgody Google przy pierwszym
/// wywołaniu (lub gdy token wygasł). Rzuca, jeśli GIS niezaładowane lub user odmówił.
Future<String> getDriveAccessToken() {
  final completer = Completer<String>();
  void onToken(_GisTokenResponse resp) {
    final tok = resp.access_token;
    if (tok != null && tok.isNotEmpty) {
      if (!completer.isCompleted) completer.complete(tok);
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
