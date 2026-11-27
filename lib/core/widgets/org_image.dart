import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/local/cover_cache.dart';
import '../../data/models/rso.dart';
import '../../state/cover_updates.dart';
import '../assets/asset_catalog.dart';
import '../theme/app_colors.dart';

/// An organization's photo, with a graceful stand-in when there isn't one.
///
/// gradient in the organization's own colour with its category icon, so an
/// art-less group still reads as designed rather than as broken. See
/// `docs/IMAGE_SPEC.md` for how to add the real art.
class OrgImage extends StatelessWidget {
  const OrgImage({super.key, required this.rso, this.iconSize = 28});

  final Rso rso;

  /// Size of the category glyph in the fallback. Tune it per call site: small
  /// on a 56px list tile, larger on a detail cover.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    // Micro-optimization (Sprint 4): decode the photo at the size it's drawn,
    // not at the file's size. A 900x600 cover decoded in full takes ~2.1 MB of
    // the image cache even on a 56 px list tile; decoded at the tile's size
    // in physical pixels it takes a few KB, so dozens of covers fit in the
    // cache instead of a handful, and scrolling doesn't evict and re-decode.
    return LayoutBuilder(
      builder: (context, constraints) =>
          _image(context, _decodeWidth(context, constraints)),
    );
  }

  /// The drawn width in physical pixels, rounded up to a multiple of 64 so
  /// slightly different layouts share one decoded copy; `null` (full size)
  /// when the width isn't bounded.
  static int? _decodeWidth(BuildContext context, BoxConstraints constraints) {
    // Covers are 3:2 and drawn with BoxFit.cover, so a slot taller than 3:2
    // (a square tile) crops the sides and needs 1.5x its height in width.
    final fromWidth = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final fromHeight = constraints.hasBoundedHeight
        ? constraints.maxHeight * 1.5
        : 0.0;
    final width = fromWidth > fromHeight ? fromWidth : fromHeight;
    if (width == 0) return null;
    final pixels = width * MediaQuery.devicePixelRatioOf(context);
    return ((pixels / 64).ceil() * 64).clamp(64, 2048);
  }

  Widget _image(BuildContext context, int? decodeWidth) {
    final fallback = _Fallback(rso: rso, iconSize: iconSize);

    // An uploaded photo, from the phone's copy when it's there.
    final fresh = context.watch<CoverUpdates?>()?.latest(rso.id);
    if (fresh ?? CoverCache.urlFor(rso) case final url?) {
      return CachedNetworkImage(
        imageUrl: url,
        cacheManager: CoverCache.shared,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        memCacheWidth: decodeWidth,
        // The gradient shows while the photo downloads, and stays if it fails
        // (offline, and never downloaded before).
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      );
    }

    if (AssetCatalog.orgImage(rso.imageSlug) case final path?) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        cacheWidth: decodeWidth,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return fallback;
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.rso, required this.iconSize});

  final Rso rso;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            rso.color.withValues(alpha: 0.55),
            rso.color.withValues(alpha: 0.18),
            AppColors.card,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          rso.category.icon,
          size: iconSize,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}
