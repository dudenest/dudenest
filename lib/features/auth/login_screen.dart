import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth/auth_service.dart';
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
              _SocialIconButton(icon: FontAwesomeIcons.github,
                  url: 'https://github.com/dudenest/dudenest', tooltip: 'GitHub'),
              const SizedBox(width: 16),
              _SocialIconButton(icon: FontAwesomeIcons.discord,
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
                    _OAuthButton(label: 'Continue with Google', icon: _GoogleIcon(),
                        onTap: () => AuthService().signInWith('google')),
                    const SizedBox(height: 12),
                    _OAuthButton(label: 'Continue with GitHub',
                        icon: const Icon(Icons.code, size: 20, color: Color(0xFFB0C4DE)),
                        onTap: () => AuthService().signInWith('github')),
                    const SizedBox(height: 12),
                    _OAuthButton(label: 'Continue with Apple',
                        icon: const Icon(Icons.apple, size: 20, color: Color(0xFFB0C4DE)),
                        onTap: () => AuthService().signInWith('apple')),
                    const SizedBox(height: 32),
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
        icon: FaIcon(icon, size: 18, color: const Color(0xFF4A6080)),
        onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    );
  }
}
