// s329 Feature 5: /Files filter + sort + group settings model. Pure data + grouping helper.
// Logic lives in pure functions for easy unit testing (no Flutter dependency aside from prefs).
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

enum FilesGroupMode { account, date, type, none }
enum FilesSortField { date, name, size, type }

class FilesViewSettings {
  final FilesGroupMode primaryGroup;    // default: account
  final FilesGroupMode secondaryGroup;  // default: date — applied within primary groups; .none = single-level
  final FilesSortField sortField;       // default: date
  final bool sortAscending;             // default: false (desc — newest/largest first)
  final String searchQuery;             // free-text substring match on name; default ''
  final Set<String> typeFilters;        // file-type chips: 'photo' | 'video' | 'document' | 'archive' | 'other'; default {} (all)

  const FilesViewSettings({
    this.primaryGroup = FilesGroupMode.account,
    this.secondaryGroup = FilesGroupMode.date,
    this.sortField = FilesSortField.date,
    this.sortAscending = false,
    this.searchQuery = '',
    this.typeFilters = const {},
  });

  FilesViewSettings copyWith({
    FilesGroupMode? primaryGroup, FilesGroupMode? secondaryGroup,
    FilesSortField? sortField, bool? sortAscending,
    String? searchQuery, Set<String>? typeFilters,
  }) => FilesViewSettings(
    primaryGroup: primaryGroup ?? this.primaryGroup,
    secondaryGroup: secondaryGroup ?? this.secondaryGroup,
    sortField: sortField ?? this.sortField,
    sortAscending: sortAscending ?? this.sortAscending,
    searchQuery: searchQuery ?? this.searchQuery,
    typeFilters: typeFilters ?? this.typeFilters,
  );

  // s329 Feature 5: persistence — single JSON key. Resilient to unknown enum values (falls back to defaults).
  static const _kSettings = 'files_view_settings_v1';

  Map<String, dynamic> toJson() => {
    'primary': primaryGroup.name,
    'secondary': secondaryGroup.name,
    'sort_field': sortField.name,
    'sort_asc': sortAscending,
    'search': searchQuery,
    'type_filters': typeFilters.toList(),
  };

  factory FilesViewSettings.fromJson(Map<String, dynamic> j) {
    FilesGroupMode pg(String? s) => FilesGroupMode.values.firstWhere(
        (e) => e.name == s, orElse: () => FilesGroupMode.account);
    FilesSortField sf(String? s) => FilesSortField.values.firstWhere(
        (e) => e.name == s, orElse: () => FilesSortField.date);
    return FilesViewSettings(
      primaryGroup: pg(j['primary'] as String?),
      secondaryGroup: pg(j['secondary'] as String?),
      sortField: sf(j['sort_field'] as String?),
      sortAscending: (j['sort_asc'] as bool?) ?? false,
      searchQuery: (j['search'] as String?) ?? '',
      typeFilters: ((j['type_filters'] as List?) ?? []).cast<String>().toSet(),
    );
  }

  static Future<FilesViewSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSettings);
    if (raw == null || raw.isEmpty) return const FilesViewSettings();
    try { return FilesViewSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>); }
    catch (_) { return const FilesViewSettings(); }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSettings, jsonEncode(toJson()));
  }
}

// FilesGroup is one rendered section: label + list of files (already sorted + filtered).
// May contain nested FilesGroup children when secondaryGroup != .none.
class FilesGroup {
  final String label;                     // e.g. "krzysztofjeno@gmail.com" or "2026-05-30"
  final List<Map<String, dynamic>> files; // direct files (empty if has children)
  final List<FilesGroup> children;        // nested sub-groups; empty if leaf
  const FilesGroup({required this.label, this.files = const [], this.children = const []});

  int get fileCount => files.isNotEmpty ? files.length : children.fold(0, (s, c) => s + c.fileCount);
}

// Derives email from FileMap's first Replica.Location ("gdrive:user@gmail.com:path") — falls back to "Unknown".
// Used for grouping by account in UI.
String accountEmailOf(Map<String, dynamic> file) {
  final replicas = (file['replicas'] as List?) ?? const [];
  if (replicas.isEmpty) return 'Unknown';
  final loc = (replicas.first as Map?)?['location'] as String? ?? '';
  final parts = loc.split(':');
  if (parts.length >= 2 && parts[1].isNotEmpty) return parts[1];
  return 'Unknown';
}

// Classifies a file by extension into one of the 5 type buckets used for filtering chips.
String fileTypeOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  const photo = {'jpg','jpeg','png','gif','webp','heic','heif','bmp','tiff','tif','avif'};
  const video = {'mp4','mov','avi','mkv','webm','m4v','3gp','wmv','flv'};
  const doc   = {'pdf','doc','docx','txt','md','rtf','odt','xls','xlsx','ppt','pptx','csv','json','xml','html'};
  const arch  = {'zip','rar','7z','tar','gz','bz2','xz'};
  if (photo.contains(ext)) return 'photo';
  if (video.contains(ext)) return 'video';
  if (doc.contains(ext))   return 'document';
  if (arch.contains(ext))  return 'archive';
  return 'other';
}

// Pure helper: applies search + type filter, then groups + sorts files according to settings.
// Returns root list of FilesGroup; depth=2 when secondary != .none, depth=1 otherwise, depth=0 (single flat group) when both .none.
List<FilesGroup> groupAndSort(List<Map<String, dynamic>> files, FilesViewSettings s) {
  // Step 1: filter
  final filtered = files.where((f) {
    final name = (f['name'] as String? ?? '').toLowerCase();
    if (s.searchQuery.isNotEmpty && !name.contains(s.searchQuery.toLowerCase())) return false;
    if (s.typeFilters.isNotEmpty && !s.typeFilters.contains(fileTypeOf(f['name'] as String? ?? ''))) return false;
    return true;
  }).toList();
  // Step 2: sort comparator
  int cmp(Map<String, dynamic> a, Map<String, dynamic> b) {
    int r;
    switch (s.sortField) {
      case FilesSortField.date:
        final da = DateTime.tryParse(a['taken_at'] as String? ?? a['created'] as String? ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b['taken_at'] as String? ?? b['created'] as String? ?? '') ?? DateTime(2000);
        r = da.compareTo(db); break;
      case FilesSortField.name:
        r = (a['name'] as String? ?? '').toLowerCase().compareTo((b['name'] as String? ?? '').toLowerCase()); break;
      case FilesSortField.size:
        r = ((a['size'] as num?)?.toInt() ?? 0).compareTo((b['size'] as num?)?.toInt() ?? 0); break;
      case FilesSortField.type:
        r = fileTypeOf(a['name'] as String? ?? '').compareTo(fileTypeOf(b['name'] as String? ?? '')); break;
    }
    return s.sortAscending ? r : -r;
  }
  filtered.sort(cmp);
  // Step 3: grouping. Helper computes key for a single file given a mode.
  String keyOf(Map<String, dynamic> f, FilesGroupMode m) {
    switch (m) {
      case FilesGroupMode.account: return accountEmailOf(f);
      case FilesGroupMode.date:
        final dt = DateTime.tryParse(f['taken_at'] as String? ?? f['created'] as String? ?? '') ?? DateTime(2000);
        return '${dt.toUtc().year.toString().padLeft(4, '0')}-${dt.toUtc().month.toString().padLeft(2, '0')}-${dt.toUtc().day.toString().padLeft(2, '0')}';
      case FilesGroupMode.type: return fileTypeOf(f['name'] as String? ?? '');
      case FilesGroupMode.none: return '';
    }
  }
  if (s.primaryGroup == FilesGroupMode.none) {
    return [FilesGroup(label: 'All files', files: filtered)];
  }
  // Build primary buckets, preserving sort order from `filtered`.
  final primary = <String, List<Map<String, dynamic>>>{};
  final primaryOrder = <String>[];
  for (final f in filtered) {
    final k = keyOf(f, s.primaryGroup);
    if (!primary.containsKey(k)) { primary[k] = []; primaryOrder.add(k); }
    primary[k]!.add(f);
  }
  if (s.secondaryGroup == FilesGroupMode.none || s.secondaryGroup == s.primaryGroup) {
    return primaryOrder.map((k) => FilesGroup(label: k, files: primary[k]!)).toList();
  }
  // Two-level grouping: each primary bucket has its own ordered map of secondary buckets.
  return primaryOrder.map((pk) {
    final inBucket = primary[pk]!;
    final sec = <String, List<Map<String, dynamic>>>{};
    final secOrder = <String>[];
    for (final f in inBucket) {
      final sk = keyOf(f, s.secondaryGroup);
      if (!sec.containsKey(sk)) { sec[sk] = []; secOrder.add(sk); }
      sec[sk]!.add(f);
    }
    return FilesGroup(
      label: pk,
      children: secOrder.map((sk) => FilesGroup(label: sk, files: sec[sk]!)).toList(),
    );
  }).toList();
}
