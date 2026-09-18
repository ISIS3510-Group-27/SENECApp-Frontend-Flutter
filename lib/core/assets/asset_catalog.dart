import 'package:flutter/services.dart';

/// Brand art that ships with the repository.
abstract final class BrandAssets {
  static const logo = 'assets/images/brand/senecapp_logo.jpeg';
  static const mascot67 = 'assets/images/brand/senecapp_67.jpeg';
  static const mascotHat = 'assets/images/brand/senecapp_hat.jpeg';
}

/// Knows which organization photos are actually bundled.
///
/// Organization art is added over time, so rather than let a missing file throw
/// on every frame, the app reads the asset manifest once at startup and asks
/// this class before trying to load anything. Whatever is absent falls back to
/// a brand-coloured gradient, and the app never looks broken mid-demo.
abstract final class AssetCatalog {
  static const _orgDirectory = 'assets/images/orgs';

  /// Tried in order, so a `.png` drop-in works without touching code.
  static const _extensions = ['.jpg', '.jpeg', '.png', '.webp'];

  static Set<String> _available = const {};

  /// Reads the asset manifest. Call once, before `runApp`.
  static Future<void> load() async {
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      _available = manifest.listAssets().toSet();
    } on Exception {
      // No manifest is not worth failing to launch over: every organization
      // simply renders its gradient fallback.
      _available = const {};
    }
  }

  /// The bundled path for an organization's photo, or `null` if it has not
  /// been added yet.
  static String? orgImage(String slug) {
    for (final extension in _extensions) {
      final path = '$_orgDirectory/$slug$extension';
      if (_available.contains(path)) return path;
    }
    return null;
  }
}
