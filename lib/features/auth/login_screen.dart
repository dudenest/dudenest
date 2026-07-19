import 'package:flutter/material.dart';
// font_awesome_flutter removed — see main.dart for rationale (Dart 3 final-class regression).
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth/auth_service.dart';
import '../../core/auth/web_utils.dart';
import 'starfield_background.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});
  static const _version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

  @override
  Widget build(BuildContext context) {
    return StarfieldBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.only(bottom: 20, top: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _SocialIconButton(icon: Icons.code,
                  url: 'https://github.com/dudenest/dudenest', tooltip: 'GitHub'),
              const SizedBox(width: 16),
              _SocialIconButton(icon: Icons.forum,
                  url: 'https://discord.gg/pYjR9jS4', tooltip: 'Discord'),
            ]),
            const SizedBox(height: 4),
            Text('$_version · © ${DateTime.now().year} Dudenest',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF4A6080), fontSize: 12)),
          ]),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.cloud_done, size: 64, color: Color(0xFF7090D0)),
                    const SizedBox(height: 16),
                    const Text('Dudenest', textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 8),
                    const Text('Private encrypted cloud storage', textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF7090A8), fontSize: 14)),
                    const SizedBox(height: 48),
                    _OAuthButton(label: 'Login with Google', icon: _GoogleIcon(),
                        onTap: () => AuthService().signInWith('google')),
                    const SizedBox(height: 12),
                    _OAuthButton(label: 'Login with GitHub',
                        icon: const Icon(Icons.code, size: 20, color: Color(0xFFB0C4DE)),
                        onTap: () => AuthService().signInWith('github')),
                    const SizedBox(height: 12),
                    _OAuthButton(label: 'Login with Apple',
                        icon: const Icon(Icons.apple, size: 20, color: Color(0xFFB0C4DE)),
                        onTap: () => AuthService().signInWith('apple')),
                    const SizedBox(height: 24),
                    const _TryDemoButton(),
                    const SizedBox(height: 24),
                    const Text(
                      'By signing in you agree to the Terms of Service.\nYour files are stored encrypted across multiple providers.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF4A6080), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// "Try DEMO" — POSTs /auth/demo, then reloads so the app root rebuilds logged-in
// (mirrors the OAuth return). Shows a spinner while minting and a snackbar on failure.
class _TryDemoButton extends StatefulWidget {
  const _TryDemoButton();
  @override
  State<_TryDemoButton> createState() => _TryDemoButtonState();
}

class _TryDemoButtonState extends State<_TryDemoButton> {
  bool _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await AuthService().signInDemo();
      setLocationHref(getLocationHref().split('?').first.split('#').first); // reload → logged in
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demo is unavailable right now — please try again later.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _busy ? null : _go,
      icon: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF34C759)))
          : const Icon(Icons.play_circle_outline, size: 20, color: Color(0xFF34C759)),
      label: const Text('Try DEMO — no sign-in needed',
          style: TextStyle(color: Color(0xFF34C759), fontWeight: FontWeight.w600)),
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
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: const BorderSide(color: Color(0xFF2A3A5A)),
        backgroundColor: const Color(0x22304060),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        icon,
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, color: Color(0xFFCCDDFF))),
      ]),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF4285F4)));
  }
}

class _SocialIconButton extends StatelessWidget {
  final IconData icon;
  final String url;
  final String tooltip;
  const _SocialIconButton({required this.icon, required this.url, required this.tooltip});
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18, color: const Color(0xFF4A6080)),
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    );
  }
}
