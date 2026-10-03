import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../data/analytics/analytics.dart';
import '../../data/auth/auth_service.dart';
import '../../state/session_controller.dart';
import '../shell/track_screen.dart';
import 'auth_widgets.dart';

/// Waits for the student to click the verification link. The backend only
/// accepts verified university emails.
class VerifyEmailScreen extends StatelessWidget {
  const VerifyEmailScreen({super.key});

  Future<void> _resend(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<SessionController>().resendVerification();
      messenger.showSnackBar(
        const SnackBar(content: Text('Sent! Check your inbox and spam.')),
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) =>
      TrackScreen(name: Screens.login, child: _buildScreen(context));

  Widget _buildScreen(BuildContext context) {
    final session = context.watch<SessionController>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 32, kPageGutter, 32),
          children: [
            AuthHeader(
              title: 'Check your inbox',
              subtitle:
                  'We sent a verification link to '
                  '${session.pendingEmail ?? 'your email'}. Open it, then '
                  'come back here.',
            ),
            if (session.error case final error?) ...[
              const SizedBox(height: 20),
              AuthMessage.error(error),
            ],
            const SizedBox(height: 28),
            PrimaryButton(
              label: "I've verified my email",
              busy: session.busy,
              onPressed: session.checkVerified,
            ),
            const SizedBox(height: 12),
            PrimaryButton.secondary(
              label: 'Resend email',
              onPressed: session.busy ? null : () => _resend(context),
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: session.busy ? null : session.signOut,
                child: Text(
                  'Use another account',
                  style: AppTheme.body(
                    size: 13,
                    weight: FontWeight.w700,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
