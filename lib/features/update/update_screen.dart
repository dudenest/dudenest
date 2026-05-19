// update_screen.dart — surfaces every component's running version + latest release + one-click relay update.
//
// Three cards in a list:
//   1. Dudenest App (web bundle) — built APP_VERSION + repo + changelog links. No "Update" button —
//      the web app refreshes itself on next page load whenever CI ships a new bundle.
//   2. Dudenest Relay — calls GET /admin/version on the paired relay. If a newer GitHub release
//      exists, shows an "Update Now" button that POSTs /admin/update; the screen then polls
//      /admin/version every 3 s until relay_version changes (or 60 s timeout → "still restarting?").
//   3. Dudenest Backend — repo + changelog links only (backend version-introspection endpoint is a
//      future enhancement; users mostly care about app + relay versions).
//
// Reached from Settings (P3 nav: bottom tabs are Photos | Files | Upload | Settings, no separate Update tab).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/network/relay_client.dart';

class UpdateScreen extends StatefulWidget {
  final RelayClient relay;
  const UpdateScreen({super.key, required this.relay});
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> {
  static const _appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  Map<String, dynamic>? _relayInfo;
  String? _relayError;
  bool _refreshing = false;
  bool _updating = false;
  String? _updateMessage;
  Timer? _postUpdatePoll;

  @override
  void initState() { super.initState(); _refresh(); }

  @override
  void dispose() { _postUpdatePoll?.cancel(); super.dispose(); }

  Future<void> _refresh() async {
    setState(() { _refreshing = true; _relayError = null; });
    try {
      final info = await widget.relay.getRelayVersionInfo();
      if (mounted) setState(() { _relayInfo = info; _refreshing = false; });
    } catch (e) {
      if (mounted) setState(() { _relayError = e.toString(); _refreshing = false; });
    }
  }

  Future<void> _triggerUpdate() async {
    if (_updating) return;
    setState(() { _updating = true; _updateMessage = 'Triggering relay update…'; });
    try {
      final res = await widget.relay.triggerRelayUpdate();
      final status = res['status'] as String? ?? 'unknown';
      final to = res['to_version'] as String? ?? '';
      setState(() { _updateMessage = status == 'already_up_to_date'
          ? 'Already on latest release.'
          : 'Relay restarting to $to — polling status…'; });
      if (status == 'updating') _startPostUpdatePoll(to);
      else setState(() => _updating = false);
    } catch (e) {
      // POST /admin/update may close the connection mid-response when SIGTERM hits — treat as success
      // and start polling. Only true failures (404, 500, etc.) bubble up here as RelayException.
      if (e is RelayException && (e.statusCode == null || e.statusCode == 200)) {
        setState(() => _updateMessage = 'Relay restarting — polling status…');
        _startPostUpdatePoll(null);
      } else {
        setState(() { _updateMessage = 'Update failed: $e'; _updating = false; });
      }
    }
  }

  void _startPostUpdatePoll(String? targetVersion) {
    final originalVersion = (_relayInfo?['relay_version'] as String?) ?? '';
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    _postUpdatePoll?.cancel();
    _postUpdatePoll = Timer.periodic(const Duration(seconds: 3), (t) async {
      if (DateTime.now().isAfter(deadline)) {
        t.cancel();
        if (mounted) setState(() { _updateMessage = 'Timeout — relay still on $originalVersion. Check service status manually.'; _updating = false; });
        return;
      }
      try {
        final info = await widget.relay.getRelayVersionInfo();
        final newVersion = info['relay_version'] as String? ?? '';
        if (newVersion != originalVersion) {
          t.cancel();
          if (mounted) setState(() { _relayInfo = info; _updateMessage = '✅ Relay now on $newVersion'; _updating = false; });
        }
      } catch (_) {
        // Connection refused during restart window — keep polling.
      }
    });
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Updates'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _refreshing ? null : _refresh),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _AppCard(version: _appVersion, onOpen: _open),
        const SizedBox(height: 12),
        _RelayCard(
          info: _relayInfo,
          error: _relayError,
          refreshing: _refreshing,
          updating: _updating,
          updateMessage: _updateMessage,
          onUpdate: _triggerUpdate,
          onOpen: _open,
        ),
        const SizedBox(height: 12),
        _BackendCard(onOpen: _open),
      ]),
    );
  }
}

// ─── Dudenest App card ───────────────────────────────────────────────────────

class _AppCard extends StatelessWidget {
  final String version;
  final ValueChanged<String> onOpen;
  const _AppCard({required this.version, required this.onOpen});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.phone_iphone, size: 28),
            const SizedBox(width: 12),
            Text('Dudenest App', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 12),
          _kv('Current version', version),
          const SizedBox(height: 4),
          Text('Web app auto-updates on the next page load whenever CI ships a new bundle.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            TextButton.icon(icon: const Icon(Icons.code, size: 16), label: const Text('Repository'),
                onPressed: () => onOpen('https://github.com/dudenest/dudenest')),
            TextButton.icon(icon: const Icon(Icons.description_outlined, size: 16), label: const Text('Changelog'),
                onPressed: () => onOpen('https://github.com/dudenest/dudenest/blob/main/CHANGELOG.md')),
            TextButton.icon(icon: const Icon(Icons.local_offer_outlined, size: 16), label: const Text('Releases'),
                onPressed: () => onOpen('https://github.com/dudenest/dudenest/releases')),
          ]),
        ]),
      ),
    );
  }
}

// ─── Dudenest Relay card ─────────────────────────────────────────────────────

class _RelayCard extends StatelessWidget {
  final Map<String, dynamic>? info;
  final String? error;
  final bool refreshing;
  final bool updating;
  final String? updateMessage;
  final VoidCallback onUpdate;
  final ValueChanged<String> onOpen;
  const _RelayCard({
    required this.info, required this.error, required this.refreshing,
    required this.updating, required this.updateMessage,
    required this.onUpdate, required this.onOpen,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final relayVersion = info?['relay_version'] as String? ?? '—';
    final latest = info?['latest_release'] as String? ?? '';
    final updateAvailable = info?['update_available'] as bool? ?? false;
    final repoUrl = info?['repo_url'] as String? ?? 'https://github.com/dudenest/dudenest-relay';
    final releaseUrl = info?['release_url'] as String? ?? 'https://github.com/dudenest/dudenest-relay/releases/latest';
    final changelogUrl = info?['changelog_url'] as String? ?? 'https://github.com/dudenest/dudenest-relay/blob/main/CHANGELOG.md';
    final fetchError = info?['fetch_error'] as String? ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.dns_outlined, size: 28),
            const SizedBox(width: 12),
            Text('Dudenest Relay', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            if (refreshing) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: 12),
          if (error != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.red.withOpacity(0.08), borderRadius: BorderRadius.circular(4)),
              child: Text('Could not reach /admin/version — older relay (<v0.12.0)? $error',
                  style: const TextStyle(fontSize: 12, color: Colors.red)),
            )
          else ...[
            _kv('Current version', relayVersion),
            const SizedBox(height: 4),
            _kv('Latest release', latest.isEmpty ? '(failed to fetch)' : latest),
            if (fetchError.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('GitHub fetch error: $fetchError', style: const TextStyle(fontSize: 11, color: Colors.orange)),
            ],
            const SizedBox(height: 8),
            if (updateAvailable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
                child: Text('Update available', style: TextStyle(color: scheme.onPrimaryContainer, fontSize: 12, fontWeight: FontWeight.bold)),
              )
            else if (latest.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: const Text('Up to date', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            TextButton.icon(icon: const Icon(Icons.code, size: 16), label: const Text('Repository'), onPressed: () => onOpen(repoUrl)),
            TextButton.icon(icon: const Icon(Icons.description_outlined, size: 16), label: const Text('Changelog'), onPressed: () => onOpen(changelogUrl)),
            TextButton.icon(icon: const Icon(Icons.local_offer_outlined, size: 16), label: const Text('Release'), onPressed: () => onOpen(releaseUrl)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton.icon(
              icon: updating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.system_update),
              label: Text(updating ? 'Updating…' : 'Update Relay Now'),
              onPressed: (updating || refreshing || error != null) ? null : onUpdate,
            ),
          ]),
          if (updateMessage != null) ...[
            const SizedBox(height: 8),
            Text(updateMessage!, style: const TextStyle(fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}

// ─── Dudenest Backend card ───────────────────────────────────────────────────

class _BackendCard extends StatelessWidget {
  final ValueChanged<String> onOpen;
  const _BackendCard({required this.onOpen});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.cloud_circle_outlined, size: 28),
            const SizedBox(width: 12),
            Text('Dudenest Backend', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 12),
          Text('Hub service (dudenest-backup) — version surfaced via /relay/bootstrap response in the future. For now: repository + changelog links only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            TextButton.icon(icon: const Icon(Icons.code, size: 16), label: const Text('Repository'),
                onPressed: () => onOpen('https://github.com/dudenest/dudenest-backup')),
            TextButton.icon(icon: const Icon(Icons.description_outlined, size: 16), label: const Text('Changelog'),
                onPressed: () => onOpen('https://github.com/dudenest/dudenest-backup/blob/main/CHANGELOG.md')),
          ]),
        ]),
      ),
    );
  }
}

Widget _kv(String k, String v) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 2),
  child: Row(children: [
    SizedBox(width: 130, child: Text(k, style: const TextStyle(color: Colors.grey, fontSize: 13))),
    Expanded(child: SelectableText(v, style: const TextStyle(fontFamily: 'monospace'))),
  ]),
);
