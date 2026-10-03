import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/config/app_config.dart';
import 'core/widgets/qr_camera.dart';
import 'data/analytics/analytics.dart';
import 'data/api/api_client.dart';
import 'data/api/client_context.dart';
import 'data/auth/auth_service.dart';
import 'data/auth/dev_auth_service.dart';
import 'data/auth/firebase_auth_service.dart';
import 'data/location/location_service.dart';
import 'data/push/push_service.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/events_repository.dart';
import 'data/repositories/groups_repository.dart';
import 'data/repositories/me_repository.dart';
import 'data/repositories/notifications_repository.dart';
import 'data/repositories/recommendations_repository.dart';

/// The long-lived objects that talk to the outside world, built once at launch.
///
/// Tests build their own with fakes instead of calling [create].
class AppServices {
  AppServices({
    required this.auth,
    required this.api,
    this.preferences,
    this.location = const GeolocatorLocationService(),
    this.qrCamera = mobileScannerCamera,
    Analytics? analytics,
    this.push = const DisabledPushService(),
  }) : analytics = analytics ?? Analytics(api: api, context: api.context),
       me = MeRepository(api),
       groups = GroupsRepository(api),
       events = EventsRepository(api),
       notifications = NotificationsRepository(api),
       catalog = CatalogRepository(api),
       recommendations = RecommendationsRepository(api);

  final AuthService auth;
  final ApiClient api;
  final SharedPreferences? preferences;

  /// The phone's GPS.
  final LocationService location;

  /// The phone's camera, for scanning check-in codes.
  final QrCameraBuilder qrCamera;

  /// Screen views, errors and join forms, for the business questions.
  final Analytics analytics;

  /// Push notifications; switched off until Firebase is configured.
  final PushService push;

  final MeRepository me;
  final GroupsRepository groups;
  final EventsRepository events;
  final NotificationsRepository notifications;
  final CatalogRepository catalog;
  final RecommendationsRepository recommendations;

  static Future<AppServices> create() async {
    final prefs = await SharedPreferences.getInstance();
    final AuthService auth;
    switch (AppConfig.authMode) {
      case AuthMode.firebase:
        // Reads google-services.json (Android) / GoogleService-Info.plist
        // (iOS), which `flutterfire configure` adds to the project.
        await Firebase.initializeApp();
        auth = FirebaseAuthService();
      case AuthMode.dev:
        auth = DevAuthService(prefs);
    }

    final context = await ClientContext.load()
      ..attach();

    final api = ApiClient(
      baseUrl: AppConfig.apiBaseUrl,
      auth: auth,
      context: context,
    );

    // Whatever the last run couldn't send (offline, or a crash) goes first.
    final analytics = Analytics(
      api: api,
      context: context,
      store: PrefsAnalyticsStore(prefs),
    );
    await analytics.restore();
    analytics
      ..start()
      ..flush();

    return AppServices(
      auth: auth,
      api: api,
      preferences: prefs,
      analytics: analytics,
      // Firebase was initialized above, with sign-in.
      push: AppConfig.firebaseEnabled && !kIsWeb
          ? FirebasePushService()
          : const DisabledPushService(),
    );
  }
}
