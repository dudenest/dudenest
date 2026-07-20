import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

// Render mediów przez NATYWNE elementy przeglądarki (<img>/<video>) z blob URL. Powód: Flutter web/
// CanvasKit NIE dekoduje avif/heic (ani nie odtwarza wideo), a przeglądarka Chrome dekoduje wszystko
// natywnie. Bajty pobieramy tokenem (DirectEngine.downloadFile — <img>/<video> nie ustawią nagłówka
// Authorization), robimy blob URL i podajemy natywnemu elementowi przez platform view.

/// Tworzy blob URL z bajtów. Zwolnij przez [revokeObjectUrl] gdy niepotrzebny (przeciek pamięci inaczej).
String makeObjectUrl(Uint8List bytes, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  return web.URL.createObjectURL(blob);
}

void revokeObjectUrl(String url) => web.URL.revokeObjectURL(url);

/// `<img>` przez platform view — renderuje formaty, których CanvasKit nie dekoduje (avif/heic/…),
/// bo dekoduje je natywnie przeglądarka.
class NativeImageView extends StatefulWidget {
  final String objectUrl;
  const NativeImageView({super.key, required this.objectUrl});
  @override
  State<NativeImageView> createState() => _NativeImageViewState();
}

class _NativeImageViewState extends State<NativeImageView> {
  late final String _viewType;
  @override
  void initState() {
    super.initState();
    _viewType = 'dnest-img-${widget.objectUrl.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) {
      return web.HTMLImageElement()
        ..src = widget.objectUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain';
    });
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _viewType);
}
