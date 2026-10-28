import 'dart:convert';

import 'package:flutter/foundation.dart';

/// JSON work that is moved off the UI thread when it is big enough to matter.
///
/// Flutter draws a frame every 16 ms on the main isolate. Decoding a long
/// list (50 events, the whole Explore page, a saved inbox) can take longer
/// than that on a cheap phone, which shows as a stutter while scrolling or
/// during a page transition. Above [threshold] the work runs on a short-lived
/// background isolate through [compute] (`Isolate.run` on phones): it has its
/// own memory, so nothing is shared or locked, and its result is handed back
/// with `Isolate.exit`, which transfers it without copying.
///
/// Below [threshold] it stays on the main isolate: starting an isolate costs
/// about a millisecond, more than decoding a small answer. On the web, which
/// has no isolates, [compute] runs the same function inline.
abstract final class BackgroundJson {
  /// Bytes (or characters) from which a background isolate pays off. A list
  /// of ~20 groups or events is about this size.
  static const threshold = 16 * 1024;

  /// Decodes a UTF-8 JSON body, as received from the backend.
  static Future<Object?> decodeBytes(Uint8List bytes) async {
    if (bytes.isEmpty) return null;
    if (bytes.length < threshold) return _decodeBytes(bytes);
    return compute(_decodeBytes, bytes, debugLabel: 'decode JSON');
  }

  /// Decodes many JSON documents at once (rows read from the database).
  static Future<List<Object?>> decodeAll(List<String> texts) async {
    final size = texts.fold(0, (sum, text) => sum + text.length);
    if (size < threshold) return _decodeAll(texts);
    return compute(_decodeAll, texts, debugLabel: 'decode rows');
  }

  /// Encodes many values at once (rows about to be written to the database).
  static Future<List<String>> encodeAll(List<Object?> values) async {
    if (values.length < 20) return _encodeAll(values);
    return compute(_encodeAll, values, debugLabel: 'encode rows');
  }

  // Top-level-style (static) functions: what runs on the other isolate can't
  // capture anything from this one.
  static Object? _decodeBytes(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes));

  static List<Object?> _decodeAll(List<String> texts) => [
    for (final text in texts) jsonDecode(text),
  ];

  static List<String> _encodeAll(List<Object?> values) => [
    for (final value in values) jsonEncode(value),
  ];
}
