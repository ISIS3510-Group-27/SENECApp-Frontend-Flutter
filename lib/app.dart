import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_services.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/phone_frame.dart';
import 'features/auth/session_status_screens.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/verify_email_screen.dart';
import 'features/shell/home_shell.dart';
import 'state/app_state.dart';
import 'state/leave_reminders.dart';
import 'state/outdoor_mode.dart';
import 'state/push_registration.dart';
import 'state/session_controller.dart';

/// Wires the services, session and theme around the navigation shell.
class SenecApp extends StatelessWidget {
  const SenecApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: services),
        ChangeNotifierProvider(
          create: (_) => SessionController(
            auth: services.auth,
            me: services.me,
            api: services.api,
            analytics: services.analytics,
            push: PushRegistration(
              push: services.push,
              notifications: services.notifications,
              platform: services.api.context.platform,
            ),
          )..start(),
        ),
        ChangeNotifierProvider(
          create: (_) => OutdoorMode(
            sensor: services.ambientLight,
            preferences: services.preferences,
          )..start(),
        ),
      ],
      child: MaterialApp(
        title: 'SENECApp',
        debugShowCheckedModeBanner: false,
        // The palette is built for a dark canvas, so the app pins itself there
        // rather than following the system setting.
        theme: AppTheme.dark,
        home: const _SessionGate(),
        builder: (context, child) => PhoneFrame(
          child: OutdoorView(
            mode: context.read<OutdoorMode>(),
            child: child!,
          ),
        ),
      ),
    );
  }
}

/// Shows sign-in until there is a student, then the app.
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    return switch (session.status) {
      SessionStatus.starting ||
      SessionStatus.loadingProfile => const SplashScreen(),
      SessionStatus.signedOut => const SignInScreen(),
      SessionStatus.unverified => const VerifyEmailScreen(),
      SessionStatus.profileFailed => const ProfileLoadFailedScreen(),
      SessionStatus.signedIn => MultiProvider(
        // A different student gets a fresh state, never the previous one's.
        key: ValueKey(session.student!.id),
        providers: [
          ChangeNotifierProvider(
            create: (context) {
              final services = context.read<AppServices>();
              return AppState(
                student: session.student!,
                me: services.me,
                groups: services.groups,
                events: services.events,
                notifications: services.notifications,
                preferences: services.preferences,
              )..load();
            },
          ),
          ChangeNotifierProvider(
            lazy: false,
            create: (context) {
              final services = context.read<AppServices>();
              return LeaveReminders(
                studentId: session.student!.id,
                notifications: services.reminders,
                location: services.location,
                me: services.me,
                catalog: services.catalog,
                locationOptIn: () =>
                    context.read<AppState>().student.locationOptIn,
                preferences: services.preferences,
              )..start();
            },
          ),
        ],
        child: const HomeShell(),
      ),
    };
  }
}
