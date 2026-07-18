import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dudenest/core/storage/storage_engine.dart';
import 'package:dudenest/features/files/direct_mode_screen.dart';
import 'package:dudenest/features/files/gallery_screen.dart';

// 1x1 przezroczysty PNG — żeby engine.thumbnail() dawał dekodowalny ImageProvider w teście.
final _px = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

/// Fake StorageEngine: konfigurowalne listFiles (lista lub wyjątek), reszta nieistotna dla testu.
class _FakeEngine extends StorageEngine {
  final List<Map<String, dynamic>>? files;
  final Object? throwOnList;
  _FakeEngine({this.files, this.throwOnList});
  @override
  Future<List<Map<String, dynamic>>> listFiles() async {
    if (throwOnList != null) throw throwOnList!;
    return files ?? const [];
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
  Future<Map<String, dynamic>> uploadFile(String f, Uint8List b, {String strategy = 'Replica'}) async => {};
  @override
  Future<Uint8List> downloadFile(String fileId) async => Uint8List(0);
  @override
  Future<void> deleteFile(String fileId) async {}
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
    expect(find.textContaining('Brak plików utworzonych'), findsOneWidget);
    expect(find.byType(GalleryScreen), findsNothing);
  });

  testWidgets('connect → wyjątek (np. 401) → stan błędu + Połącz ponownie', (t) async {
    await t.pumpWidget(_wrap(DirectModeScreen(
        folder: 'photos', engineBuilder: () => _FakeEngine(throwOnList: StorageException('401', statusCode: 401)))));
    await t.tap(find.text('Connect Google Drive'));
    await t.pumpAndSettle();
    expect(find.text('Połącz ponownie'), findsOneWidget);
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
}
