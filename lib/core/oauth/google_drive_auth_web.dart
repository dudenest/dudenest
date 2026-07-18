// ignore_for_file: non_constant_identifier_names — access_token/client_id/scope MUSZĄ mieć
// nazwy snake_case, bo mapują 1:1 na właściwości JS API Google Identity Services.
import 'dart:async';
import 'dart:js_interop';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_service.dart';
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
// tylko przy pierwszym połączeniu (przycisk Connect = gest) i po wygaśnięciu.
//
// 🔒 IZOLACJA MIĘDZY KONTAMI: token jest ZWIĄZANY z id użytkownika Dudenest (`_uid`). Persystujemy go w
// SharedPreferences RAZEM z uid; przy odczycie używamy TYLKO gdy `storedUid == bieżący uid`. Bez tego
// po przełączeniu konta Dudenest następny użytkownik dziedziczyłby token Drive poprzedniego (realny
// wyciek — zgłoszony 2026-07-18). `clearDriveToken()` (wołane przy wylogowaniu) kasuje pamięć+dysk.
// DEMO (sesja WSPÓŁDZIELONA) → NIE persystujemy (tylko pamięć per-karta), bo demo-uid jest wspólny.
String? _cachedToken;
DateTime? _cachedExpiry;
String? _cachedUid;
const _kTok = 'drive_access_token';
const _kExp = 'drive_access_token_exp_ms';
const _kUid = 'drive_access_token_uid';

String? _uid() => AuthService().user?.id;
bool _persistable() => !AuthService().isDemo; // demo = współdzielone → nigdy na dysk

bool _valid(String? t, DateTime? e) =>
    t != null && e != null && DateTime.now().isBefore(e.subtract(const Duration(seconds: 60)));
bool _memHit(String? uid) => uid != null && _cachedUid == uid && _valid(_cachedToken, _cachedExpiry);

/// Kasuje token Drive (pamięć + SharedPreferences). Wołane przy wylogowaniu z Dudenest — inaczej
/// następny użytkownik odziedziczyłby dostęp do Drive poprzedniego (wyciek między kontami).
Future<void> clearDriveToken() async {
  _cachedToken = null;
  _cachedExpiry = null;
  _cachedUid = null;
  final p = await SharedPreferences.getInstance();
  await p.remove(_kTok);
  await p.remove(_kExp);
  await p.remove(_kUid);
}

/// Czy istnieje ważny token NALEŻĄCY DO BIEŻĄCEGO użytkownika Dudenest. Pozwala DirectModeScreen
/// auto-połączyć się po reloadzie BEZ popupu — ale nigdy cudzym tokenem.
Future<bool> hasValidDriveToken() async {
  final uid = _uid();
  if (_memHit(uid)) return true;
  if (uid == null || !_persistable()) return false;
  final p = await SharedPreferences.getInstance();
  final ms = p.getInt(_kExp);
  return p.getString(_kUid) == uid && ms != null &&
      _valid(p.getString(_kTok), DateTime.fromMillisecondsSinceEpoch(ms));
}

/// Zwraca access token `drive.file` dla BIEŻĄCEGO użytkownika Dudenest. Kolejność: pamięć (jego) →
/// SharedPreferences (jego, przetrwa reload) → popup zgody Google (user-gesture). Rzuca, jeśli GIS
/// niezaładowane lub user odmówił.
Future<String> getDriveAccessToken() async {
  final uid = _uid();
  if (_memHit(uid)) return _cachedToken!; // brak popupu (upload/miniatury)
  final prefs = await SharedPreferences.getInstance();
  if (uid != null && _persistable() && prefs.getString(_kUid) == uid) {
    final pms = prefs.getInt(_kExp);
    if (pms != null) {
      final pt = prefs.getString(_kTok);
      final pe = DateTime.fromMillisecondsSinceEpoch(pms);
      if (_valid(pt, pe)) {
        _cachedToken = pt;
        _cachedExpiry = pe;
        _cachedUid = uid;
        return pt!; // token przetrwał reload (ten sam user) → brak popupu
      }
    }
  }
  final completer = Completer<String>();
  void onToken(_GisTokenResponse resp) {
    final t = resp.access_token;
    if (t != null && t.isNotEmpty) {
      _cachedToken = t;
      _cachedExpiry = DateTime.now().add(Duration(seconds: (resp.expires_in ?? 3600).toInt()));
      _cachedUid = uid;
      if (uid != null && _persistable()) {
        prefs.setString(_kTok, t);
        prefs.setInt(_kExp, _cachedExpiry!.millisecondsSinceEpoch);
        prefs.setString(_kUid, uid);
      }
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
