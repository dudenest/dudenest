// rh_validate.dart — client-side (format-only) validation for method-3 fields.
//
// Catches obviously-malformed input BEFORE it reaches the relay, so the sidecar
// never types garbage into Google and the user gets instant feedback. This is
// FORMAT validation only — correctness (is the password right?) is decided by
// Google server-side. Pure functions → unit-testable, no Flutter dependency.

/// Returns an error message for [value] under field [kind], or null if valid.
/// [kind]: text (login = email or phone) | password | tel | code | captcha_image.
String? validateRhField(String kind, String value) {
  // Passwords may contain leading/trailing spaces and any characters — never trim.
  if (kind == 'password') {
    return value.isEmpty ? 'Enter your password' : null;
  }
  final v = value.trim();
  if (v.isEmpty) return 'Required';
  switch (kind) {
    case 'tel':
      return _validatePhone(v);
    case 'code':
      return _validateCode(v);
    case 'text': // Google login accepts an email OR a phone
      final looksPhone = RegExp(r'^\+?[\d\s\-()]+$').hasMatch(v) && !v.contains('@');
      return looksPhone ? _validatePhone(v) : validateEmail(v);
    default:
      return null; // captcha_image etc. — only non-empty (checked above)
  }
}

/// Email format per the fields the user flagged: single @, starts with a letter,
/// no spaces, allowed chars, domain with a dot.
String? validateEmail(String v) {
  if (v.contains(' ')) return 'No spaces allowed';
  final at = v.indexOf('@');
  if (at <= 0 || v.indexOf('@', at + 1) != -1) return 'Enter a valid email (one @)';
  final local = v.substring(0, at);
  final domain = v.substring(at + 1);
  if (!RegExp(r'^[A-Za-z]').hasMatch(local)) return 'Email must start with a letter';
  if (!RegExp(r'^[A-Za-z0-9._%+\-]+$').hasMatch(local)) return 'Invalid characters in email';
  if (domain.isEmpty || !domain.contains('.')) return 'Email domain must include a dot';
  if (!RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(domain)) return 'Invalid characters in domain';
  if (domain.startsWith('.') || domain.endsWith('.') || domain.startsWith('-') || domain.endsWith('-')) {
    return 'Invalid domain';
  }
  if (domain.contains('..')) return 'Invalid domain';
  return null;
}

String? _validatePhone(String v) {
  final digits = v.replaceAll(RegExp(r'[\s\-()]'), '');
  if (!RegExp(r'^\+?\d+$').hasMatch(digits)) return 'Digits only (with country code, e.g. +48…)';
  final bare = digits.startsWith('+') ? digits.substring(1) : digits;
  if (bare.length < 7 || bare.length > 15) return 'Enter a valid phone number with country code';
  return null;
}

String? _validateCode(String v) {
  final d = v.replaceAll(RegExp(r'\s'), '');
  if (!RegExp(r'^\d+$').hasMatch(d)) return 'Code must be digits only';
  if (d.length < 6) return 'Code is too short';
  if (d.length > 8) return 'Code is too long';
  return null;
}
