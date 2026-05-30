// s329 Feature 5 regression pins: FilesViewSettings + groupAndSort must group/sort/filter
// correctly. These pure helpers drive the new /Files screen (group by account/date/type,
// sort by date/name/size/type, filter by search query + type chips, persistence via JSON).
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/features/files/files_view_settings.dart';

Map<String, dynamic> _f({
  required String id, required String name, int size = 1000, String? takenAt, String email = 'a@gmail.com',
}) => {
  'file_id': id, 'name': name, 'size': size,
  'taken_at': takenAt ?? '2026-05-30T12:00:00Z',
  'created': '2026-05-30T12:00:00Z',
  'replicas': [{'location': 'gdrive:$email:/path/$name'}],
};

void main() {
  group('accountEmailOf', () {
    test('extracts email from first replica location', () {
      expect(accountEmailOf(_f(id: '1', name: 'a.pdf', email: 'foo@bar.com')), 'foo@bar.com');
    });
    test('returns Unknown when replicas missing', () {
      expect(accountEmailOf({'name': 'x.pdf'}), 'Unknown');
    });
    test('returns Unknown when location malformed', () {
      expect(accountEmailOf({'replicas': [{'location': ''}]}), 'Unknown');
    });
  });

  group('fileTypeOf', () {
    test('classifies photos', () {
      expect(fileTypeOf('photo.jpg'), 'photo');
      expect(fileTypeOf('IMG.HEIC'), 'photo');
    });
    test('classifies videos', () {
      expect(fileTypeOf('clip.mp4'), 'video');
      expect(fileTypeOf('vid.MOV'), 'video');
    });
    test('classifies documents', () {
      expect(fileTypeOf('invoice.pdf'), 'document');
      expect(fileTypeOf('contract.DOCX'), 'document');
    });
    test('classifies archives', () {
      expect(fileTypeOf('backup.zip'), 'archive');
    });
    test('falls back to other', () {
      expect(fileTypeOf('binary.bin'), 'other');
      expect(fileTypeOf('noext'), 'other');
    });
  });

  group('groupAndSort — Feature 5', () {
    final sample = [
      _f(id: '1', name: 'newest.pdf', size: 1000, takenAt: '2026-05-30T15:00:00Z', email: 'a@gmail.com'),
      _f(id: '2', name: 'middle.jpg', size: 500,  takenAt: '2026-05-29T10:00:00Z', email: 'a@gmail.com'),
      _f(id: '3', name: 'oldest.zip', size: 2000, takenAt: '2026-05-28T08:00:00Z', email: 'b@gmail.com'),
    ];

    test('default: group by account, sort by date desc', () {
      final groups = groupAndSort(sample, const FilesViewSettings());
      expect(groups, hasLength(2));
      expect(groups[0].label, 'a@gmail.com');
      // Within a@gmail.com: secondary group by date → 2 sub-groups (2026-05-30 + 2026-05-29)
      expect(groups[0].children, hasLength(2));
      expect(groups[0].children[0].label, '2026-05-30');
      expect(groups[0].children[1].label, '2026-05-29');
    });

    test('group by date only (secondary=none): 3 date groups across all accounts', () {
      final s = const FilesViewSettings(primaryGroup: FilesGroupMode.date, secondaryGroup: FilesGroupMode.none);
      final groups = groupAndSort(sample, s);
      expect(groups, hasLength(3));
      expect(groups[0].label, '2026-05-30'); // newest first (desc default)
      expect(groups[0].files, hasLength(1));
      expect(groups[0].files[0]['file_id'], '1');
    });

    test('group=none: single flat group "All files", sorted', () {
      final s = const FilesViewSettings(primaryGroup: FilesGroupMode.none);
      final groups = groupAndSort(sample, s);
      expect(groups, hasLength(1));
      expect(groups[0].label, 'All files');
      expect(groups[0].files, hasLength(3));
      expect(groups[0].files[0]['file_id'], '1'); // newest first
    });

    test('sort by name asc', () {
      final s = const FilesViewSettings(primaryGroup: FilesGroupMode.none, sortField: FilesSortField.name, sortAscending: true);
      final groups = groupAndSort(sample, s);
      expect(groups[0].files.map((f) => f['name']).toList(), ['middle.jpg', 'newest.pdf', 'oldest.zip']);
    });

    test('sort by size desc', () {
      final s = const FilesViewSettings(primaryGroup: FilesGroupMode.none, sortField: FilesSortField.size);
      final groups = groupAndSort(sample, s);
      expect(groups[0].files.map((f) => f['name']).toList(), ['oldest.zip', 'newest.pdf', 'middle.jpg']);
    });

    test('search query filters by name substring (case-insensitive)', () {
      final s = const FilesViewSettings(primaryGroup: FilesGroupMode.none, searchQuery: 'OLD');
      final groups = groupAndSort(sample, s);
      expect(groups[0].files, hasLength(1));
      expect(groups[0].files[0]['name'], 'oldest.zip');
    });

    test('type filter limits to selected buckets', () {
      final s = const FilesViewSettings(primaryGroup: FilesGroupMode.none, typeFilters: {'photo', 'video'});
      final groups = groupAndSort(sample, s);
      expect(groups[0].files, hasLength(1));
      expect(groups[0].files[0]['name'], 'middle.jpg');
    });

    test('empty input returns empty', () {
      final groups = groupAndSort([], const FilesViewSettings());
      expect(groups, isEmpty);
    });

    test('FilesGroup.fileCount sums nested children', () {
      final groups = groupAndSort(sample, const FilesViewSettings()); // default account+date
      expect(groups[0].fileCount, 2); // a@gmail.com has 2 files across 2 date sub-groups
      expect(groups[1].fileCount, 1);
    });
  });

  group('FilesViewSettings JSON round-trip', () {
    test('default settings serialize and deserialize identically', () {
      const s = FilesViewSettings();
      final s2 = FilesViewSettings.fromJson(s.toJson());
      expect(s2.primaryGroup, s.primaryGroup);
      expect(s2.secondaryGroup, s.secondaryGroup);
      expect(s2.sortField, s.sortField);
      expect(s2.sortAscending, s.sortAscending);
      expect(s2.searchQuery, s.searchQuery);
      expect(s2.typeFilters, s.typeFilters);
    });

    test('custom settings round-trip preserves all fields', () {
      const s = FilesViewSettings(
        primaryGroup: FilesGroupMode.type, secondaryGroup: FilesGroupMode.account,
        sortField: FilesSortField.size, sortAscending: true,
        searchQuery: 'invoice', typeFilters: {'document', 'archive'},
      );
      final s2 = FilesViewSettings.fromJson(s.toJson());
      expect(s2.primaryGroup, FilesGroupMode.type);
      expect(s2.secondaryGroup, FilesGroupMode.account);
      expect(s2.sortField, FilesSortField.size);
      expect(s2.sortAscending, isTrue);
      expect(s2.searchQuery, 'invoice');
      expect(s2.typeFilters, {'document', 'archive'});
    });

    test('unknown enum values fall back to defaults', () {
      final s = FilesViewSettings.fromJson({
        'primary': 'invalid_mode', 'secondary': 'also_invalid',
        'sort_field': 'unknown', 'sort_asc': false,
      });
      expect(s.primaryGroup, FilesGroupMode.account); // fallback
      expect(s.sortField, FilesSortField.date); // fallback
    });
  });
}
