// Dekoder obrazu z bajtów. Web → przeglądarka (createImageBitmap, obsługuje avif/heic); nie-web → stub (Skia).
export 'browser_image_decode_stub.dart'
    if (dart.library.js_interop) 'browser_image_decode_web.dart';
