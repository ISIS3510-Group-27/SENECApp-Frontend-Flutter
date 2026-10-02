import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/assets/asset_catalog.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../state/session_controller.dart';

/// Shown while the previous session is restored and the profile loads.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.hero),
              child: Image.asset(
                BrandAssets.logo,
                width: 96,
                height: 96,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: AppColors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The student is signed in but `GET /me` failed, usually because the phone
/// is offline or the backend is down.
class ProfileLoadFailedScreen extends StatelessWidget {
  const ProfileLoadFailedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(kPageGutter),
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                size: 44,
                color: AppColors.mutedForeground,
              ),
              const SizedBox(height: 16),
              Text(
                "Can't load your profile",
                textAlign: TextAlign.center,
                style: AppTheme.heading(size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                session.error ?? 'Something went wrong.',
                textAlign: TextAlign.center,
                style: AppTheme.body(
                  size: 13,
                  height: 1.4,
                  color: AppColors.mutedForeground,
                ),
              ),
              // Saves the team a guess when the emulator can't see the laptop.
              if (kDebugMode) ...[
                const SizedBox(height: 6),
                Text(
                  'Backend: ${AppConfig.apiBaseUrl}',
                  textAlign: TextAlign.center,
                  style: AppTheme.body(
                    size: 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ],
              const SizedBox(height: 28),
              PrimaryButton(label: 'Try again', onPressed: session.retry),
              const SizedBox(height: 12),
              PrimaryButton.secondary(
                label: 'Sign out',
                onPressed: session.signOut,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
