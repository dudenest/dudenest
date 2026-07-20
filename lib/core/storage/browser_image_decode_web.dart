import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:web/web.dart' as web;

// Dekoduje bajty obrazu przez PRZEGLĄDARKĘ (`createImageBitmap`), która obsługuje wszystko co Chrome —
// w tym avif/heic, których CanvasKit NIE dekoduje. Rysujemy bitmapę na OffscreenCanvas, czytamy piksele
// RGBA i budujemy `ui.Image`. Dzięki temu ImageProvider działa dla KAŻDEGO formatu (siatka + podgląd).
// Uwaga: `createImageBitmap` daje pojedynczą klatkę (animowany GIF → 1. klatka — akceptowalne dla foto).
Future<ui.Image> decodeImageBytes(Uint8List bytes) async {
  final blob = web.Blob([bytes.toJS].toJS);
  final bitmap = await web.window.createImageBitmap(blob).toDart;
  final w = bitmap.width;
  final h = bitmap.height;
  final canvas = web.OffscreenCanvas(w, h);
  final ctx = canvas.getContext('2d') as web.OffscreenCanvasRenderingContext2D;
  ctx.drawImage(bitmap, 0, 0);
  bitmap.close();
  final rgba = ctx.getImageData(0, 0, w, h).data.toDart; // Uint8ClampedList (RGBA, non-premultiplied)
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
      Uint8List.fromList(rgba), w, h, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}
