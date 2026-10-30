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
import 'data/connectivity/connectivity_service.dart';
import 'data/local/cover_cache.dart';
import 'data/local/event_draft_store.dart';
import 'data/local/local_store.dart';
import 'data/local/offline_cache.dart';
import 'data/local/sqlite_local_store.dart';
import 'data/location/location_service.dart';
import 'data/local/cover_outbox_store.dart';
import 'data/local/insight_store.dart';
import 'data/location/maps_service.dart';
import 'data/push/push_service.dart';
import 'data/reminders/reminder_notifications.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/events_repository.dart';
import 'data/repositories/groups_repository.dart';
import 'data/repositories/insights_repository.dart';
import 'data/repositories/me_repository.dart';
import 'data/repositories/notifications_repository.dart';
import 'data/repositories/recommendations_repository.dart';
import 'data/sensors/ambient_light.dart';
import 'state/cover_updates.dart';
import 'data/storage/photo_picker.dart';
import 'firebase_options.dart';

/// The long-lived objects that talk to the outside world, built once at launch.
///
/// Tests build their own with fakes instead of calling [create].
class AppServices {
  AppServices({
    required this.auth,
    required this.api,
    this.preferences,
    this.location = const GeolocatorLocationService(),
    this.maps = const GoogleMapsService(),
    this.qrCamera = mobileScannerCamera,
    Analytics? analytics,
    this.push = const DisabledPushService(),
    this.ambientLight = const NoAmbientLightSensor(),
    this.reminders = const DisabledReminderNotifications(),
    this.photos = const DisabledPhotoPicker(),
    LocalStore store = const NoLocalStore(),
    this.connectivity = const AlwaysConnected(),
    this.covers,
    EventDraftStore? eventDrafts,
    CoverOutboxStore? coverOutbox,
    InsightStore? insightStore,
  }) : analytics = analytics ?? Analytics(api: api, context: api.context),
       eventDrafts = eventDrafts ?? MemoryEventDraftStore(),
       coverOutbox = coverOutbox ?? MemoryCoverOutboxStore(),
       insightStore = insightStore ?? MemoryInsightStore(),
       offline = OfflineCache(store: store),
       recommendations = RecommendationsRepository(api);

  final AuthService auth;
  final ApiClient api;
  final SharedPreferences? preferences;

  /// The phone's GPS.
  final LocationService location;

  /// External maps, opened only after an explicit action.
  final MapsService maps;

  /// The phone's camera, for scanning check-in codes.
  final QrCameraBuilder qrCamera;

  /// Screen views, errors and join forms, for the business questions.
  final Analytics analytics;

  /// Push notifications; switched off until Firebase is configured.
  final PushService push;

  final AmbientLightSensor ambientLight;

  final ReminderNotifications reminders;

  /// Camera and gallery, for group cover photos (uploaded to the backend).
  final PhotoPicker photos;

  /// Group photos on disk, downloaded ahead of time for offline use. None in
  /// tests, which never download images.
  final CoverCache? covers;

  /// Unpublished event forms, isolated by account and group.
  final EventDraftStore eventDrafts;

  final CoverOutboxStore coverOutbox;

  final InsightStore insightStore;

  final CoverUpdates coverUpdates = CoverUpdates();

  /// Whether the phone has a network, and when that changes.
  final ConnectivityService connectivity;

  /// The phone's copy of what the student last saw, used when the backend
  /// can't be reached, and which answers on screen came from it.
  final OfflineCache offline;

  late final MeRepository me = MeRepository(api, cache: offline);
  late final InsightsRepository insights = InsightsRepository(
    api: api,
    store: insightStore,
  );
  late final GroupsRepository groups = GroupsRepository(
    api,
    cache: offline,
    covers: covers,
  );
  late final EventsRepository events = EventsRepository(api, cache: offline);
  late final NotificationsRepository notifications = NotificationsRepository(
    api,
    cache: offline,
  );
  late final CatalogRepository catalog = CatalogRepository(api, cache: offline);
  final RecommendationsRepository recommendations;

  static Future<AppServices> create() async {
    final prefs = await SharedPreferences.getInstance();
    final AuthService auth;
    switch (AppConfig.authMode) {
      case AuthMode.firebase:
        // Reads google-services.json (Android) / GoogleService-Info.plist
        // (iOS), which `flutterfire configure` adds to the project.
        await Firebase.initializeApp(
          options: kIsWeb ? DefaultFirebaseOptions.currentPlatform : null,
        );
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
      ambientLight: const PlatformAmbientLightSensor(),
      reminders: platformReminders(),
      photos: DevicePhotoPicker(),
      // No SQLite in the browser; the web build simply has no offline copy.
      store: kIsWeb ? const NoLocalStore() : SqliteLocalStore(),
      connectivity: PlusConnectivityService(),
      covers: CoverCache(),
      eventDrafts: kIsWeb
          ? PrefsEventDraftStore(prefs)
          : SqliteEventDraftStore(),
      coverOutbox: kIsWeb
          ? MemoryCoverOutboxStore()
          : SqliteCoverOutboxStore(),
      insightStore: kIsWeb ? MemoryInsightStore() : FileInsightStore(),
    );
  }
}
