import 'dart:typed_data';
import 'dart:ui' as ui;

// Nie-web: użyj standardowego dekodera Fluttera (CanvasKit/Skia). Nie obsłuży avif/heic, ale ta ścieżka
// dotyczy tylko platform nie-web (mobile = E1); web używa browser_image_decode_web.
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
