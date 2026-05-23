# Flutter Cloud Accounts UI — Reference

**Status**: Phase γ continue LIVE (commit `82559de`, deployed 2026-05-22T23:45 via dudenest-web).
**File**: `lib/features/storage_accounts/accounts_screen.dart` (1190+ LOC after Phase γ additions).
**Backend dependency**: `dudenest-relay` v0.18.0+ for `/admin/accounts` + `/admin/policy` endpoints; v0.19.0+ for `DELETE` drain workflow that actually migrates files.

This document covers **only the multi-account UI added in Phase γ continue**. The pre-existing
`_AddAccountSheet` (OAuth flow for attaching new accounts) is documented separately in the
session file `~/.AI/dudenest-application/session-2026-04-07-flutter-development.md`.

---

## 1. Where users find it

```
Bottom nav (BottomNavigationBar in main.dart):
  Photos | Files | Upload | Settings
                            ↓
                          Tap Settings
                            ↓
                    SettingsScreen
                            ↓
                   "Cloud Accounts" tile
                            ↓
                    AccountsScreen
                      ├─ "Accounts" tab
                      │   ├─ _StorageSummaryCard (existing pre-Phase γ)
                      │   ├─ _PolicyCard  ← NEW (Phase γ)
                      │   └─ ListView of _AccountListTile  ← NEW (Phase γ)
                      └─ "Visualizer" tab → StorageVisualizer (existing pre-Phase γ)
```

---

## 2. Data flow

```
                          ┌───────────────────────────────────────┐
                          │  AccountsScreen._load() — parallel    │
                          │  Future.wait([                        │
                          │    relay.getProviders(),    (legacy)  │
                          │    relay.getAdminAccounts(),  (NEW)   │
                          │  ])                                   │
                          └───────────────────────────────────────┘
                                          │
                          ┌───────────────┴───────────────┐
                          ▼                               ▼
                _providers (List)                _adminAccounts (Map<int,…>)
                + _adminPolicy (Map)
                          │                               │
                          └───────────────┬───────────────┘
                                          ▼
                          ┌───────────────────────────────────────┐
                          │   _buildList() — sort by              │
                          │   admin.priority (where present),     │
                          │   render _AccountListTile per provider│
                          │   with admin metadata when matched    │
                          │   via _adminFor(provider) helper      │
                          └───────────────────────────────────────┘
```

**Key concept**: legacy `/providers` and new `/admin/accounts` describe overlapping sets but with different fields. `_providers` carries `file_count`, `available`, `last_error`, `quota_used_gb`/`quota_total_gb` (snapshot at provider auth time). `_adminAccounts` carries `id`, `role`, `priority`, `pinned`, `quota_used_bytes`/`quota_total_bytes` (refreshed by the relay's quota poll loop every 30 min). `_adminFor(provider)` matches on `(provider.type, provider.email)` and returns the admin record or `nil`. When `nil` (older relay without `/admin/accounts`), the UI degrades gracefully — no priority badge, no role badge, no popup menu — but still shows the account.

---

## 3. Widget reference

### 3.1. `AccountsScreen` (`_AccountsScreenState`)

Top-level. Stateful. Holds the two data sources + reload trigger.

**State fields**:
- `_providers: List<Map<String, dynamic>>` — legacy GET /providers data (auth status, file counts).
- `_adminAccounts: Map<int, Map<String, dynamic>>` — Phase α/β data keyed by `id` for fast lookup.
- `_adminPolicy: Map<String, dynamic>` — Phase β global policy.
- `_loading: bool` — true during `_load()`.
- `_error: Object?` — last error from `_load()`.

**Methods**:
- `initState()` → kicks off `_load()`.
- `_load()` — parallel fetch via `Future.wait`. Catches `/admin/accounts` 404 (older relay) → treats as empty admin data so UI degrades gracefully instead of erroring entirely.
- `_adminFor(provider)` — returns the admin record matching `(provider.type, provider.email)` or `null`.
- `build()` — DefaultTabController, AppBar with refresh action + "Add Account" FAB.
- `_buildList()` — sorted by admin Priority ASC; renders `_StorageSummaryCard` + `_PolicyCard` (if admin data present) + ListView of `_AccountListTile`.
- `_emptyState()` — shown when 0 providers (CTA to attach first account).

**Backwards compat**: if `/admin/accounts` returns 404 (Phase α not deployed on this relay), the UI shows accounts via legacy data only (no priority/role badges, no popup menu, no policy card). Users see no error.

### 3.2. `_AccountListTile`

One Card per cloud account. **Per-account heart of the UI**.

**Constructor params**:
- `provider: Map<String, dynamic>` — required (legacy /providers entry).
- `admin: Map<String, dynamic>?` — nullable (admin entry, null on older relays).
- `relay: RelayClient` — for action calls (refresh quota, patch, delete).
- `onChanged: VoidCallback` — reload trigger after edit/drain.
- `onReconnect: VoidCallback` — fires when user taps "Reconnect" on unavailable account.

**Rendered structure** (top to bottom):

| Element | Source | Notes |
|---------|--------|-------|
| Provider icon | `provider.type` → `Icons.drive_folder_upload` (gdrive) / `Icons.storage` (mega) / `Icons.cloud` (onedrive) | Green when `available==true`, grey otherwise |
| `_IDBadge` | `admin.id` + `admin.pinned` | Skipped when admin null |
| Email text | `provider.email` (overflow ellipsis) | Bold weight |
| Status icon | `provider.available` | Green check or red error, with tooltip |
| Popup menu (`Icons.more_vert`) | – | Skipped when admin null; otherwise Refresh/Edit/Drain items |
| `_RoleBadge` | `admin.role` | Color-coded |
| Priority chip | `admin.priority` | Compact density |
| "reconnect needed" red text | `!available` | Inline tag |
| `_QuotaBar` | `admin.quota_used_bytes`/`quota_total_bytes` (fresh) OR `provider.quota_used_gb`/`quota_total_gb` (fallback) + `admin.soft_cap_pct`/`admin.hard_cap_pct` | Threshold markers |
| Quota text | "0.12 / 16.11 GB · 0.7% used · 31 files" | Grey 12px |
| Reconnect button | `!available` | Outlined, full-width below |

**Action handler `_handleAction(ctx, action)`**:
- `'refresh'` → `relay.refreshAdminQuota(id)` → SnackBar "Quota refreshed" → `onChanged()`.
- `'edit'` → `showDialog(_EditAccountDialog)` → if returns `true`, `onChanged()`.
- `'drain'` → confirmation AlertDialog → `relay.drainAdminAccount(id)` → SnackBar "Drain started" → `onChanged()`.

All actions catch errors and surface them via SnackBar.

### 3.3. `_IDBadge`

Compact rectangle showing `ID%03d` (e.g. `ID042`) or `ID%d` for ≥1000. Pinned accounts also show a `Icons.push_pin` (11px) inside the badge — visual reminder that `ReconcileRoles` won't auto-demote/promote this account.

**Why**: IDs are NEVER reused after Drain+Remove (see backend doc §3.1). Surfacing them prominently helps with support — "I deleted ID007 last week, why is the new account ID019?" → answer: that's expected, IDs are monotonic forever.

### 3.4. `_RoleBadge`

Color-coded Chip showing the account's current selection role. Driven by Phase α model:

| Role string | Display | Color |
|-------------|---------|-------|
| `primary_write` | "Primary" | Green |
| `replica_write` | "Replica" | Blue |
| `read_only` | "Read only" | Grey |
| `cold_archive` | "Cold archive" | Purple |
| `drain` | "Draining" | Orange |
| `quarantine` | "Quarantine" | Red |
| _other_ | raw string | Blue-grey |

**Why color**: Primary green (the "good" state — file lands here first). Replica blue (cooler — backup). Cold archive purple (long-term). Draining orange (transitioning). Quarantine red (problem).

### 3.5. `_QuotaBar`

8px-tall horizontal progress bar with two vertical threshold lines:
- Green fill when `used < softCap`
- Orange fill when `softCap ≤ used < hardCap`
- Red fill when `used ≥ hardCap`
- Amber vertical line at `softCap` position (default 90%)
- Red vertical line at `hardCap` position (default 98%)

The threshold lines are static markers (1px wide) — they don't move when usage changes, only the fill does. Lets the user see at a glance "I'm 70% full, soft cap is at 90%, so I've got 20% headroom before auto-demote".

Uses `LayoutBuilder` to compute pixel positions of the threshold lines from the bar's actual width (responsive to card width changes when the device rotates).

### 3.6. `_PolicyCard`

Indigo-tinted Card pinned above the account list. Shows the global `AccountPolicyConfig` summary in one line:

```
📋 Global Policy
   Replication factor: 2 · Diversity: off · Caps: 90% / 98% · Age rotation: off    [edit]
```

Edit button → `showDialog(_EditPolicyDialog)`.

Hidden entirely when `_adminPolicy` is empty (older relay without `/admin/policy`).

### 3.7. `_EditAccountDialog`

Stateful dialog. Per-account edit form. Lets the user override:

| Field | Widget | Notes |
|-------|--------|-------|
| Role | `DropdownButtonFormField` | 4 options: Primary/Replica/Read-only/Cold archive |
| Priority | `TextFormField` (numeric) | Integer — lower = higher importance |
| Pinned | `SwitchListTile` | When on, immune to auto-demote/promote |
| Soft cap % override | `TextFormField` (numeric, optional) | Blank = inherit global |
| Hard cap % override | `TextFormField` (numeric, optional) | Blank = inherit global |

**Submit logic** (`_save()`):
- Builds a `patch` map with role/priority/pinned always (they always have a value).
- `soft_cap_pct` / `hard_cap_pct` only included when `int.tryParse` succeeds (preserves the "blank = inherit" semantics).
- Calls `relay.patchAdminAccount(id, patch)` → on success `Navigator.pop(context, true)`.
- On error: SnackBar with message + leaves dialog open.

**Loading state**: `_saving` bool. While true, Cancel + Save buttons disabled, Save shows a `CircularProgressIndicator(strokeWidth: 2)` instead of text.

### 3.8. `_EditPolicyDialog`

Stateful dialog. Global policy edit form. Same UX patterns as account edit.

| Field | Widget | Notes |
|-------|--------|-------|
| Replication factor | +/- buttons + big number | Range [1, ∞); display centered |
| Diversity required | `SwitchListTile` | When on, replicas spread across provider types |
| Age-based rotation | `SwitchListTile` | Subtitled "Migrate old files to cold archive accounts" — opt-in feature |
| Default soft cap % | `TextFormField` (numeric) | Applies to accounts without `soft_cap_pct` override |
| Default hard cap % | `TextFormField` (numeric) | Same for hard cap |

**Submit logic**: PATCH `/admin/policy` with the merged overlay. Same error/loading patterns as `_EditAccountDialog`.

---

## 4. RelayClient extensions (`lib/core/network/relay_client.dart`)

Six new methods added in Phase γ continue:

| Method | HTTP | Auth | Returns |
|--------|------|------|---------|
| `getAdminAccounts()` | GET `/admin/accounts` | JWT + X-Relay-Token | `Map<String, dynamic>` `{accounts: [...], policy: {...}}` |
| `patchAdminAccount(id, patch)` | PATCH `/admin/accounts/{id}` | same | refreshed account |
| `reorderAdminAccounts(ids)` | POST `/admin/accounts/reorder` | same | refreshed list |
| `refreshAdminQuota(id)` | POST `/admin/accounts/{id}/refresh-quota` | same | refreshed account |
| `drainAdminAccount(id)` | DELETE `/admin/accounts/{id}` | same | `{status: "drain_initiated"}` |
| `patchAdminPolicy(patch)` | PATCH `/admin/policy` | same | merged policy |

All use the shared `_headers` + `_processResponse` helpers — same auth + error handling as the rest of RelayClient. Body is `jsonEncode(patch)` with explicit `Content-Type: application/json` header on PATCH/POST.

The legacy `getProviders()` stays unchanged for backward compatibility with `StorageVisualizer` (which uses different fields).

---

## 5. User flows

### 5.1. Reorder accounts (NOT YET via drag-drop — backend ready, UI todo)

`POST /admin/accounts/reorder` accepts `{ids: [3, 1, 2]}`. The Flutter side currently has no drag-drop UI; reordering happens via `_EditAccountDialog` → Priority field. **Carry-over**: wrap the ListView in `ReorderableListView` and on `onReorder` call `relay.reorderAdminAccounts(newOrder)`. ~30 LOC Flutter.

### 5.2. Promote account manually

User taps `⋮` → Edit on the desired account → Role dropdown → Primary write → Save. The PATCH triggers `Manager.SetRole(id, primary_write)`. If another account was Primary, `ReconcileRoles` will re-evaluate on the next minute tick.

### 5.3. Pin account against auto-demote

Edit → toggle Pinned → Save. ReconcileRoles will skip this account on subsequent sweeps.

### 5.4. Cap override per account

Useful e.g. for a small free MEGA account where you want to stop using it at 50% to leave headroom. Edit → Soft cap % override = `50` → Save.

### 5.5. Drain account

`⋮` → Remove (drain) → confirmation dialog → confirm → `DELETE /admin/accounts/{id}` flips `Role=Drain`. The relay's drain worker (v0.19.0+) runs every 2 min and migrates shards to other accounts. Once all migrated, the account auto-transitions to `Status=Removed` (audit-retained).

**UI gap**: no live progress display. Backend has `DrainState` tracker; the `/admin/accounts/{id}/drain-progress` endpoint is **not yet implemented**. Carry-over.

### 5.6. Refresh quota on demand

Useful right after the user freed space on Drive UI and wants the badge to reflect it before the next scheduled poll (up to 30 min away). `⋮` → Refresh quota.

### 5.7. Edit global policy

Tap pencil on the indigo Policy card → `_EditPolicyDialog` → adjust + Save.

---

## 6. Backwards compatibility matrix

| Relay version | What user sees |
|---------------|----------------|
| <v0.17.2 (no Phase α) | List with email + quota + connection status (legacy). No Priority/Role badges, no popup menu, no Policy card. |
| v0.17.2..v0.17.3 (Phase α only) | Full UI shows Priority + Role + Quota bar. Edit dialog works. **DELETE = stub** (flips Role to Drain but no background worker exists). |
| v0.18.0 (Phase β) | Above + quota updates every 30 min from real Drive API. Auto-demote/promote visible (badges shift between Primary/Replica). |
| v0.19.0+ (Phase γ) | Above + DELETE actually migrates files in background. Account stays in Drain role visibly until done, then disappears from list (Status=Removed). |

Flutter app code is a single binary serving all relays — version detection is by gracefully handling 404 on the admin endpoints.

---

## 7. Carry-overs / Phase γ continue follow-ups

| Item | Priority | Where |
|------|----------|-------|
| ReorderableListView drag-drop for Priority | HIGH | `_buildList` — wrap ListView in `ReorderableListView`, call `relay.reorderAdminAccounts(newOrder)` in `onReorder` |
| `/admin/accounts/{id}/drain-progress` backend endpoint + UI progress bar | MEDIUM | Backend: read `globalDrainState.Snapshot(id)`, return JSON. UI: poll every 5s when account's role==drain. |
| Add account UX after Re-add detection | LOW | `_AddAccountSheet` should call `AddAccount` and on `isReAddError`, show modal "This account was previously removed as ID007. Restore old ID or create new?" per `OnReAddSameEmail` policy |
| `accepts_content_types` editor (photos-only, files-only) | LOW | `_EditAccountDialog` — add `Wrap` of FilterChip toggles |
| Region / CompressionLevel inputs | LOW | Forward-compat F3/F4 — fields exist in model but not in dialog |
| Test coverage | MEDIUM | Currently no Flutter widget tests for AccountsScreen. Add `test/features/storage_accounts/accounts_screen_test.dart` mocking RelayClient |

---

## 8. Where the code is

| Component | File | Lines (approx) |
|-----------|------|----------------|
| `AccountsScreen` + `_AccountsScreenState` | `lib/features/storage_accounts/accounts_screen.dart` | 13-180 |
| `_AccountListTile` | same | 873-980 |
| `_IDBadge` | same | 983-1003 |
| `_RoleBadge` | same | 1006-1028 |
| `_QuotaBar` | same | 1031-1061 |
| `_PolicyCard` | same | 1063-1098 |
| `_EditAccountDialog` + state | same | 1100-1180 |
| `_EditPolicyDialog` + state | same | 1183-1280 |
| RelayClient admin methods | `lib/core/network/relay_client.dart` | 54-128 |

---

## 9. Cross-references

- Backend reference (every field, every method): `dudenest-relay/docs/MULTI-ACCOUNT.md`
- Design doc: `~/.AI/dudenest-application/CLOUD-ACCOUNT-POLICY-PLAN.md`
- Session files: `~/.AI/dudenest-application/session-2026-05-23-flutter-cloud-accounts-ui.md` (this UI)
