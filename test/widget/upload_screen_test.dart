import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dudenest/core/network/relay_client.dart';
import 'package:dudenest/features/upload/upload_screen.dart';

RelayClient _relay(MockClientHandler h) =>
    RelayClient('http://relay.test', client: MockClient(h));

Widget _wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('shows empty state initially', (tester) async {
    final relay = _relay((_) async => http.Response('{}', 200));
    await tester.pumpWidget(_wrap(UploadScreen(relay: relay)));
    expect(find.text('No uploads yet'), findsOneWidget);
    expect(find.text('Pick files'), findsOneWidget);
  });

  testWidgets('shows Pick files button', (tester) async {
    final relay = _relay((_) async => http.Response('{}', 200));
    await tester.pumpWidget(_wrap(UploadScreen(relay: relay)));
    expect(find.byIcon(Icons.upload_file), findsOneWidget);
  });

  testWidgets('Upload button is always enabled (file picker opens on tap)',
      (tester) async {
    final relay = _relay((_) async => http.Response('{}', 200));
    await tester.pumpWidget(_wrap(UploadScreen(relay: relay)));
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

    await tester.pumpWidget(_wrap(UploadScreen(relay: null, picker: picker)));
    await tester.pumpWidget(
        _wrap(UploadScreen(relay: null, picker: picker, autoPickNonce: 1)));
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
        _wrap(UploadScreen(relay: null, picker: picker, autoPickNonce: 1)));
    await tester.pumpAndSettle();
    expect(picks, 1);
    expect(find.text('first.jpg'), findsOneWidget);
  });
}
