import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/storage/storage_engine.dart';
import 'package:dudenest/features/files/direct_mode_screen.dart';
import 'package:dudenest/features/files/gallery_screen.dart';

// 1x1 przezroczysty PNG — żeby engine.thumbnail() dawał dekodowalny ImageProvider w teście.
final _px = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

/// Fake StorageEngine: konfigurowalne listFiles (lista lub wyjątek), reszta nieistotna dla testu.
class _FakeEngine extends StorageEngine {
  final List<Map<String, dynamic>> _files;
  final Object? throwOnList;
  final List<String> uploaded = [];
  final List<String> deleted = [];
  _FakeEngine({List<Map<String, dynamic>>? files, this.throwOnList}) : _files = [...?files];
  @override
  Future<List<Map<String, dynamic>>> listFiles() async {
    if (throwOnList != null) throw throwOnList!;
    return List.of(_files);
  }
  ImageProvider _img(String _) => MemoryImage(_px);
  @override
  ImageProvider thumbnail(String fileId) => _img(fileId);
  @override
  ImageProvider preview(String fileId) => _img(fileId);
  @override
  ImageProvider original(String fileId) => _img(fileId);
  @override
  Future<Map<String, dynamic>> fileManifest({String? since}) async => {};
  @override
  Future<Map<String, dynamic>> uploadFile(String f, Uint8List b, {String strategy = 'Replica'}) async {
    uploaded.add(f);
    final entry = {'file_id': 'up-${uploaded.length}', 'name': f, 'folder': 'photos'};
    _files.add(entry); // po uploadzie plik pojawia się w listFiles
    return entry;
  }
  @override
  Future<Uint8List> downloadFile(String fileId) async => Uint8List(0);
  @override
  Future<void> deleteFile(String fileId) async {
    deleted.add(fileId);
    _files.removeWhere((f) => f['file_id'] == fileId);
  }
  @override
  Future<Map<String, dynamic>> getFileMap(String fileId) async => {};
  @override
  Future<Map<String, dynamic>> getMeta(String fileId) async => {};
  @override
  Future<Map<String, dynamic>> patchMeta(String fileId, Map<String, dynamic> patch) async => {};
}

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  final photo = {'file_id': 'p1', 'name': 'a.jpg', 'folder': 'photos'};
  final doc = {'file_id': 'd1', 'name': 'note.pdf', 'folder': 'files'};

  testWidgets('startuje w connect-gate (przycisk Connect)', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => _FakeEngine(files: [photo]))));
    expect(find.text('Connect Google Drive'), findsOneWidget);
    expect(find.byType(GalleryScreen), findsNothing);
  });

  testWidgets('connect → pliki → render GalleryScreen', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => _FakeEngine(files: [photo]))));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    expect(find.byType(GalleryScreen), findsOneWidget);
    expect(find.text('Connect Google Drive'), findsNothing);
  });

  testWidgets('connect → pusto → komunikat empty (nie error)', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => _FakeEngine(files: []))));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    expect(find.textContaining('No files created'), findsOneWidget);
    expect(find.byType(GalleryScreen), findsNothing);
  });

  testWidgets('connect → wyjątek (np. 401) → stan błędu + Reconnect', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(
        folder: 'photos', engineBuilder: () => _FakeEngine(throwOnList: StorageException('401', statusCode: 401)))));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.byType(GalleryScreen), findsNothing);
  });

  testWidgets('folder=photos → tylko media (filtr)', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => _FakeEngine(files: [photo, doc]))));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    expect(t.widget<GalleryScreen>(find.byType(GalleryScreen)).files.length, 1); // tylko a.jpg
  });

  testWidgets('folder=files → wszystko (filtr)', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'files', engineBuilder: () => _FakeEngine(files: [photo, doc]))));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    expect(t.widget<GalleryScreen>(find.byType(GalleryScreen)).files.length, 2); // a.jpg + note.pdf
  });

  testWidgets('upload → DirectEngine.uploadFile + re-list pokazuje plik', (t) async {
    final engine = _FakeEngine(files: []);
    final picked = FilePickerResult(
        [PlatformFile(name: 'up.jpg', size: 3, bytes: Uint8List.fromList([1, 2, 3]))]);
    await t.pumpWidget(_wrap(DirectModeScreen(
        folder: 'photos', engineBuilder: () => engine, filePicker: () async => picked)));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    expect(find.textContaining('No files'), findsOneWidget); // start: pusto
    expect(find.text('Upload'), findsOneWidget); // FAB widoczny po połączeniu
    await t.tap(find.text('Upload'));
    await t.pumpAndSettle();
    expect(engine.uploaded, ['up.jpg']); // uploadFile wywołany
    expect(find.byType(GalleryScreen), findsOneWidget); // re-list → grid z wgranym plikiem
  });

  testWidgets('connect-gate bez FAB (upload dopiero po połączeniu)', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => _FakeEngine(files: []))));
    expect(find.text('Upload'), findsNothing);
  });

  testWidgets('long-press → tryb selekcji (AppBar count + delete, FAB znika)', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => _FakeEngine(files: [photo]))));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    await t.longPress(find.byType(Image).first); // wejście w selekcję
    await t.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.delete), findsOneWidget);
    expect(find.text('Upload'), findsNothing); // FAB ukryty w selekcji
  });

  testWidgets('select + delete → engine.deleteFile + re-list bez pliku', (t) async {
    final engine = _FakeEngine(files: [photo]);
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => engine)));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    await t.longPress(find.byType(Image).first);
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.delete)); // otwiera confirm dialog
    await t.pumpAndSettle();
    await t.tap(find.text('Delete')); // potwierdź
    await t.pumpAndSettle();
    expect(engine.deleted, ['p1']); // deleteFile wywołany dla zaznaczonego id
    expect(find.textContaining('No files'), findsOneWidget); // re-list → pusto
  });

  testWidgets('delete anulowany → engine.deleteFile NIE wywołany', (t) async {
    final engine = _FakeEngine(files: [photo]);
    await t.pumpWidget(_wrap(DirectModeScreen(folder: 'photos', engineBuilder: () => engine)));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    await t.longPress(find.byType(Image).first);
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.delete));
    await t.pumpAndSettle();
    await t.tap(find.text('Cancel')); // rezygnacja
    await t.pumpAndSettle();
    expect(engine.deleted, isEmpty);
    expect(find.byType(GalleryScreen), findsOneWidget); // plik nadal jest
  });
}
