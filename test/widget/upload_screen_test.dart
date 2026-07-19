import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/core/storage/storage_engine.dart';
import 'package:dudenest/features/upload/upload_screen.dart';

RelayClient _relay(MockClientHandler h) =>
    RelayClient('http://relay.test', client: MockClient(h));

Widget _wrap(Widget child) => MaterialApp(home: child);

// Minimalny fake do testu ścieżki direct (onConnect) — nagrywa uploady.
class _FakeEngine extends StorageEngine {
  final List<String> uploaded = [];
  @override
  Future<Map<String, dynamic>> uploadFile(String f, Uint8List b, {String strategy = 'Replica'}) async {
    uploaded.add(f);
    return {'file_id': 'x', 'name': f};
  }
  @override
  Future<List<Map<String, dynamic>>> listFiles() async => [];
  @override
  Future<Map<String, dynamic>> fileManifest({String? since}) async => {};
  @override
  Future<Uint8List> downloadFile(String fileId) async => Uint8List(0);
  @override
  Future<void> deleteFile(String fileId) async {}
  @override
  Future<Map<String, dynamic>> getFileMap(String fileId) async => {};
  @override
  Future<Map<String, dynamic>> getMeta(String fileId) async => {};
  @override
  Future<Map<String, dynamic>> patchMeta(String fileId, Map<String, dynamic> p) async => {};
  @override
  ImageProvider thumbnail(String fileId) => const AssetImage('x');
  @override
  ImageProvider preview(String fileId) => const AssetImage('x');
  @override
  ImageProvider original(String fileId) => const AssetImage('x');
}

void main() {
  testWidgets('shows empty state initially', (tester) async {
    final relay = _relay((_) async => http.Response('{}', 200));
    await tester.pumpWidget(_wrap(UploadScreen(engine: relay)));
    expect(find.text('No uploads yet'), findsOneWidget);
    expect(find.text('Pick files'), findsOneWidget);
  });

  testWidgets('shows Pick files button', (tester) async {
    final relay = _relay((_) async => http.Response('{}', 200));
    await tester.pumpWidget(_wrap(UploadScreen(engine: relay)));
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
  });

  testWidgets('Upload button is always enabled (file picker opens on tap)',
      (tester) async {
    final relay = _relay((_) async => http.Response('{}', 200));
    await tester.pumpWidget(_wrap(UploadScreen(engine: relay)));
    final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Pick files'));
    expect(btn.onPressed, isNotNull);
  });

  testWidgets('autoPickNonce invokes injected picker and blocks without relay',
      (tester) async {
    var picks = 0;
    Future<FilePickerResult?> picker() async {
      picks++;
      return FilePickerResult([
        PlatformFile(
            name: 'a.jpg', size: 3, bytes: Uint8List.fromList([1, 2, 3]))
      ]);
    }

    await tester.pumpWidget(_wrap(UploadScreen(engine: null, picker: picker)));
    await tester.pumpWidget(
        _wrap(UploadScreen(engine: null, picker: picker, autoPickNonce: 1)));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.textContaining('Relay is required'), findsOneWidget);
  });

  testWidgets('initial autoPickNonce invokes picker on first mount',
      (tester) async {
    var picks = 0;
    Future<FilePickerResult?> picker() async {
      picks++;
      return FilePickerResult([
        PlatformFile(
            name: 'first.jpg', size: 3, bytes: Uint8List.fromList([1, 2, 3]))
      ]);
    }

    await tester.pumpWidget(
        _wrap(UploadScreen(engine: null, picker: picker, autoPickNonce: 1)));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(find.text('first.jpg'), findsOneWidget);
  });

  // ── Direct: connect-gate (onConnect) ─────────────────────────────────────
  testWidgets('direct: bez silnika pokazuje connect-gate, nie Pick files',
      (tester) async {
    final engine = _FakeEngine();
    await tester.pumpWidget(_wrap(
        UploadScreen(engine: null, onConnect: () async => engine)));
    expect(find.text('Connect Google Drive'), findsOneWidget);
    expect(find.text('Pick files'), findsNothing);
  });

  testWidgets('direct: connect → Pick files; pick → engine.uploadFile',
      (tester) async {
    final engine = _FakeEngine();
    Future<FilePickerResult?> picker() async => FilePickerResult([
          PlatformFile(
              name: 'd.jpg', size: 3, bytes: Uint8List.fromList([1, 2, 3]))
        ]);
    await tester.pumpWidget(_wrap(UploadScreen(
        engine: null, onConnect: () async => engine, picker: picker)));
    await tester.tap(find.text('Connect Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Pick files'), findsOneWidget); // brama zniknęła po połączeniu
    await tester.tap(find.text('Pick files'));
    await tester.pumpAndSettle();
    expect(engine.uploaded, ['d.jpg']); // upload przez silnik direct, nie relay
  });

  testWidgets('direct: onConnect zwraca null (anulowano) → zostaje na bramie',
      (tester) async {
    await tester.pumpWidget(_wrap(
        UploadScreen(engine: null, onConnect: () async => null)));
    await tester.tap(find.text('Connect Google Drive'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Google Drive'), findsOneWidget);
    expect(find.text('Pick files'), findsNothing);
  });
}
