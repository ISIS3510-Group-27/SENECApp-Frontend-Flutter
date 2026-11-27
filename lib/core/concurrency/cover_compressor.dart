import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

abstract final class CoverCompressor {
  static const maxSide = 1280;
  static const quality = 80;

  static Future<Uint8List> compress(Uint8List bytes) =>
      compute(shrink, bytes, debugLabel: 'compress cover');

  @visibleForTesting
  static Uint8List shrink(Uint8List bytes) {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } on Object {
      return bytes;
    }
    if (decoded == null) return bytes;
    final longest = max(decoded.width, decoded.height);
    final resized = longest <= maxSide
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxSide : null,
            height: decoded.height > decoded.width ? maxSide : null,
          );
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }
}
