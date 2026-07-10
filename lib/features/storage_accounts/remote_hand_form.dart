// remote_hand_form.dart — schema-driven form for method-3 (Relay-assisted login).
//
// Renders whatever fields the relay sends (rh_prompt): email+password first, then
// phone/SMS/captcha appear smoothly as new prompts without a screen change (§7).
// Secrets are sealed inside RemoteHand.submit before leaving the device.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/remote_hand.dart';
import '../../core/network/rh_validate.dart';

class RemoteHandForm extends StatefulWidget {
  final RemoteHand controller;
  const RemoteHandForm({super.key, required this.controller});

  @override
  State<RemoteHandForm> createState() => _RemoteHandFormState();
}

class _RemoteHandFormState extends State<RemoteHandForm> {
  final _fieldCtrls = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrlFor(RhField f) => _fieldCtrls.putIfAbsent(
      f.name, () => TextEditingController(text: f.value));

  void _submit(RhPrompt prompt) {
    final values = {for (final f in prompt.fields) f.name: _ctrlFor(f).text};
    widget.controller.submit(values);
    for (final f in prompt.fields) {
      if (f.sensitive)
        _ctrlFor(f).clear(); // don't retain secrets in the widget
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final c = widget.controller;
        switch (c.status) {
          case RhStatus.success:
            return _banner(Icons.check_circle, Colors.green,
                'Account connected', c.message);
          case RhStatus.error:
            return _banner(
                Icons.error, Colors.red, 'Could not sign in', c.message);
          case RhStatus.working:
          case RhStatus.connecting:
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Working…'),
              ]),
            );
          case RhStatus.needInput:
            final p = c.prompt;
            if (p == null) return const SizedBox.shrink();
            return _promptForm(p, c.ready);
        }
      },
    );
  }

  Widget _promptForm(RhPrompt p, bool ready) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(p.title,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: p.isWarning ? Colors.red : null)),
          const SizedBox(height: 16),
          if (p.imageB64 != null) ...[
            // §8.1: tightly-cropped challenge — fills the view, not a speck on empty space
            Image.memory(base64Decode(p.imageB64!), fit: BoxFit.contain),
            const SizedBox(height: 16),
          ],
          for (final f in p.fields) _fieldWidget(f),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (ready && _allValid(p)) ? () => _submit(p) : null,
            child: const Text('Continue'),
          ),
          if (!ready)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Establishing secure channel…',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  // All visible fields pass client-side format validation → Continue enabled.
  bool _allValid(RhPrompt p) => p.fields
      .where((f) => f.kind != 'captcha_image')
      .every((f) => validateRhField(f.kind, _ctrlFor(f).text) == null);

  Widget _fieldWidget(RhField f) {
    if (f.kind == 'captcha_image')
      return const SizedBox.shrink(); // image already shown above
    final text = _ctrlFor(f).text;
    // Show the format error only once the user has typed (don't shout 'Required' on an empty field).
    final error = text.isEmpty ? null : validateRhField(f.kind, text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrlFor(f),
        obscureText: f.obscure,
        inputFormatters: _inputFormattersFor(f),
        onChanged: (_) => setState(() {}), // re-validate + re-gate Continue
        keyboardType: f.kind == 'tel'
            ? TextInputType.phone
            : (f.kind == 'code' ? TextInputType.number : TextInputType.text),
        decoration: InputDecoration(
          labelText: f.label,
          helperText: f.hint.isEmpty ? null : f.hint,
          errorText: error,
          border: const OutlineInputBorder(),
          suffixIcon: f.sensitive ? const Icon(Icons.lock, size: 18) : null,
        ),
      ),
    );
  }

  List<TextInputFormatter>? _inputFormattersFor(RhField f) {
    if (f.kind == 'password' || f.kind == 'text')
      return [FilteringTextInputFormatter.deny(RegExp(r'\s'))];
    return null;
  }

  Widget _banner(IconData icon, Color color, String title, String msg) =>
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(height: 12),
          Text(title,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey)),
            ),
        ]),
      );
}
