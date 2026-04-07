// oauth_service.dart — Orchestrates cloud provider OAuth on user's device (user's IP ✅).
// Auth code obtained here → sent to relay via POST /auth/exchange.
// Relay only does the token exchange (relay IP acceptable for server calls).
import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import '../network/relay_client.dart';

/// Platform-appropriate OAuth callback URLs.
/// Mobile/Desktop: custom scheme intercepted by flutter_web_auth_2
/// Web: page within the Flutter web app (requires callbackUrl registered in Google Cloud Console)
const _callbackScheme = 'com.dudenest.app';
const _mobileCallbackUrl = '$_callbackScheme://oauth/callback';
// Web: app.dudenest.com/auth (flutter_web_auth_2 web callback page — see web/callback.html)
const _webCallbackUrl = 'https://app.dudenest.com/auth';

/// Returns the platform-appropriate redirect URI for OAuth.
String get oauthCallbackUrl => kIsWeb ? _webCallbackUrl : _mobileCallbackUrl;

/// OAuthService: full OAuth flow on user's device → sends code to relay.
/// Relay stores the token and uses it for cloud storage API calls.
class OAuthService {
  final RelayClient relay;
  OAuthService(this.relay);

  /// Adds a cloud provider account via OAuth.
  /// Opens system browser (user's IP ✅), user approves, relay exchanges code → stores token.
  /// Returns the email of the connected account.
  Future<String> addProvider(String provider, {String? requestId}) async {
    final callback = oauthCallbackUrl;
    // 1. Get auth URL from relay (relay has client_secret, Flutter only needs client_id via URL)
    final urlData = await relay.getAuthUrl(provider, callback);
    final authUrl = urlData['url'] as String;
    // 2. Open browser on user's device — user logs in at their own IP ✅
    final result = await FlutterWebAuth2.authenticate(
      url: authUrl,
      callbackUrlScheme: kIsWeb ? 'https' : _callbackScheme,
    );
    // 3. Extract auth code from callback URL
    final code = Uri.parse(result).queryParameters['code'] ?? '';
    if (code.isEmpty) throw Exception('No OAuth code received in callback');
    // 4. Send code to relay — relay does token exchange (relay IP for exchange is acceptable)
    final data = await relay.exchangeOAuthCode(provider, code, callback, requestId: requestId);
    return data['email'] as String? ?? 'unknown';
  }
}
