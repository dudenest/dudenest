// remote_hand_form.dart — schema-driven form for method-3 (Relay-assisted login).
//
// Renders whatever fields the relay sends (rh_prompt): email+password first, then
// phone/SMS/captcha appear smoothly as new prompts without a screen change (§7).
// Secrets are sealed inside RemoteHand.submit before leaving the device.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/network/remote_hand.dart';
import '../../core/network/rh_validate.dart';

class RemoteHandForm extends StatefulWidget {
  final RemoteHand controller;
  final VoidCallback?
      onAddNext; // success → start another account (fresh relay session)
  final VoidCallback?
      onFinish; // success → close and return to the accounts list
  final String Function(String url)? resolveTakeoverUrl;
  final bool embedTakeoverWebView;
  const RemoteHandForm(
      {super.key,
      required this.controller,
      this.onAddNext,
      this.onFinish,
      this.resolveTakeoverUrl,
      this.embedTakeoverWebView = true});

  @override
  State<RemoteHandForm> createState() => _RemoteHandFormState();
}

class _RemoteHandFormState extends State<RemoteHandForm> {
  final _fieldCtrls = <String, TextEditingController>{};
  WebViewController? _takeoverCtrl;
  String? _takeoverLoaded;

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
            return _successView(c.message);
          case RhStatus.error:
            if (c.takeoverUrl != null) return _takeoverView(c, true);
            return _banner(
                Icons.error, Colors.red, 'Could not sign in', c.message);
          case RhStatus.working:
            if (c.takeoverUrl != null) return _takeoverView(c, false);
            return _workingView(c.message);
          case RhStatus.connecting:
            return _workingView(c.message);
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
          for (final f in p.fields) _fieldWidget(f, p, ready),
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

  String _resolvedTakeoverUrl(String url) =>
      widget.resolveTakeoverUrl?.call(url) ?? url;

  Widget _takeoverView(RemoteHand c, bool isError) {
    final url = _resolvedTakeoverUrl(c.takeoverUrl!);
    if (!kIsWeb && widget.embedTakeoverWebView && _takeoverLoaded != url) {
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse(url));
      _takeoverCtrl = ctrl;
      _takeoverLoaded = url;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(children: [
            Icon(isError ? Icons.warning_amber : Icons.visibility,
                color: isError ? Colors.orange : Colors.blue, size: 34),
            const SizedBox(height: 8),
            Text(
                isError
                    ? 'Human takeover needed'
                    : 'Google needs your attention',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            if (c.message.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(c.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey))),
          ])),
      if (!kIsWeb && widget.embedTakeoverWebView && _takeoverCtrl != null)
        SizedBox(height: 520, child: WebViewWidget(controller: _takeoverCtrl!))
      else
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FilledButton.icon(
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open live Google screen'),
              onPressed: () => launchUrl(Uri.parse(url),
                  mode: LaunchMode.externalApplication),
            )),
    ]);
  }

  // All visible fields pass client-side format validation → Continue enabled.
  bool _allValid(RhPrompt p) => p.fields
      .where((f) => f.kind != 'captcha_image')
      .every((f) => validateRhField(f.kind, _ctrlFor(f).text) == null);

  Widget _fieldWidget(RhField f, RhPrompt p, bool ready) {
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
        textInputAction: TextInputAction.done,
        onSubmitted: (_) {
          if (ready && _allValid(p)) _submit(p);
        },
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

  // Working state: an indeterminate bar sweeping across, so the wait (Chromium loads /
  // Google verifies) reads as active progress. The "submitting…" message tells the step.
  Widget _workingView(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(4)),
            child: SizedBox(height: 8, child: LinearProgressIndicator()),
          ),
          const SizedBox(height: 18),
          Text(message.isEmpty ? 'Working…' : message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: Colors.grey)),
        ]),
      );

  // Success: keep the connected account visible and offer the two next actions.
  Widget _successView(String email) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 12),
              const Text('Account connected',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              if (email.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: widget.onAddNext,
                icon: const Icon(Icons.add),
                label: const Text('Add Next Account'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: widget.onFinish,
                child: const Text('Finish'),
              ),
            ]),
      );

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
