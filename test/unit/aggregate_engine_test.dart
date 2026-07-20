import 'dart:typed_data';
import 'package:flutter/widgets.dart' show ImageProvider, AssetImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/storage/aggregate_engine.dart';
import 'package:dudenest/core/storage/storage_engine.dart';

// Przypina kontrakt MP1b: AggregateEngine merge'uje pliki z wielu kont, taguje account_id, a operacje
// per-plik routuje do właściwego silnika po INDEKSIE file_id→accountId budowanym w listFiles.
// Silniki są fake (per konto) → zero sieci/OAuth; sprawdzamy DOKĄD trafiło wywołanie.

class _FakeEngine implements StorageEngine {
  final String tag; // do rozpoznania, który silnik obsłużył wywołanie
  final List<Map<String, dynamic>> files;
  final Object? throwOnList; // gdy != null, listFiles rzuca (symuluje odwołany/wygasły token konta)
  final List<String> deleted = [];
  final List<String> downloaded = [];
  final List<String> uploaded = [];
  _FakeEngine(this.tag, {List<Map<String, dynamic>>? files, this.throwOnList}) : files = files ?? [];

  // Zwracaj ŚWIEŻE kopie map — inaczej AggregateEngine mutuje account_id na współdzielonej mapie.
  @override
  Future<List<Map<String, dynamic>>> listFiles() async {
    if (throwOnList != null) throw throwOnList!;
    return files.map((f) => Map<String, dynamic>.from(f)).toList();
  }

  @override
  Future<void> deleteFile(String fileId) async {
    deleted.add(fileId);
    files.removeWhere((f) => f['file_id'] == fileId);
  }

  @override
  Future<Uint8List> downloadFile(String fileId) async {
    downloaded.add(fileId);
    return Uint8List.fromList(tag.codeUnits); // marker źródła
  }

  @override
  Future<Map<String, dynamic>> uploadFile(String filename, Uint8List bytes,
      {String strategy = 'Replica'}) async {
    uploaded.add(filename);
    final entry = {'file_id': '$tag-${uploaded.length}', 'name': filename, 'folder': 'photos'};
    files.add(entry);
    return entry;
  }

  @override
  Future<Map<String, dynamic>> getFileMap(String fileId) async => {'file_id': fileId, 'from': tag};
  @override
  Future<Map<String, dynamic>> getMeta(String fileId) async => {'from': tag};
  @override
  Future<Map<String, dynamic>> patchMeta(String fileId, Map<String, dynamic> patch) async =>
      {'from': tag, ...patch};
  @override
  Future<Map<String, dynamic>> fileManifest({String? since}) async => {};
  ImageProvider _img() => _TagImage(tag);
  @override
  ImageProvider thumbnail(String fileId) => _img();
  @override
  ImageProvider preview(String fileId) => _img();
  @override
  ImageProvider original(String fileId) => _img();
}

// ImageProvider niosący tag silnika — pozwala sprawdzić, który silnik zwrócił provider.
class _TagImage extends AssetImage {
  final String engineTag;
  const _TagImage(this.engineTag) : super('x');
}

void main() {
  Map<String, dynamic> file(String id, {String folder = 'photos'}) =>
      {'file_id': id, 'name': '$id.jpg', 'folder': folder};

  test('implements StorageEngine', () {
    final StorageEngine e = AggregateEngine({'a': _FakeEngine('a')});
    expect(e, isA<AggregateEngine>());
  });

  test('listFiles: merge z wielu kont + tag account_id + zbudowany indeks', () async {
    final agg = AggregateEngine({
      'google:a@x.com': _FakeEngine('A', files: [file('f1'), file('f2')]),
      'google:b@x.com': _FakeEngine('B', files: [file('g1')]),
    });
    final out = await agg.listFiles();
    expect(out.length, 3);
    expect(out.firstWhere((f) => f['file_id'] == 'f1')['account_id'], 'google:a@x.com');
    expect(out.firstWhere((f) => f['file_id'] == 'g1')['account_id'], 'google:b@x.com');
    expect(agg.accountCount, 2);
  });

  test('delete routuje do właściwego konta + usuwa z indeksu', () async {
    final a = _FakeEngine('A', files: [file('f1')]);
    final b = _FakeEngine('B', files: [file('g1')]);
    final agg = AggregateEngine({'A': a, 'B': b});
    await agg.listFiles();
    await agg.deleteFile('g1');
    expect(b.deleted, ['g1']);
    expect(a.deleted, isEmpty); // NIE poszło do konta A
    // po delete plik zniknął z indeksu → kolejna operacja na nim rzuca
    expect(() => agg.downloadFile('g1'), throwsA(isA<StorageException>()));
  });

  test('download + getMeta routują po account_id pliku', () async {
    final a = _FakeEngine('A', files: [file('f1')]);
    final b = _FakeEngine('B', files: [file('g1')]);
    final agg = AggregateEngine({'A': a, 'B': b});
    await agg.listFiles();
    await agg.downloadFile('f1');
    await agg.getMeta('g1');
    expect(a.downloaded, ['f1']);
    expect(b.downloaded, isEmpty);
    expect(await agg.getMeta('g1'), {'from': 'B'});
  });

  test('upload trafia do konta domyślnego (pierwsze) + taguje + indeksuje', () async {
    final a = _FakeEngine('A');
    final b = _FakeEngine('B');
    final agg = AggregateEngine({'primary': a, 'secondary': b});
    final res = await agg.uploadFile('new.jpg', Uint8List(0));
    expect(a.uploaded, ['new.jpg']);
    expect(b.uploaded, isEmpty);
    expect(res['account_id'], 'primary');
    // świeżo wgrany plik jest w indeksie → delete routuje bez ponownego listFiles
    await agg.deleteFile(res['file_id'] as String);
    expect(a.deleted, [res['file_id']]);
  });

  test('thumbnail routuje po właścicielu; nieznany plik → fallback pierwszy silnik (nie rzuca)', () async {
    final a = _FakeEngine('A', files: [file('f1')]);
    final b = _FakeEngine('B', files: [file('g1')]);
    final agg = AggregateEngine({'A': a, 'B': b});
    await agg.listFiles();
    expect((agg.thumbnail('g1') as _TagImage).engineTag, 'B'); // po właścicielu
    expect((agg.thumbnail('unknown') as _TagImage).engineTag, 'A'); // fallback, bez crashu
  });

  test('listFiles przebudowuje indeks od zera (usunięty plik przestaje routować)', () async {
    final a = _FakeEngine('A', files: [file('f1'), file('f2')]);
    final agg = AggregateEngine({'A': a});
    await agg.listFiles();
    a.files.removeWhere((f) => f['file_id'] == 'f2'); // plik zniknął po stronie konta
    await agg.listFiles(); // re-list → indeks bez f2
    expect(() => agg.downloadFile('f2'), throwsA(isA<StorageException>()));
    await agg.downloadFile('f1'); // f1 nadal routuje
    expect(a.downloaded, ['f1']);
  });

  test('jedno konto pada → partial results z konta zdrowego + lastListErrors', () async {
    final good = _FakeEngine('GOOD', files: [file('f1'), file('f2')]);
    final bad = _FakeEngine('BAD', throwOnList: StateError('token revoked'));
    final agg = AggregateEngine({'good': good, 'bad': bad});
    final out = await agg.listFiles();
    expect(out.map((f) => f['file_id']), containsAll(['f1', 'f2'])); // galeria NIE zgasła
    expect(out.every((f) => f['account_id'] == 'good'), isTrue);
    expect(agg.lastListErrors, ['bad']); // padłe konto odnotowane
    await agg.downloadFile('f1'); // zdrowe konto nadal routuje
    expect(good.downloaded, ['f1']);
  });

  test('wszystkie konta padają → StorageException (ekran pokaże błąd, nie pusty grid)', () async {
    final agg = AggregateEngine({
      'a': _FakeEngine('A', throwOnList: StateError('x')),
      'b': _FakeEngine('B', throwOnList: StateError('y')),
    });
    expect(() => agg.listFiles(), throwsA(isA<StorageException>()));
  });

  test('pusty agregat: isEmpty, listFiles puste, upload rzuca', () async {
    final agg = AggregateEngine({});
    expect(agg.isEmpty, isTrue);
    expect(await agg.listFiles(), isEmpty);
    expect(() => agg.uploadFile('x.jpg', Uint8List(0)), throwsA(isA<StorageException>()));
  });

  test('operacja na pliku bez listFiles (nieznany) rzuca StorageException 404', () async {
    final agg = AggregateEngine({'A': _FakeEngine('A', files: [file('f1')])});
    expect(() => agg.deleteFile('f1'),
        throwsA(isA<StorageException>().having((e) => e.statusCode, 'statusCode', 404)));
  });
}
