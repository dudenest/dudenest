import 'package:flutter/material.dart';
import '../../core/storage/direct_account.dart';

/// DirectAccountsScreen — zarządzanie kontami trybu direct (MP1b, bez relaya). Analog relayowego
/// „Cloud Accounts" (`accounts_screen.dart`), ale mówi do backendu `directauth` przez [AccountsService]:
/// listuje konta usera, dodaje konto Google (pełnostronicowy redirect zgody), usuwa konto.
///
/// [service] jest WSTRZYKIWANY (szew testowy) — domyślnie realny [AccountsService] (JWT z SharedPreferences,
/// redirect przeglądarki). W testach wstrzykuje się serwis z fake http + przechwyconym redirectem.
class DirectAccountsScreen extends StatefulWidget {
  final AccountsService? service;
  const DirectAccountsScreen({super.key, this.service});
  @override
  State<DirectAccountsScreen> createState() => _DirectAccountsScreenState();
}

class _DirectAccountsScreenState extends State<DirectAccountsScreen> {
  late final AccountsService _svc;
  List<DirectAccount>? _accounts;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _svc = widget.service ?? AccountsService();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final a = await _svc.list();
      if (!mounted) return;
      setState(() { _accounts = a; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  // Dodanie konta = pełnostronicowy REDIRECT do zgody Google (strona odchodzi; po powrocie lista się
  // przeładuje z nowym kontem). W teście redirect jest wstrzyknięty (no-op) → wołanie jest przechwytywalne.
  Future<void> _addGoogle() async {
    try {
      await _svc.connect(provider: 'google');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start Google sign-in: $e')));
    }
  }

  Future<void> _remove(DirectAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove account'),
        content: Text('Remove ${a.email}? Files stay in Google Drive; Dudenest just stops accessing them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      await _svc.remove(a.accountId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Removed ${a.email}.')));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Accounts'), actions: [
          if (_accounts != null)
            IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _loading ? null : _load),
        ]),
        body: _body(),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _loading ? null : _addGoogle,
          icon: const Icon(Icons.add),
          label: const Text('Add Google account'),
        ),
      );

  Widget _body() {
    if (_loading && _accounts == null) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorState();
    final accounts = _accounts;
    if (accounts == null) return const SizedBox.shrink();
    if (accounts.isEmpty) return _emptyState();
    return ListView.separated(
      itemCount: accounts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final a = accounts[i];
        return ListTile(
          leading: const Icon(Icons.cloud_done, color: Colors.green),
          title: Text(a.email),
          subtitle: Text(a.provider), // MP1: 'google'; MP2+ onedrive/dropbox
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Remove',
            onPressed: _loading ? null : () => _remove(a),
          ),
        );
      },
    );
  }

  Widget _emptyState() => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40, color: Colors.grey),
            SizedBox(height: 12),
            Text('No Google accounts connected yet.\nTap “Add Google account” to connect one.',
                textAlign: TextAlign.center),
          ]),
        ),
      );

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.orangeAccent, size: 40),
            const SizedBox(height: 12),
            Text('Could not load accounts.\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ]),
        ),
      );
}
