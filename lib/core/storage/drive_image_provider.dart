import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'browser_image_decode.dart';

/// ImageProvider, który ładuje bajty obrazu z asynchronicznego loadera.
///
/// Powód (E3, 2026-07-17): `StorageEngine.thumbnail/preview/original` musi zwracać `ImageProvider`,
/// a `DirectEngine` (Google Drive) NIE ma gotowego URL-a z nagłówkiem auth pod goły `NetworkImage`
/// — pobranie miniatury z Drive wymaga (a) tokenu OAuth i (b) czasem dwóch żądań (metadata→link).
/// [obtainKey] jest synchroniczne (kontrakt ImageProvider), więc całą asynchronię (token, HTTP)
/// zamykamy w [loader], który odpala się dopiero w [loadImage].
///
/// [cacheKey] MUSI być stabilny per (plik + wariant), bo to on decyduje o trafieniu w Flutterowy
/// `imageCache` — dwa różne warianty tego samego pliku (thumb vs preview) muszą mieć różne klucze.
@immutable
class DriveImageProvider extends ImageProvider<DriveImageProvider> {
  final String cacheKey;
  final Future<Uint8List> Function() loader;
  final double scale;

  const DriveImageProvider(this.cacheKey, this.loader, {this.scale = 1.0});

  @override
  Future<DriveImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<DriveImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
      DriveImageProvider key, ImageDecoderCallback decode) {
    // OneFrame + dekoder PRZEGLĄDARKI (nie CanvasKit `decode`), bo tylko przeglądarka dekoduje avif/heic.
    return OneFrameImageStreamCompleter(
      _load(key),
      informationCollector: () => [DiagnosticsProperty('cacheKey', cacheKey)],
    );
  }

  Future<ImageInfo> _load(DriveImageProvider key) async {
    final bytes = await key.loader();
    if (bytes.isEmpty) {
      throw StateError('DriveImageProvider($cacheKey): empty image bytes');
    }
    final image = await decodeImageBytes(bytes); // browser-decode → obsługuje avif/heic
    return ImageInfo(image: image, scale: key.scale);
  }

  @override
  bool operator ==(Object other) =>
      other is DriveImageProvider && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;

  @override
  String toString() => 'DriveImageProvider("$cacheKey")';
}
