import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'data/api/api_client.dart';
import 'data/api/client_context.dart';
import 'data/auth/auth_service.dart';
import 'data/auth/dev_auth_service.dart';
import 'data/auth/firebase_auth_service.dart';
import 'data/repositories/me_repository.dart';

/// The long-lived objects that talk to the outside world, built once at launch.
///
/// Tests build their own with fakes instead of calling [create].
class AppServices {
  AppServices({required this.auth, required this.api}) : me = MeRepository(api);

  final AuthService auth;
  final ApiClient api;
  final MeRepository me;

  static Future<AppServices> create() async {
    final AuthService auth;
    switch (AppConfig.authMode) {
      case AuthMode.firebase:
        // Reads google-services.json (Android) / GoogleService-Info.plist
        // (iOS), which `flutterfire configure` adds to the project.
        await Firebase.initializeApp();
        auth = FirebaseAuthService();
      case AuthMode.dev:
        auth = DevAuthService(await SharedPreferences.getInstance());
    }

    final context = await ClientContext.load()
      ..attach();

    return AppServices(
      auth: auth,
      api: ApiClient(
        baseUrl: AppConfig.apiBaseUrl,
        auth: auth,
        context: context,
      ),
    );
  }
}
