// Stub for non-web platforms (tests, native iOS/Android/desktop)
import 'dart:io';
import 'dart:typed_data';

String getLocationHref() => 'http://localhost/';
void setLocationHref(String url) {}
void historyReplaceState(String url) {}

// Native: save bytes to temp file
Future<void> downloadBytes(String filename, Uint8List bytes) async {
  final tmpPath = '${Directory.systemTemp.path}/$filename';
  await File(tmpPath).writeAsBytes(bytes);
}
