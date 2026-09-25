import 'package:flutter/material.dart';

import '../../data/models/rso.dart';
import '../assets/asset_catalog.dart';
import '../theme/app_colors.dart';

/// An organization's photo, with a graceful stand-in when there isn't one.
///
/// The fallback is not a grey box: it is a gradient in the organization's own
/// colour with its category icon, so an art-less build still reads as designed
/// rather than as broken. See `docs/IMAGE_SPEC.md` for how to add the real art.
class OrgImage extends StatelessWidget {
  const OrgImage({super.key, required this.rso, this.iconSize = 28});

  final Rso rso;

  /// Size of the category glyph in the fallback. Tune it per call site: small
  /// on a 56px list tile, larger on a detail cover.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final path = AssetCatalog.orgImage(rso.imageSlug);
    if (path == null) return _Fallback(rso: rso, iconSize: iconSize);

    return Image.asset(
      path,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => _Fallback(rso: rso, iconSize: iconSize),
    );
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
