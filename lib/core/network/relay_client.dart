import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../auth/auth_service.dart';

class RelayException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;
  RelayException(this.message, {this.statusCode, this.body});
  @override
  String toString() => 'RelayException: $message (Status: $statusCode)';
}

class RelayClient {
  final String baseUrl; // e.g. "https://relay.dudenest.com"
  final String? relayToken; // Layer 3: short-lived HMAC from GET /api/v1/relays, sent as X-Relay-Token
  final http.Client _http;
  RelayClient(this.baseUrl, {http.Client? client, this.relayToken}) : _http = client ?? http.Client();

  Map<String, String> get headers {
    final token = AuthService().token;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      if (relayToken != null) 'X-Relay-Token': relayToken!,
    };
  }

  Map<String, String> get _headers => {
    ...headers,
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // WebSocket URL: ws://host:port/ws (or wss:// for https relay)
  String get wsUrl => baseUrl.replaceFirst('http://', 'ws://').replaceFirst('https://', 'wss://') + '/ws';

  dynamic _processResponse(http.Response resp, String context) {
    if (resp.statusCode != 200) {
      throw RelayException('$context: HTTP ${resp.statusCode}', statusCode: resp.statusCode, body: resp.body);
    }
    final contentType = resp.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw RelayException('$context: Expected JSON but got $contentType', statusCode: resp.statusCode, body: resp.body);
    }
    try {
      return jsonDecode(resp.body);
    } catch (e) {
      throw RelayException('$context: Failed to parse JSON: $e', statusCode: resp.statusCode, body: resp.body);
    }
  }

  // GET /providers — returns list of authenticated cloud accounts (legacy — pre-Phase α structure).
  // Kept for backward compatibility with the StorageVisualizer.
  Future<List<Map<String, dynamic>>> getProviders() async {
    final resp = await _http.get(Uri.parse('$baseUrl/providers'), headers: _headers);
    final data = _processResponse(resp, 'GET /providers') as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['providers'] ?? []);
  }

  // ─── Phase α/β admin endpoints (multi-account policy) ────────────────────
  // GET /admin/accounts — returns {accounts: [...], policy: {...}} per the relay's
  // account.Manager state. Each account has id (int), provider, email, role, priority,
  // pinned, quota_used_bytes, quota_total_bytes, status, etc. See dudenest-relay
  // docs/MULTI-ACCOUNT.md for the full field reference.
  Future<Map<String, dynamic>> getAdminAccounts() async {
    final resp = await _http.get(Uri.parse('$baseUrl/admin/accounts'), headers: _headers);
    return _processResponse(resp, 'GET /admin/accounts') as Map<String, dynamic>;
  }

  // PATCH /admin/accounts/{id} — overlay any subset of: role, priority, pinned,
  // soft_cap_pct, hard_cap_pct, max_file_size_mb, accepts_content_types, region,
  // compression_level. Returns the refreshed account record.
  Future<Map<String, dynamic>> patchAdminAccount(int id, Map<String, dynamic> patch) async {
    final resp = await _http.patch(
      Uri.parse('$baseUrl/admin/accounts/$id'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    );
    return _processResponse(resp, 'PATCH /admin/accounts/$id') as Map<String, dynamic>;
  }

  // POST /admin/accounts/reorder — bulk priority reorder by submitting the new ID order.
  // IDs missing from the list keep their relative order and are appended.
  Future<Map<String, dynamic>> reorderAdminAccounts(List<int> ids) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/admin/accounts/reorder'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'ids': ids}),
    );
    return _processResponse(resp, 'POST /admin/accounts/reorder') as Map<String, dynamic>;
  }

  // POST /admin/accounts/{id}/refresh-quota — on-demand quota fetch from the cloud
  // provider. Returns the refreshed account.
  Future<Map<String, dynamic>> refreshAdminQuota(int id) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/admin/accounts/$id/refresh-quota'),
      headers: _headers,
    );
    return _processResponse(resp, 'POST /admin/accounts/$id/refresh-quota') as Map<String, dynamic>;
  }

  // DELETE /admin/accounts/{id} — flips the account to Role=Drain. The relay's
  // background drain worker then migrates replicas to other accounts and finally
  // sets Status=Removed when done. Phase γ (v0.19.0+).
  Future<Map<String, dynamic>> drainAdminAccount(int id) async {
    final resp = await _http.delete(
      Uri.parse('$baseUrl/admin/accounts/$id'),
      headers: _headers,
    );
    return _processResponse(resp, 'DELETE /admin/accounts/$id') as Map<String, dynamic>;
  }

  // POST /admin/accounts/refresh-quota — bulk on-demand quota refresh for ALL active accounts.
  // Fire-and-forget; returns 202 immediately. Next GET /admin/accounts will see refreshed values
  // within ~5-10s (Drive about.get latency). s319 #9.
  Future<Map<String, dynamic>> refreshAllAdminQuota() async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/admin/accounts/refresh-quota'),
      headers: _headers,
    );
    return _processResponse(resp, 'POST /admin/accounts/refresh-quota') as Map<String, dynamic>;
  }

  // GET /admin/accounts/{id}/drain-progress — returns live drain worker progress for one account.
  // Response shape: {account_id, role, status, in_progress, snapshot: {started_at, file_maps_scanned,
  // replicas_to_migrate, replicas_migrated, replicas_failed, last_err} | null}.
  // snapshot is null when worker hasn't started its first sweep yet (account is Drain but waiting).
  // Phase γ (v0.20.1+).
  Future<Map<String, dynamic>> getDrainProgress(int id) async {
    final resp = await _http.get(
      Uri.parse('$baseUrl/admin/accounts/$id/drain-progress'),
      headers: _headers,
    );
    return _processResponse(resp, 'GET /admin/accounts/$id/drain-progress') as Map<String, dynamic>;
  }

  // GET /admin/scan/status — P5c scan engine state map: {providerID: {state, started_at, last_finished_at,
  // files_discovered, files_newly_indexed, files_skipped, errors, last_error}}. Drives Sync Status surface
  // and per-account "last scanned" indicator. s320 Phase 1.
  Future<Map<String, dynamic>> getScanStatus() async {
    final resp = await _http.get(Uri.parse('$baseUrl/admin/scan/status'), headers: _headers);
    return _processResponse(resp, 'GET /admin/scan/status') as Map<String, dynamic>;
  }
  // POST /admin/scan/start?provider=<id> — kick off (or resume) cloud-side scan for one provider.
  // Scanner discovers files added directly to the cloud (outside dudenest), registers them as Foreign FileMaps
  // so they appear in /files. Idempotent: dedup by CloudID skips already-indexed entries.
  Future<Map<String, dynamic>> startScan(String providerID) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/admin/scan/start?provider=${Uri.encodeQueryComponent(providerID)}'),
      headers: _headers);
    return _processResponse(resp, 'POST /admin/scan/start') as Map<String, dynamic>;
  }
  // POST /admin/scan/pause?provider=<id> — settles within seconds at next folder boundary.
  Future<Map<String, dynamic>> pauseScan(String providerID) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/admin/scan/pause?provider=${Uri.encodeQueryComponent(providerID)}'),
      headers: _headers);
    return _processResponse(resp, 'POST /admin/scan/pause') as Map<String, dynamic>;
  }
  // POST /admin/scan/bootstrap?provider=<id>[&reset=1] — s321: one-shot Drive-wide retro-index.
  // Catches files that existed BEFORE Phase 2 pageToken seed (e.g. uploaded directly to Drive before
  // dudenest connection). Idempotent — re-run safe; pass reset=true to force re-index even if already done.
  Future<Map<String, dynamic>> bootstrapWholeDrive(String providerID, {bool reset = false}) async {
    final qs = 'provider=${Uri.encodeQueryComponent(providerID)}${reset ? "&reset=1" : ""}';
    final resp = await _http.post(Uri.parse('$baseUrl/admin/scan/bootstrap?$qs'), headers: _headers);
    return _processResponse(resp, 'POST /admin/scan/bootstrap') as Map<String, dynamic>;
  }

  // PATCH /admin/policy — overlay merge of any subset of AccountPolicyConfig fields
  // (replication_factor, diversity_required, soft_cap_default_pct, etc.). Returns
  // the merged + persisted policy.
  Future<Map<String, dynamic>> patchAdminPolicy(Map<String, dynamic> patch) async {
    final resp = await _http.patch(
      Uri.parse('$baseUrl/admin/policy'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode(patch),
    );
    return _processResponse(resp, 'PATCH /admin/policy') as Map<String, dynamic>;
  }

  // GET /files — returns list of uploaded FileMaps
  Future<List<Map<String, dynamic>>> listFiles() async {
    final resp = await _http.get(Uri.parse('$baseUrl/files'), headers: _headers);
    final data = _processResponse(resp, 'GET /files') as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['files'] ?? []);
  }

  // POST /files/upload — multipart form with field "file"
  Future<Map<String, dynamic>> uploadFile(String filename, Uint8List bytes, {String strategy = 'Replica'}) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/files/upload'))
      ..headers.addAll({...headers, 'Accept': 'application/json'})
      ..fields['strategy'] = strategy
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await _http.send(req);
    final resp = await http.Response.fromStream(streamed);
    return _processResponse(resp, 'POST /files/upload') as Map<String, dynamic>;
  }

  // GET /files/{id}/map — returns full FileMap (replicas, locations)
  Future<Map<String, dynamic>> getFileMap(String fileId) async {
    final resp = await _http.get(Uri.parse('$baseUrl/files/$fileId/map'), headers: _headers);
    return _processResponse(resp, 'GET /files/$fileId/map') as Map<String, dynamic>;
  }

  // GET /files/{id} — download file bytes
  Future<Uint8List> downloadFile(String fileId) async {
    final resp = await _http.get(Uri.parse('$baseUrl/files/$fileId'), headers: _headers);
    if (resp.statusCode != 200) {
      throw RelayException('GET /files/$fileId: HTTP ${resp.statusCode}', statusCode: resp.statusCode, body: resp.body);
    }
    return resp.bodyBytes;
  }

  // DELETE /files/{id}
  Future<void> deleteFile(String fileId) async {
    final resp = await _http.delete(Uri.parse('$baseUrl/files/$fileId'), headers: _headers);
    _processResponse(resp, 'DELETE /files/$fileId');
  }

  // POST /auth/session — start browser OAuth flow, returns step with screenshot+fields
  Future<Map<String, dynamic>> startAuthSession(String provider) async {
    final resp = await _http.post(Uri.parse('$baseUrl/auth/session'),
        headers: _headers,
        body: jsonEncode({'provider': provider}));
    return _processResponse(resp, 'POST /auth/session') as Map<String, dynamic>;
  }

  // POST /auth/input — fill a field in the browser
  Future<Map<String, dynamic>> authInput(String sessionId, String selector, String text) async {
    final resp = await _http.post(Uri.parse('$baseUrl/auth/input'),
        headers: _headers,
        body: jsonEncode({'session_id': sessionId, 'selector': selector, 'text': text}));
    return _processResponse(resp, 'POST /auth/input') as Map<String, dynamic>;
  }

  // POST /auth/click — click an element in the browser
  Future<Map<String, dynamic>> authClick(String sessionId, String selector) async {
    final resp = await _http.post(Uri.parse('$baseUrl/auth/click'),
        headers: _headers,
        body: jsonEncode({'session_id': sessionId, 'selector': selector}));
    return _processResponse(resp, 'POST /auth/click') as Map<String, dynamic>;
  }

  // GET /auth/status/{id} — poll current session status
  Future<Map<String, dynamic>> authStatus(String sessionId) async {
    final resp = await _http.get(Uri.parse('$baseUrl/auth/status/$sessionId'), headers: _headers);
    return _processResponse(resp, 'GET /auth/status') as Map<String, dynamic>;
  }

  // POST /auth/close/{id} — close session
  Future<void> authClose(String sessionId) async {
    final resp = await _http.post(Uri.parse('$baseUrl/auth/close/$sessionId'), headers: _headers);
    _processResponse(resp, 'POST /auth/close');
  }

  // --- Method A: Flutter-side OAuth (user's IP for login ✅) ---

  // GET /auth/url?provider=gdrive&callback=<uri> — returns OAuth URL for Flutter to open in browser
  Future<Map<String, dynamic>> getAuthUrl(String provider, String callbackUri) async {
    final uri = Uri.parse('$baseUrl/auth/url').replace(queryParameters: {'provider': provider, 'callback': callbackUri});
    final resp = await _http.get(uri, headers: _headers);
    return _processResponse(resp, 'GET /auth/url') as Map<String, dynamic>;
  }

  // POST /auth/exchange {provider, code, redirect_uri, request_id?} — relay exchanges code → stores token
  Future<Map<String, dynamic>> exchangeOAuthCode(String provider, String code, String redirectUri, {String? requestId}) async {
    final body = <String, dynamic>{'provider': provider, 'code': code, 'redirect_uri': redirectUri};
    if (requestId != null) body['request_id'] = requestId;
    final resp = await _http.post(Uri.parse('$baseUrl/auth/exchange'),
        headers: _headers, body: jsonEncode(body));
    return _processResponse(resp, 'POST /auth/exchange') as Map<String, dynamic>;
  }

  // GET /files/{id}/meta — returns file metadata (favorites, albums, location, caption)
  Future<Map<String, dynamic>> getMeta(String fileId) async {
    final resp = await _http.get(Uri.parse('$baseUrl/files/$fileId/meta'), headers: _headers);
    return _processResponse(resp, 'GET /files/$fileId/meta') as Map<String, dynamic>;
  }

  // PATCH /files/{id}/meta — updates file metadata
  Future<Map<String, dynamic>> patchMeta(String fileId, Map<String, dynamic> patch) async {
    final resp = await _http.patch(
      Uri.parse('$baseUrl/files/$fileId/meta'),
      headers: _headers,
      body: jsonEncode(patch),
    );
    return _processResponse(resp, 'PATCH /files/$fileId/meta') as Map<String, dynamic>;
  }

  // GET /admin/version — returns running relay version + latest GitHub release + canonical URLs.
  // Powers the Update screen header. Available since relay v0.12.0; older relays return 404, which
  // the caller treats as "unknown — show only what we know locally" rather than an error.
  Future<Map<String, dynamic>> getRelayVersionInfo() async {
    final resp = await _http.get(Uri.parse('$baseUrl/admin/version'), headers: _headers);
    return _processResponse(resp, 'GET /admin/version') as Map<String, dynamic>;
  }

  // POST /admin/update — relay self-updates from the GitHub release matching its arch + restarts.
  // Connection drops ~2 seconds after the response body arrives (relay SIGTERMs itself; systemd
  // brings the new version up). Caller should show "restarting…" UI and re-poll /admin/version
  // every 3 seconds for ~30 seconds until a different relay_version is reported.
  Future<Map<String, dynamic>> triggerRelayUpdate() async {
    final resp = await _http.post(Uri.parse('$baseUrl/admin/update'), headers: _headers);
    return _processResponse(resp, 'POST /admin/update') as Map<String, dynamic>;
  }
}
