// sealed_box.dart — NaCl sealed_box for method-3 credentials (RELAY-REMOTE-HAND
// -PLAN.md §10.1). TLS terminates at HAProxy, so the Google password must be
// sealed at the application layer to an ephemeral key only the relay sidecar
// holds. This produces the base64 ciphertext Flutter puts in rh_input.sealed;
// the sidecar opens it with rh_crypto.py (PyNaCl SealedBox) — interop-verified.
import 'dart:convert';

import 'package:pinenacl/x25519.dart';

/// Seals [obj] as JSON to a relay session public key (base64 X25519), returning
/// a base64 NaCl sealed_box. Only the holder of the matching private key (the
/// per-session sidecar) can open it — HAProxy/hub see ciphertext only.
String sealJsonToPubkey(String pubkeyBase64, Map<String, dynamic> obj) {
  final pk = PublicKey(base64.decode(pubkeyBase64));
  final sealed = SealedBox(pk).encrypt(utf8.encode(jsonEncode(obj)));
  return base64.encode(sealed);
}
