import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/primary_button.dart';
import '../../core/widgets/surfaces.dart';
import '../../state/session_controller.dart';
import 'auth_widgets.dart';

/// Sign in, or create an account, with a university email.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  /// The seeded student from the backend's demo data, for dev sign-in.
  static const demoEmail = 's.arango@uniandes.edu.co';

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _registering = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    FocusScope.of(context).unfocus();
    final session = context.read<SessionController>();
    if (_registering) {
      session.register(email: _email.text, password: _password.text);
    } else {
      session.signIn(email: _email.text, password: _password.text);
    }
  }

  void _useDemoStudent() {
    _email.text = SignInScreen.demoEmail;
    _submit();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final devMode = AppConfig.authMode == AuthMode.dev;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(kPageGutter, 32, kPageGutter, 32),
          children: [
            AuthHeader(
              title: _registering ? 'Create your account' : 'Welcome back',
              subtitle: _registering
                  ? "Use your university email. We'll send you a link to "
                        'verify it.'
                  : 'Sign in with your university account to find your '
                        'people on campus.',
            ),
            const SizedBox(height: 28),
            if (devMode) ...[
              const AuthMessage.info(
                'Developer sign-in: any @${AppConfig.allowedEmailDomain} '
                'email, no password. The backend must run with '
                'AUTH_PROVIDER=dev.',
              ),
              const SizedBox(height: 20),
            ],
            const SectionLabel(text: 'University email'),
            const SizedBox(height: 10),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              textInputAction: session.requiresPassword
                  ? TextInputAction.next
                  : TextInputAction.done,
              onSubmitted: session.requiresPassword ? null : (_) => _submit(),
              style: AppTheme.body(size: 14),
              decoration: const InputDecoration(
                hintText: 'you@${AppConfig.allowedEmailDomain}',
              ),
            ),
            if (session.requiresPassword) ...[
              const SizedBox(height: 20),
              const SectionLabel(text: 'Password'),
              const SizedBox(height: 10),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                autofillHints: [
                  _registering
                      ? AutofillHints.newPassword
                      : AutofillHints.password,
                ],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: AppTheme.body(size: 14),
                decoration: InputDecoration(
                  hintText: _registering ? 'At least 6 characters' : null,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                    ),
                    color: AppColors.mutedForeground,
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            ],
            if (session.error case final error?) ...[
              const SizedBox(height: 16),
              AuthMessage.error(error),
            ],
            const SizedBox(height: 24),
            PrimaryButton(
              label: _registering ? 'Create account' : 'Sign in',
              busy: session.busy,
              onPressed: _submit,
            ),
            if (devMode) ...[
              const SizedBox(height: 12),
              PrimaryButton.secondary(
                label: 'Use demo student',
                onPressed: session.busy ? null : _useDemoStudent,
              ),
            ],
            if (session.supportsRegistration) ...[
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: session.busy
                      ? null
                      : () => setState(() => _registering = !_registering),
                  child: Text(
                    _registering
                        ? 'Already have an account? Sign in'
                        : 'New to SENECApp? Create an account',
                    style: AppTheme.body(
                      size: 13,
                      weight: FontWeight.w700,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
