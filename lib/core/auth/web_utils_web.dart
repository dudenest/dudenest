import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

String getLocationHref() => web.window.location.href;
void setLocationHref(String url) { web.window.location.href = url; }
void historyReplaceState(String url) { web.window.history.replaceState(null, '', url); }

// Web: trigger browser "Save As" dialog via blob URL
Future<void> downloadBytes(String filename, Uint8List bytes) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.document.createElement('a') as web.HTMLAnchorElement;
  a.href = url;
  a.download = filename;
  web.document.body!.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
}
