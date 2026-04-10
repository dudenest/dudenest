import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../auth/auth_service.dart';

class RelayClient {
  final String baseUrl; // e.g. "http://10.71.0.1:8086"
  final http.Client _http;
  RelayClient(this.baseUrl, {http.Client? client}) : _http = client ?? http.Client();

  Map<String, String> get _headers {
    final token = AuthService().token;
    return {
      if (token != null) 'Authorization': 'Bearer \$token',
      'Content-Type': 'application/json',
    };
  }

  // WebSocket URL: ws://host:port/ws (or wss:// for https relay)
  String get wsUrl => baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://') + '/ws';

  // GET /providers — returns list of authenticated cloud accounts
  Future<List<Map<String, dynamic>>> getProviders() async {
    final resp = await _http.get(Uri.parse('\$baseUrl/providers'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('GET /providers: \${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['providers'] ?? []);
  }

  // GET /files — returns list of uploaded FileMaps
  Future<List<Map<String, dynamic>>> listFiles() async {
    final resp = await _http.get(Uri.parse('\$baseUrl/files'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('GET /files: \${resp.statusCode}');
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['files'] ?? []);
  }

  // POST /files/upload — multipart form with field "file"
  Future<Map<String, dynamic>> uploadFile(String filename, Uint8List bytes) async {
    final req = http.MultipartRequest('POST', Uri.parse('\$baseUrl/files/upload'))
      ..headers.addAll({'Authorization': 'Bearer \${AuthService().token ?? ""}'})
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _http.send(req);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) throw Exception('POST /files/upload: \${streamed.statusCode}: \$body');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  // GET /files/{id} — download file bytes
  Future<Uint8List> downloadFile(String fileId) async {
    final resp = await _http.get(Uri.parse('\$baseUrl/files/\$fileId'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('GET /files/\$fileId: \${resp.statusCode}');
    return resp.bodyBytes;
  }

  // DELETE /files/{id}
  Future<void> deleteFile(String fileId) async {
    final resp = await _http.delete(Uri.parse('\$baseUrl/files/\$fileId'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('DELETE /files/\$fileId: \${resp.statusCode}');
  }

  // POST /auth/session — start browser OAuth flow, returns step with screenshot+fields
  Future<Map<String, dynamic>> startAuthSession(String provider) async {
    final resp = await _http.post(Uri.parse('\$baseUrl/auth/session'),
        headers: _headers,
        body: jsonEncode({'provider': provider}));
    if (resp.statusCode != 200) throw Exception('POST /auth/session: \${resp.statusCode}: \${resp.body}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // POST /auth/input — fill a field in the browser
  Future<Map<String, dynamic>> authInput(String sessionId, String selector, String text) async {
    final resp = await _http.post(Uri.parse('\$baseUrl/auth/input'),
        headers: _headers,
        body: jsonEncode({'session_id': sessionId, 'selector': selector, 'text': text}));
    if (resp.statusCode != 200) throw Exception('POST /auth/input: \${resp.statusCode}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // POST /auth/click — click an element in the browser
  Future<Map<String, dynamic>> authClick(String sessionId, String selector) async {
    final resp = await _http.post(Uri.parse('\$baseUrl/auth/click'),
        headers: _headers,
        body: jsonEncode({'session_id': sessionId, 'selector': selector}));
    if (resp.statusCode != 200) throw Exception('POST /auth/click: \${resp.statusCode}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // GET /auth/status/{id} — poll current session status
  Future<Map<String, dynamic>> authStatus(String sessionId) async {
    final resp = await _http.get(Uri.parse('\$baseUrl/auth/status/\$sessionId'), headers: _headers);
    if (resp.statusCode != 200) throw Exception('GET /auth/status: \${resp.statusCode}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // POST /auth/close/{id} — close session
  Future<void> authClose(String sessionId) async {
    await _http.post(Uri.parse('\$baseUrl/auth/close/\$sessionId'), headers: _headers);
  }

  // --- Method A: Flutter-side OAuth (user's IP for login ✅) ---

  // GET /auth/url?provider=gdrive&callback=<uri> — returns OAuth URL for Flutter to open in browser
  Future<Map<String, dynamic>> getAuthUrl(String provider, String callbackUri) async {
    final uri = Uri.parse('\$baseUrl/auth/url').replace(queryParameters: {'provider': provider, 'callback': callbackUri});
    final resp = await _http.get(uri, headers: _headers);
    if (resp.statusCode != 200) throw Exception('GET /auth/url: \${resp.statusCode}: \${resp.body}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  // POST /auth/exchange {provider, code, redirect_uri, request_id?} — relay exchanges code → stores token
  Future<Map<String, dynamic>> exchangeOAuthCode(String provider, String code, String redirectUri, {String? requestId}) async {
    final body = <String, dynamic>{'provider': provider, 'code': code, 'redirect_uri': redirectUri};
    if (requestId != null) body['request_id'] = requestId;
    final resp = await _http.post(Uri.parse('\$baseUrl/auth/exchange'),
        headers: _headers, body: jsonEncode(body));
    if (resp.statusCode != 200) throw Exception('POST /auth/exchange: \${resp.statusCode}: \${resp.body}');
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }
}
