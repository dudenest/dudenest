// remote_hand.dart — method-3 (CDP-free mediated login) client state.
//
// The relay drives a vanilla Chromium and reads it visually; over /ws it sends a
// schema-driven form (rh_prompt) that this controller renders dynamically. The
// user types into native Flutter fields; sensitive fields (password, SMS code)
// are sealed to the relay's ephemeral pubkey (rh_hello) before leaving the device.
// See RELAY-REMOTE-HAND-PLAN.md §6/§7/§10.
import 'package:flutter/foundation.dart';

import '../crypto/sealed_box.dart';

/// Minimal transport RemoteHand needs — implemented by WsClient, faked in tests.
abstract class RhTransport {
  Stream<Map<String, dynamic>> get raw;
  void send(Map<String, dynamic> msg);
}

/// One field of a dynamically-rendered form.
class RhField {
  final String name;
  final String label; // copied verbatim from the real Google field
  final String kind; // text|password|tel|code|captcha_image
  final String value;
  final String hint;
  final bool sensitive; // true → sealed, never sent in cleartext

  const RhField({
    required this.name,
    required this.label,
    this.kind = 'text',
    this.value = '',
    this.hint = '',
    this.sensitive = false,
  });

  factory RhField.fromJson(Map<String, dynamic> j) => RhField(
        name: j['name'] as String? ?? '',
        label: j['label'] as String? ?? '',
        kind: j['kind'] as String? ?? 'text',
        value: j['value'] as String? ?? '',
        hint: j['hint'] as String? ?? '',
        sensitive: j['sensitive'] as bool? ?? false,
      );

  bool get obscure => kind == 'password' || kind == 'code';
}

/// A prompt asking the user to fill [fields]; [imageB64] carries a tightly-cropped
/// captcha challenge (§8.1) when [step] is a captcha step.
class RhPrompt {
  final String step;
  final String title;
  final List<RhField> fields;
  final String? imageB64;

  const RhPrompt({required this.step, required this.title, required this.fields, this.imageB64});

  factory RhPrompt.fromJson(Map<String, dynamic> j) => RhPrompt(
        step: j['step'] as String? ?? '',
        title: j['title'] as String? ?? '',
        fields: ((j['fields'] as List?) ?? const [])
            .map((f) => RhField.fromJson(f as Map<String, dynamic>))
            .toList(),
        imageB64: j['image'] as String?,
      );
}

enum RhStatus { connecting, working, needInput, success, error }

/// Drives one method-3 session: consumes rh_* frames, exposes the current prompt,
/// and seals+sends user input. UI listens via ChangeNotifier.
class RemoteHand extends ChangeNotifier {
  final RhTransport ws;
  final String sessionId;

  String? _pubkey; // relay session pubkey (rh_hello) — seal secrets to this
  RhPrompt? _prompt;
  RhStatus _status = RhStatus.connecting;
  String _message = '';

  RhPrompt? get prompt => _prompt;
  RhStatus get status => _status;
  String get message => _message;
  bool get ready => _pubkey != null;

  RemoteHand({required this.ws, required this.sessionId}) {
    ws.raw.listen(_onFrame);
  }

  void _onFrame(Map<String, dynamic> j) {
    if ((j['session_id'] as String?) != null && j['session_id'] != sessionId) return; // not ours
    switch (j['type'] as String? ?? '') {
      case 'rh_hello':
        _pubkey = j['relay_pubkey'] as String?;
        notifyListeners();
        break;
      case 'rh_prompt':
        _prompt = RhPrompt.fromJson(j);
        _status = RhStatus.needInput;
        notifyListeners();
        break;
      case 'rh_state':
        _status = switch (j['state'] as String? ?? '') {
          'working' => RhStatus.working,
          'need_input' => RhStatus.needInput,
          'success' => RhStatus.success,
          'error' => RhStatus.error,
          _ => _status,
        };
        _message = j['message'] as String? ?? '';
        notifyListeners();
        break;
    }
  }

  /// Seals sensitive values to the relay pubkey and sends rh_input for [step].
  /// Non-sensitive values go in cleartext (within TLS); secrets go in `sealed`.
  void submit(Map<String, String> values) {
    final p = _prompt;
    if (p == null) return;
    final sensitive = <String, String>{};
    final plain = <String, String>{};
    for (final f in p.fields) {
      final v = values[f.name];
      if (v == null) continue;
      (f.sensitive ? sensitive : plain)[f.name] = v;
    }
    final msg = <String, dynamic>{
      'type': 'rh_input',
      'session_id': sessionId,
      'step': p.step,
      'values': plain,
    };
    if (sensitive.isNotEmpty && _pubkey != null) {
      msg['sealed'] = sealJsonToPubkey(_pubkey!, sensitive);
    }
    ws.send(msg);
    _status = RhStatus.working;
    _prompt = null; // consumed; next prompt (or terminal state) will arrive
    notifyListeners();
  }
}
