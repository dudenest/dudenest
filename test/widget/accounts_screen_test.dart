import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/features/storage_accounts/accounts_screen.dart';

RelayClient _relay(MockClientHandler h) =>
    RelayClient('http://relay.test', client: MockClient(h));

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows loading indicator initially', (tester) async {
    final completer = Completer<http.Response>();
    final relay = RelayClient('http://relay.test',
        client: MockClient((_) => completer.future));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    completer.complete(http.Response('{"providers":[]}', 200,
        headers: {'content-type': 'application/json'}));
    await tester.pump();
  });

  testWidgets('shows empty state when no providers', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': []}), 200,
        headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump(); // Start loading
    await tester.pump(); // Finish loading
    expect(find.text('No storage accounts'), findsOneWidget);
    expect(find.text('Add Account'), findsWidgets);
  });

  testWidgets('shows provider list on success', (tester) async {
    final relay = _relay((_) async => http.Response(
        jsonEncode({'providers': [
          {'id': 'gdrive_1', 'email': 'user@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.2, 'available': true, 'type': 'gdrive'}
        ]}), 200, headers: {'content-type': 'application/json'}));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump();
    await tester.pump();
    expect(find.text('user@gmail.com'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('shows error on relay failure', (tester) async {
    final relay = _relay((_) async => http.Response('error', 503));
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('Error:'), findsOneWidget);
    expect(find.textContaining('Status Code: 503'), findsOneWidget);
  });

  testWidgets('FAB opens Add Account sheet', (tester) async {
    final relay = _relay((req) async {
      if (req.url.path == '/providers') return http.Response('{"providers":[]}', 200, headers: {'content-type': 'application/json'});
      return http.Response('error', 404);
    });
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); // start animation
    await tester.pump(const Duration(seconds: 1)); // wait for sheet
    expect(find.text('Add Storage Account'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('MEGA.nz'), findsOneWidget);
  });

  testWidgets('Add Account sheet shows method selection after provider pick', (tester) async {
    final relay = _relay((req) async {
      return http.Response('{"providers":[]}', 200, headers: {'content-type': 'application/json'});
    });
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump(); await tester.pump();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Google Drive'));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    expect(find.text('Login Method'), findsOneWidget);
    expect(find.text('Login via your browser'), findsOneWidget);
    expect(find.text('Relay browser (automated)'), findsOneWidget);
  });

  testWidgets('Method E credentials form shows email/password/phone fields', (tester) async {
    final relay = _relay((req) async {
      return http.Response('{"providers":[]}', 200, headers: {'content-type': 'application/json'});
    });
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump(); await tester.pump();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Google Drive'));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    expect(find.text('Auto-fill in app'), findsOneWidget);
    await tester.tap(find.text('Auto-fill in app'));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    expect(find.text('Enter Credentials'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Phone (for 2FA, optional)'), findsOneWidget);
  });

  // s329 regression pin: ReorderableListView with explicit drag handle MUST render whenever
  // /admin/accounts returns at least one account. Pre-fix the canReorder gate had a second clause
  // requiring `sortedProviders.any(_adminFor(p) != null)` which empirically evaluated false on
  // desktop Chrome/Safari/Firefox, silently falling through to a plain ListView (no drag handle,
  // no Reorder semantic node, no way to change Priority). Verified empirically against prcznsk@
  // production session 2026-05-30: 4 providers + 3 admin accounts but no drag handle visible.
  testWidgets('s329: drag handle renders when admin accounts are loaded (desktop Chrome regression)', (tester) async {
    final relay = _relay((req) async {
      if (req.url.path == '/providers') {
        return http.Response(jsonEncode({'providers': [
          {'id': 'gdrive_1', 'email': 'a@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.0, 'available': true, 'type': 'gdrive', 'file_count': 10},
          {'id': 'gdrive_2', 'email': 'b@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.0, 'available': true, 'type': 'gdrive', 'file_count': 10},
          {'id': 'gdrive_3', 'email': 'orphan@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 0.0, 'available': false, 'type': 'gdrive', 'file_count': 0, 'last_error': 'Token revoked'},
        ]}), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/admin/accounts') {
        return http.Response(jsonEncode({
          'accounts': [
            {'id': 1, 'provider': 'gdrive', 'email': 'a@gmail.com', 'role': 'primary_write', 'priority': 0, 'status': 'active', 'quota_used_bytes': 1000000000, 'quota_total_bytes': 16000000000},
            {'id': 2, 'provider': 'gdrive', 'email': 'b@gmail.com', 'role': 'replica_write', 'priority': 1, 'status': 'active', 'quota_used_bytes': 1000000000, 'quota_total_bytes': 16000000000},
          ],
          'policy': {'replication_factor': 2, 'diversity_required': false, 'soft_cap_default_pct': 90, 'hard_cap_default_pct': 98, 'age_based_rotation': false},
        }), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/admin/scan/status') {
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('not found', 404);
    });
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump(); await tester.pump(); await tester.pump(const Duration(milliseconds: 200));
    // 1) ReorderableListView must be the chosen container — not plain ListView. This is the
    //    SINGLE most important assertion: if it ever silently degrades again, this test fails.
    expect(find.byType(ReorderableListView), findsOneWidget,
        reason: 's329 regression: admin accounts loaded but ReorderableListView not rendered — canReorder gate failed');
    // 2) s329 fix #3 (final): buildDefaultDragHandles must be FALSE so each tile uses our custom
    //    ReorderableDragStartListener wrapper (immediate mouse-down=drag on web), with the visual
    //    cue painted by _DragHandleHamburger (pure Container — no Material Icons font dependency).
    final rlv = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    expect(rlv.buildDefaultDragHandles, isFalse,
        reason: 's329 #3: defaults require long-press on web; custom ReorderableDragStartListener wraps each admin tile for mouse-down=drag');
    // 3) Each admin-matched tile must be wrapped in a ReorderableDragStartListener (a@, b@ — 2 wrappers).
    //    Orphan tile (orphan@) skips the wrapper (KeyedSubtree fallback) so it cannot be dragged into payload.
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(2),
        reason: 's329 #3: 2 admin tiles must each have ReorderableDragStartListener wrapping the Card');
  });

  // (Hamburger pure-paint widget existence is implicitly covered by the ReorderableDragStartListener
  // wrapping pin above — each admin tile is wrapped, and the tile body always paints the cue inside.
  // A dedicated paint-pin would be too brittle to Flutter's internal Container shape.)

  // s329 regression pin: onReorder must filter out providers without admin id BEFORE sending
  // the payload to relay. Tests the "newIDs.isEmpty → early return" guard added in the same fix.
  testWidgets('s329: onReorder filters orphan providers and sends only known admin ids', (tester) async {
    final reorderPayloads = <List<dynamic>>[];
    final relay = _relay((req) async {
      if (req.url.path == '/providers') {
        return http.Response(jsonEncode({'providers': [
          {'id': 'gdrive_1', 'email': 'a@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.0, 'available': true, 'type': 'gdrive', 'file_count': 10},
          {'id': 'gdrive_2', 'email': 'b@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.0, 'available': true, 'type': 'gdrive', 'file_count': 10},
        ]}), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/admin/accounts' && req.method == 'GET') {
        return http.Response(jsonEncode({
          'accounts': [
            {'id': 1, 'provider': 'gdrive', 'email': 'a@gmail.com', 'role': 'primary_write', 'priority': 0, 'status': 'active'},
            {'id': 2, 'provider': 'gdrive', 'email': 'b@gmail.com', 'role': 'replica_write', 'priority': 1, 'status': 'active'},
          ],
          'policy': {},
        }), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/admin/accounts/reorder' && req.method == 'POST') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        reorderPayloads.add(body['ids'] as List<dynamic>);
        return http.Response(jsonEncode({'status': 'ok', 'accounts': []}), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/admin/scan/status') {
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }
      return http.Response('not found', 404);
    });
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump(); await tester.pump(); await tester.pump(const Duration(milliseconds: 200));
    // Find the ReorderableListView and trigger a programmatic reorder (swap 0↔1).
    final rlv = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    rlv.onReorder!(0, 2); // move idx 0 to after idx 1 (Flutter quirk: newIdx=length means "to end")
    await tester.pump(); await tester.pump();
    // The first reorder triggers a follow-up GET /admin/accounts via _load() — payload was sent BEFORE that.
    expect(reorderPayloads.length, greaterThanOrEqualTo(1),
        reason: 's329: reorder POST should fire once for the swap');
    expect(reorderPayloads.first, [2, 1],
        reason: 's329: ids must be ints in new order; would have hit relay HTTP 400 pre-fix');
  });

  testWidgets('Method E Continue button disabled without email', (tester) async {
    final relay = _relay((req) async {
      return http.Response('{"providers":[]}', 200, headers: {'content-type': 'application/json'});
    });
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump(); await tester.pump();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Google Drive'));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Auto-fill in app'));
    await tester.pump(); await tester.pump(const Duration(seconds: 1));
    final continueBtn = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Continue').last
    );
    expect(continueBtn.onPressed, isNull);
  });

  // s329 #C+D regression pin: badge row replaces "Priority N" with "Nth choice" (1-based ordinal)
  // + Active/Standby slot derived from priority < replication_factor. priority=0 + role=primary_write
  // → "1st choice" with ⭐ icon + "Active" chip. priority=2 with RF=2 → "3rd choice" + "Standby".
  // Reason: user feedback 2026-05-30 — "Priority 0/1/2 is unintuitive". Verified empirically.
  testWidgets('s329 #C+D: badge row shows ordinal choice + Active/Standby slot', (tester) async {
    // Tall surface so all 3 tiles fit in viewport (otherwise Sliver lazy-build skips offscreen text).
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final relay = _relay((req) async {
      if (req.url.path == '/providers') {
        return http.Response(jsonEncode({'providers': [
          {'id': 'gdrive_1', 'email': 'a@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.0, 'available': true, 'type': 'gdrive', 'file_count': 10},
          {'id': 'gdrive_2', 'email': 'b@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.0, 'available': true, 'type': 'gdrive', 'file_count': 10},
          {'id': 'gdrive_3', 'email': 'c@gmail.com', 'quota_total_gb': 15.0, 'quota_used_gb': 1.0, 'available': true, 'type': 'gdrive', 'file_count': 10},
        ]}), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/admin/accounts') {
        return http.Response(jsonEncode({
          'accounts': [
            {'id': 1, 'provider': 'gdrive', 'email': 'a@gmail.com', 'role': 'primary_write', 'priority': 0, 'status': 'active'},
            {'id': 2, 'provider': 'gdrive', 'email': 'b@gmail.com', 'role': 'replica_write', 'priority': 1, 'status': 'active'},
            {'id': 3, 'provider': 'gdrive', 'email': 'c@gmail.com', 'role': 'replica_write', 'priority': 2, 'status': 'active'},
          ],
          'policy': {'replication_factor': 2}, // RF=2 → priorities 0,1 = Active; priority 2 = Standby
        }), 200, headers: {'content-type': 'application/json'});
      }
      if (req.url.path == '/admin/scan/status') return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      return http.Response('not found', 404);
    });
    await tester.pumpWidget(_wrap(AccountsScreen(relay: relay)));
    await tester.pump(); await tester.pump(); await tester.pump(const Duration(milliseconds: 200));
    // 1) "1st choice" + "2nd choice" + "3rd choice" — 1-based ordinal labels (replaces Priority 0/1/2).
    expect(find.text('1st choice'), findsOneWidget, reason: 's329 #C: priority=0 → "1st choice"');
    expect(find.text('2nd choice'), findsOneWidget, reason: 's329 #C: priority=1 → "2nd choice"');
    expect(find.text('3rd choice'), findsOneWidget, reason: 's329 #C: priority=2 → "3rd choice"');
    // 2) Old "Priority N" labels MUST be gone — user explicitly rejected this naming.
    expect(find.textContaining('Priority '), findsNothing, reason: 's329 #C: legacy "Priority N" chip removed');
    // 3) ⭐ icon visible exactly once — only on priority=0 (Primary).
    expect(find.byIcon(Icons.star), findsOneWidget, reason: 's329 #C: ⭐ Primary indicator on priority=0 only');
    // 4) Fix D: Active/Standby slot chip — 2 accounts Active (priorities 0,1 < RF=2), 1 Standby (priority 2).
    expect(find.text('Active'), findsNWidgets(2), reason: 's329 #D: priorities < RF=2 → Active');
    expect(find.text('Standby'), findsOneWidget, reason: 's329 #D: priority >= RF=2 → Standby');
  });
}
