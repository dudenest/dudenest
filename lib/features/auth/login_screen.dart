import 'package:flutter/material.dart';
import '../../core/auth/auth_service.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  static const _version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(
          '$_version · © ${DateTime.now().year} Dudenest',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.cloud_done, size: 64, color: scheme.primary),
                const SizedBox(height: 16),
                Text('Dudenest', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Private encrypted cloud storage', textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 48),
                _OAuthButton(
                  label: 'Continue with Google',
                  icon: _GoogleIcon(),
                  onTap: () => AuthService().signInWith('google'),
                ),
                const SizedBox(height: 12),
                _OAuthButton(
                  label: 'Continue with GitHub',
                  icon: const Icon(Icons.code, size: 20),
                  onTap: () => AuthService().signInWith('github'),
                ),
                const SizedBox(height: 12),
                _OAuthButton(
                  label: 'Continue with Apple',
                  icon: const Icon(Icons.apple, size: 20),
                  onTap: () => AuthService().signInWith('apple'),
                ),
                const SizedBox(height: 32),
                Text(
                  'By signing in you agree to the Terms of Service.\nYour files are stored encrypted across multiple providers.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OAuthButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  const _OAuthButton({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: scheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        icon,
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

// Simple Google "G" logo using colored text
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text('G', style: TextStyle(
      fontSize: 18, fontWeight: FontWeight.bold,
      color: Color(0xFF4285F4), // Google blue
    ));
  }
}
