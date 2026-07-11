import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'web_utils.dart';
import 'user_model.dart';

// OAuth flow: Flutter → api.dudenest.com/auth/{provider} → Google/GitHub/Apple
//             → api.dudenest.com/auth/callback → dudenest.com?token=JWT&user=base64(JSON)
// Backend required endpoints (Go, api.dudenest.com):
//   GET /auth/google   — redirect to Google OAuth
//   GET /auth/github   — redirect to GitHub OAuth
//   GET /auth/apple    — redirect to Apple OAuth
//   GET /auth/callback — exchanges code for JWT, redirects to app with ?token=JWT&user=base64(JSON)

const _apiBase = 'https://api.dudenest.com';
const _kToken = 'auth_token';
const _kUser = 'auth_user';

class AuthService {
  static final AuthService _i = AuthService._();
  factory AuthService() => _i;
  AuthService._();

  String? _token;
  AuthUser? _user;

  String? get token => _token;
  AuthUser? get user => _user;
  bool get isLoggedIn => _token != null;
  bool get isDemo => _user?.demo == true;

  // Called at app startup — loads token from localStorage + handles OAuth callback in URL
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    final userJson = prefs.getString(_kUser);
    if (userJson != null) {
      try { _user = AuthUser.fromJson(jsonDecode(userJson) as Map<String, dynamic>); } catch (_) {}
    }
    // OAuth callback: ?token=JWT&user=base64url(JSON)
    final uri = Uri.parse(getLocationHref());
    final callbackToken = uri.queryParameters['token'];
    final callbackUser = uri.queryParameters['user'];
    if (callbackToken != null) {
      await _saveSession(callbackToken, callbackUser);
      historyReplaceState(uri.replace(queryParameters: {}).toString()); // clean URL
    } else if (uri.queryParameters['demo'] == '1' && !isLoggedIn) {
      // Deep link ?demo=1 (landing CTA): start a demo session automatically.
      try { await signInDemo(); } catch (_) {}
      historyReplaceState(uri.replace(queryParameters: {}).toString());
    }
  }

  // Demo login: POST /auth/demo returns {token, user} for a shared throwaway session.
  Future<void> signInDemo() async {
    final resp = await http.post(Uri.parse('$_apiBase/auth/demo'));
    if (resp.statusCode != 200) {
      throw Exception('Demo unavailable (${resp.statusCode})');
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    _token = j['token'] as String?;
    final u = j['user'] as Map<String, dynamic>?;
    if (u != null) _user = AuthUser.fromJson({...u, 'avatar_url': u['avatar_url']});
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) await prefs.setString(_kToken, _token!);
    if (_user != null) await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
  }

  Future<void> _saveSession(String token, String? userBase64) async {
    _token = token;
    if (userBase64 != null) {
      try {
        final json = utf8.decode(base64Url.decode(base64Url.normalize(userBase64)));
        _user = AuthUser.fromJson(jsonDecode(json) as Map<String, dynamic>);
      } catch (_) {}
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    if (_user != null) await prefs.setString(_kUser, jsonEncode(_user!.toJson()));
  }

  // Redirects browser to backend OAuth — page navigates away, returns with ?token=JWT
  void signInWith(String provider) {
    final returnUrl = Uri.encodeComponent(
      getLocationHref().split('?').first.split('#').first,
    );
    setLocationHref('$_apiBase/auth/$provider?return_url=$returnUrl');
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
  }
}
