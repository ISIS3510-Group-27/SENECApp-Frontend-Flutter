import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/widgets/phone_frame.dart';
import 'features/shell/home_shell.dart';
import 'state/app_state.dart';

/// Wires the shared state and theme around the navigation shell.
class SenecApp extends StatelessWidget {
  const SenecApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: MaterialApp(
        title: 'SENECApp',
        debugShowCheckedModeBanner: false,
        // The palette is built for a dark canvas, so the app pins itself there
        // rather than following the system setting.
        theme: AppTheme.dark,
        home: const HomeShell(),
        builder: (context, child) => PhoneFrame(child: child!),
      ),
    );
  }
}
