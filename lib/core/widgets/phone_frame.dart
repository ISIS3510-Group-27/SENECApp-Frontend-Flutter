import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Presents the app inside a phone-sized frame when the window is too wide to
/// be a phone.
///
/// On a real device this is a no-op - [child] fills the screen as it should.
/// It exists so `flutter run -d chrome` shows the app at its design width of
/// 390x844 instead of a stretched tablet layout, which is what makes the
/// browser a usable stand-in while the Android SDK is being installed.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  static const designWidth = 390.0;
  static const designHeight = 844.0;

  /// Below this the window is phone-shaped already and the frame steps aside.
  static const _frameAbove = 620.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < _frameAbove) return child;

    final height = size.height.clamp(0.0, designHeight);

    return ColoredBox(
      color: AppColors.canvas,
      child: Center(
        child: Container(
          width: designWidth,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(44),
            border: Border.all(color: AppColors.secondary, width: 2),
            boxShadow: const [
              BoxShadow(
                color: Color(0xCC000000),
                blurRadius: 80,
                offset: Offset(0, 40),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            child: child,
          ),
        ),
      ),
    );
  }
}
