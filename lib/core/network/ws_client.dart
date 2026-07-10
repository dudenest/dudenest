// ws_client.dart — WebSocket client for persistent relay↔Flutter communication.
// Relay sends auth_request messages when it needs a new cloud account to be authorized.
// Flutter handles auth on user's device (user's IP ✅) and sends code to /auth/exchange.
import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'remote_hand.dart' show RhTransport; // WsClient satisfies RemoteHand's transport contract

/// Message types sent by relay via WebSocket.
enum WsMessageType { authRequest, authDone, authError, ping, unknown }

class WsMessage {
  final WsMessageType type;
  final String? provider;   // "gdrive"|"mega"|"onedrive"
  final String? requestId;  // correlates with /auth/exchange request_id
  final String? email;      // set on auth_done
  final String? error;      // set on auth_error
  const WsMessage({required this.type, this.provider, this.requestId, this.email, this.error});

  factory WsMessage.fromJson(Map<String, dynamic> j) {
    final t = switch (j['type'] as String? ?? '') {
      'auth_request' => WsMessageType.authRequest,
      'auth_done'    => WsMessageType.authDone,
      'auth_error'   => WsMessageType.authError,
      'ping'         => WsMessageType.ping,
      _              => WsMessageType.unknown,
    };
    return WsMessage(type: t, provider: j['provider'] as String?, requestId: j['request_id'] as String?, email: j['email'] as String?, error: j['error'] as String?);
  }
}

/// Persistent WebSocket connection to relay with auto-reconnect.
class WsClient implements RhTransport {
  final String baseUrl; // e.g. "https://relay.dudenest.com" or "http://10.71.0.1:8086"
  WebSocketChannel? _channel;
  final _ctrl = StreamController<WsMessage>.broadcast();
  final _raw = StreamController<Map<String, dynamic>>.broadcast();
  bool _disposed = false;
  Duration _retryDelay = const Duration(seconds: 3);

  WsClient(this.baseUrl);

  /// Stream of typed auth_* messages received from relay.
  Stream<WsMessage> get messages => _ctrl.stream;

  /// Stream of raw decoded JSON frames — used by Remote-Hand (method 3) whose
  /// rh_* messages carry dynamic form schemas the typed enum doesn't model.
  @override
  Stream<Map<String, dynamic>> get raw => _raw.stream;

  /// Sends a JSON frame to the relay (e.g. Remote-Hand rh_input).
  @override
  void send(Map<String, dynamic> msg) => _channel?.sink.add(jsonEncode(msg));

  /// Opens the WebSocket connection. Auto-reconnects on disconnect.
  void connect() {
    if (_disposed) return;
    final wsUrl = baseUrl.replaceFirst(RegExp(r'^https?'), baseUrl.startsWith('https') ? 'wss' : 'ws') + '/ws';
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _retryDelay = const Duration(seconds: 3); // reset backoff on successful connect
      _channel!.stream.listen(
        (data) {
          if (_disposed) return;
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _raw.add(json);                       // Remote-Hand consumes rh_* here
            _ctrl.add(WsMessage.fromJson(json));  // typed auth_* stream
          } catch (_) {} // ignore malformed messages
        },
        onDone: () { if (!_disposed) Future.delayed(_retryDelay, connect); },
        onError: (_) { if (!_disposed) Future.delayed(_retryDelay, connect); },
        cancelOnError: true,
      );
    } catch (_) {
      if (!_disposed) Future.delayed(_retryDelay, connect);
      final nextDelay = _retryDelay * 2;
      _retryDelay = nextDelay > const Duration(seconds: 30) ? const Duration(seconds: 30) : (nextDelay < const Duration(seconds: 3) ? const Duration(seconds: 3) : nextDelay);
    }
  }

  void dispose() {
    _disposed = true;
    _channel?.sink.close();
    _ctrl.close();
    _raw.close();
  }
}
