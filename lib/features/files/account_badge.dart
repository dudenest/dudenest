import 'package:flutter/material.dart';

/// Mały „pill" na kafelku galerii pokazujący, z KTÓREGO konta direct pochodzi plik (multi-konto MP1b).
/// Etykieta = email wyłuskany z `account_id` (`provider:email`). Renderowany jako [Positioned], więc musi
/// być bezpośrednim dzieckiem [Stack]. Gdy plik nie ma `account_id` (ścieżka relay) → nic nie pokazuje.
class AccountBadge extends StatelessWidget {
  final Map<String, dynamic> file;
  const AccountBadge({super.key, required this.file});

  /// Email do pokazania z `account_id` (`provider:email`) — część po pierwszym `:`. Null gdy brak konta.
  static String? labelFor(Map<String, dynamic> file) {
    final acc = file['account_id'] as String?;
    if (acc == null || acc.isEmpty) return null;
    final i = acc.indexOf(':');
    final email = i >= 0 ? acc.substring(i + 1) : acc;
    return email.isEmpty ? null : email;
  }

  @override
  Widget build(BuildContext context) {
    final label = labelFor(file);
    if (label == null) return const SizedBox.shrink();
    return Positioned(
      left: 3,
      right: 3,
      bottom: 3,
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }
}
