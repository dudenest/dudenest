import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/web_utils.dart';

// AccountsService — warstwa kliencka multi-konta direct (MP1b). Rozmawia z backendem `directauth`:
// listuje konta usera, inicjuje zgodę (redirect) na nowe konto, usuwa konto, mintuje access tokeny.
// Bajty plików nadal Flutter→provider wprost (DirectEngine); tu wyłącznie zarządzanie kontami + tokeny.
// Endpointy (backend MP1a, prod): patrz session-2026-07-19-...-multiprovider.md „Endpointy backendu".

const _apiBase = 'https://api.dudenest.com';

/// Konto direct (multi-provider). `accountId` = `provider:email` (np. `google:me@gmail.com`).
class DirectAccount {
  final String accountId;
  final String provider; // google | onedrive | dropbox | mega (MP1: google)
  final String email;
  const DirectAccount({required this.accountId, required this.provider, required this.email});
  factory DirectAccount.fromJson(Map<String, dynamic> j) => DirectAccount(
        accountId: j['account_id'] as String? ?? '',
        provider: j['provider'] as String? ?? '',
        email: j['email'] as String? ?? '',
      );
}

/// AccountsService — klient endpointów multi-konta direct. `http.Client`, `redirect` i `origin` są
/// WSTRZYKIWANE, więc serwis jest testowalny bez sieci i bez realnego przekierowania przeglądarki.
class AccountsService {
  final http.Client _http;
  final void Function(String url) _redirect; // domyślnie web_utils.setLocationHref (no-op poza web)
  final String Function() _origin; // domyślnie web_utils.getLocationHref
  // Cache access tokenu per konto (backend zwraca ~1h token). Bez cache KAŻDA miniatura/preview/download
  // = round-trip do /accounts/{id}/token, bo DirectEngine woła accessToken() per żądanie. Margines 60 s,
  // 1:1 jak legacy `_cachedToken/_cachedExpiry` w google_drive_auth_web.dart.
  final Map<String, String> _tokenCache = {};
  final Map<String, DateTime> _tokenExpiry = {};

  AccountsService({
    http.Client? client,
    void Function(String url)? redirect,
    String Function()? origin,
  })  : _http = client ?? http.Client(),
        _redirect = redirect ?? setLocationHref,
        _origin = origin ?? getLocationHref;

  Future<String> _jwt() async =>
      (await SharedPreferences.getInstance()).getString('auth_token') ?? '';
  Map<String, String> _auth(String jwt) => {'Authorization': 'Bearer $jwt'};

  /// Lista kont usera. GET /api/v1/direct/accounts (Bearer JWT). Akceptuje bare-array lub `{accounts:[...]}`.
  Future<List<DirectAccount>> list() async {
    final jwt = await _jwt();
    final resp = await _http.get(Uri.parse('$_apiBase/api/v1/direct/accounts'), headers: _auth(jwt));
    if (resp.statusCode != 200) throw StateError('accounts list failed: HTTP ${resp.statusCode}');
    final data = jsonDecode(resp.body);
    final raw = data is List ? data : (data['accounts'] as List? ?? const []);
    return raw
        .map((e) => DirectAccount.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Dodanie konta: pełnostronicowy REDIRECT do zgody providera (jak `connectDrive`, ale per provider).
  /// MP1: provider='google'. Po powrocie backend ma refresh token NOWEGO konta (nie nadpisuje istniejących).
  Future<void> connect({String provider = 'google'}) async {
    final jwt = await _jwt();
    final ret = _origin().split('?').first.split('#').first; // czysty origin bez query/hash
    _redirect('$_apiBase/auth/${Uri.encodeComponent(provider)}/connect'
        '?token=${Uri.encodeComponent(jwt)}&return_url=${Uri.encodeComponent(ret)}');
  }

  /// Usunięcie konta (revoke + delete). DELETE /api/v1/direct/accounts/{id}. account_id URL-encoded (`:` i `@`).
  Future<void> remove(String accountId) async {
    final jwt = await _jwt();
    final resp = await _http.delete(
      Uri.parse('$_apiBase/api/v1/direct/accounts/${Uri.encodeComponent(accountId)}'),
      headers: _auth(jwt),
    );
    if (resp.statusCode != 200 && resp.statusCode != 204) {
      throw StateError('account remove failed: HTTP ${resp.statusCode}');
    }
    _tokenCache.remove(accountId);
    _tokenExpiry.remove(accountId);
  }

  /// Świeży access token dla konta (mint z refresh po stronie backendu). GET /api/v1/direct/accounts/{id}/token.
  /// Cache z marginesem 60 s. Wstrzykiwany do `DirectEngine(accessToken: () => tokenFor(accountId))`.
  Future<String> tokenFor(String accountId) async {
    final exp = _tokenExpiry[accountId];
    final tok = _tokenCache[accountId];
    if (tok != null && exp != null &&
        DateTime.now().isBefore(exp.subtract(const Duration(seconds: 60)))) {
      return tok;
    }
    final jwt = await _jwt();
    final resp = await _http.get(
      Uri.parse('$_apiBase/api/v1/direct/accounts/${Uri.encodeComponent(accountId)}/token'),
      headers: _auth(jwt),
    );
    if (resp.statusCode != 200) {
      throw StateError('account token fetch failed ($accountId): HTTP ${resp.statusCode}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final t = data['access_token'] as String?;
    if (t == null || t.isEmpty) throw StateError('no access_token for $accountId');
    _tokenCache[accountId] = t;
    _tokenExpiry[accountId] =
        DateTime.now().add(Duration(seconds: (data['expires_in'] as num?)?.toInt() ?? 3000));
    return t;
  }
}
