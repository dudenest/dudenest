import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Icons;

// Nie-web: natywny render przez <img>/blob dotyczy tylko web. Stub istnieje dla kompilacji na
// wszystkich platformach (mobile użyje innej ścieżki w E1).

String makeObjectUrl(Uint8List bytes, String mime) =>
    throw UnsupportedError('makeObjectUrl: tylko web');

void revokeObjectUrl(String url) {}

class NativeImageView extends StatelessWidget {
  final String objectUrl;
  const NativeImageView({super.key, required this.objectUrl});
  @override
  Widget build(BuildContext context) =>
      const Center(child: Icon(Icons.broken_image, color: Color(0xFF404040)));
}
