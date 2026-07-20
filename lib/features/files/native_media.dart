// Natywny render mediów (blob URL + <img>/platform view). Web → native_media_web; nie-web → stub.
export 'native_media_stub.dart' if (dart.library.js_interop) 'native_media_web.dart';
