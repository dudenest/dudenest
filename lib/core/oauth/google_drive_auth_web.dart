import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/auth_service.dart';
import '../auth/web_utils.dart';

// Direct-mode Google Drive auth — BACKEND-ASSISTED (nie GIS). Zgoda robiona przez REDIRECT do
// api.dudenest.com (jak login Dudenest), backend trzyma refresh token i mintuje access tokeny.
// Zysk vs GIS: ZERO popupu (redirect zamiast popupu, którego przeglądarka nie blokuje) i /photos
// ładuje się od razu na KAŻDYM loginie (backend odnawia token po stronie serwera — parytet z relay).
// Bajty plików nadal Flutter→Drive wprost; backendowe jest tylko pozyskanie tokenu.

const _apiBase = 'https://api.dudenest.com';

// Cache access tokenu per uid (Dudenest). Backend zwraca ~1h token; cache'ujemy z marginesem.
String? _cachedToken;
DateTime? _cachedExpiry;
String? _cachedUid;

String? _uid() => AuthService().user?.id;
bool _valid() =>
    _cachedToken != null && _cachedExpiry != null &&
    DateTime.now().isBefore(_cachedExpiry!.subtract(const Duration(seconds: 60)));

Future<String> _dudenestJwt() async =>
    (await SharedPreferences.getInstance()).getString('auth_token') ?? '';

/// Ważny token dla BIEŻĄCEGO usera w cache? (bez sieci). Pełną prawdę daje [getDriveAccessToken].
Future<bool> hasValidDriveToken() async {
  final uid = _uid();
  return uid != null && _cachedUid == uid && _valid();
}

/// Access token drive.file dla bieżącego usera. Cache → backend GET (ciche, bez popupu).
/// [silent]/[hint] zachowane dla zgodności sygnatury (backend jest z natury cichy). Rzuca
/// `not_connected` gdy backend nie ma refresh tokena (→ ekran pokazuje „Connect" = redirect).
Future<String> getDriveAccessToken({bool silent = false, String? hint}) async {
  final uid = _uid();
  if (uid != null && _cachedUid == uid && _valid()) return _cachedToken!;
  final jwt = await _dudenestJwt();
  final resp = await http.get(
    Uri.parse('$_apiBase/api/v1/direct/google/token'),
    headers: {'Authorization': 'Bearer $jwt'},
  );
  if (resp.statusCode == 404) {
    throw StateError('not_connected'); // brak refresh tokena → brama Connect (redirect)
  }
  if (resp.statusCode != 200) {
    throw StateError('drive token fetch failed: HTTP ${resp.statusCode}');
  }
  final data = jsonDecode(resp.body) as Map<String, dynamic>;
  final tok = data['access_token'] as String?;
  if (tok == null || tok.isEmpty) throw StateError('no access_token in response');
  _cachedToken = tok;
  _cachedUid = uid;
  _cachedExpiry = DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 3000));
  return tok;
}

/// Wyczyść cache (token żyje w backendzie; przy Sign out czyścimy tylko lokalny cache — nie kasujemy
/// refresh tokena, żeby ponowny login tego samego usera łączył od razu; to jest źródło parytetu z relay).
Future<void> clearDriveToken() async {
  _cachedToken = null;
  _cachedExpiry = null;
  _cachedUid = null;
}

/// Pierwsze podłączenie: pełnostronicowy REDIRECT do backendu (zgoda Google przez redirect, NIE popup).
/// Po powrocie (`?drive=connected`) apka startuje, [getDriveAccessToken] dostaje token → /photos od razu.
Future<void> connectDrive() async {
  final jwt = await _dudenestJwt();
  final ret = getLocationHref().split('?').first.split('#').first; // np. https://dudenest.com/
  setLocationHref('$_apiBase/auth/google/drive'
      '?token=${Uri.encodeComponent(jwt)}&return_url=${Uri.encodeComponent(ret)}');
}
