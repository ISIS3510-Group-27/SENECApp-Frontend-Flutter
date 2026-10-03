import 'package:flutter/material.dart';

import '../../data/models/rso.dart';
import '../assets/asset_catalog.dart';
import '../theme/app_colors.dart';

/// An organization's photo, with a graceful stand-in when there isn't one.
///
/// Bundled art wins (it's curated and works offline), then the photo the
/// backend hosts, then the fallback. The fallback is not a grey box: it is a
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
    final fallback = _Fallback(rso: rso, iconSize: iconSize);

    if (AssetCatalog.orgImage(rso.imageSlug) case final path?) {
      return Image.asset(
        path,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    if (rso.imageUrl case final url?) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        // The gradient shows while the photo downloads, and stays if it fails.
        frameBuilder: (_, child, frame, wasSynchronouslyLoaded) =>
            frame == null && !wasSynchronouslyLoaded ? fallback : child,
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
