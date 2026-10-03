import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/ids.dart';
import '../api/api_client.dart';
import '../api/client_context.dart';

/// Screen names, as the event taxonomy (`docs/event-taxonomy.md` in the
/// backend) lists them, and the feature each belongs to.
abstract final class Screens {
  static const login = 'login';
  static const discover = 'discover';
  static const groupDetail = 'group_detail';
  static const joinForm = 'join_form';
  static const recommendations = 'recommendations';
  static const freeNow = 'free_now';
  static const events = 'events';
  static const eventDetail = 'event_detail';
  static const checkInScanner = 'check_in_scanner';
  static const notifications = 'notifications';
  static const profile = 'profile';
  static const createGroup = 'create_group';
  static const createEvent = 'create_event';

  // Not in the taxonomy yet; worth adding there.
  static const myGroups = 'my_groups';
  static const schedule = 'schedule';

  /// The `feature` an error on [screen] is filed under (BQ1).
  static String featureOf(String? screen) => switch (screen) {
    login => 'auth',
    discover => 'explore',
    groupDetail => 'group_profile',
    joinForm => 'join',
    recommendations => 'recommendations',
    freeNow => 'free_now',
    events || eventDetail || createEvent => 'events',
    checkInScanner => 'check_in',
    notifications => 'notifications',
    profile || schedule => 'profile',
    createGroup => 'create_group',
    myGroups => 'home',
    _ => 'unknown',
  };
}

/// Where queued events wait to be sent.
abstract interface class AnalyticsStore {
  Future<List<Map<String, dynamic>>> load();
  Future<void> save(List<Map<String, dynamic>> events);
}

/// Keeps nothing between runs. For tests.
class MemoryAnalyticsStore implements AnalyticsStore {
  List<Map<String, dynamic>> saved = [];

  @override
  Future<List<Map<String, dynamic>>> load() async => [...saved];

  @override
  Future<void> save(List<Map<String, dynamic>> events) async =>
      saved = [...events];
}

/// Keeps the queue on the phone, so events recorded offline, or just before
/// a crash, are sent on a later run.
class PrefsAnalyticsStore implements AnalyticsStore {
  PrefsAnalyticsStore(this._prefs);

  static const _key = 'analytics.queue';

  final SharedPreferences _prefs;

  @override
  Future<List<Map<String, dynamic>>> load() async {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    try {
      return [
        for (final event in jsonDecode(raw) as List)
          event as Map<String, dynamic>,
      ];
    } on FormatException {
      return [];
    }
  }

  @override
  Future<void> save(List<Map<String, dynamic>> events) =>
      _prefs.setString(_key, jsonEncode(events));
}

/// The events the app reports itself (`POST /analytics/events`): screen
/// views with load times, errors, and join forms being opened. Everything
/// else is recorded by the backend from the regular API calls.
///
/// Events are queued and sent in batches: every [flushInterval], whenever
/// the app goes to the background, and before signing out.
class Analytics with WidgetsBindingObserver {
  Analytics({
    required ApiClient api,
    required ClientContext context,
    AnalyticsStore? store,
    DateTime Function() clock = DateTime.now,
  }) : _api = api,
       _context = context,
       _store = store ?? MemoryAnalyticsStore(),
       _clock = clock;

  static const flushInterval = Duration(seconds: 30);

  /// The backend takes at most this many per request.
  static const batchSize = 500;

  /// Beyond this, the oldest events are dropped rather than filling the
  /// phone while it stays offline.
  static const maxQueued = 2000;

  final ApiClient _api;
  final ClientContext _context;
  final AnalyticsStore _store;
  final DateTime Function() _clock;

  final List<Map<String, dynamic>> _queue = [];
  Timer? _timer;
  Future<void>? _flushing;
  String? _currentScreen;

  /// Events not sent yet, oldest first.
  List<Map<String, dynamic>> get pending => List.unmodifiable(_queue);

  /// Picks up what a previous run didn't get to send.
  Future<void> restore() async => _queue.insertAll(0, await _store.load());

  /// Starts the periodic and on-background flushes.
  void start() {
    _timer ??= Timer.periodic(flushInterval, (_) => flush());
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      flush();
    }
  }

  // --- Events ----------------------------------------------------------------

  /// A screen finished its first render with data. [loadTime] runs from the
  /// moment it was shown; it's left out when the student comes back to a
  /// screen that was already loaded (BQ1 counts it, BQ11 doesn't).
  void screenView(String screen, {Duration? loadTime}) {
    _currentScreen = screen;
    _record(
      'screen_view',
      screen: screen,
      properties: {'load_time_ms': ?loadTime?.inMilliseconds},
    );
  }

  /// An error the student saw, or a crash ([fatal]). Filed under [screen],
  /// or the last screen viewed. Only the backend's own messages are sent:
  /// other exception texts can carry personal data.
  void error(Object error, {String? screen, bool fatal = false}) {
    final at = screen ?? _currentScreen;
    _record(
      'app_error',
      screen: at,
      properties: {
        'feature': Screens.featureOf(at),
        'error_type': error.runtimeType.toString(),
        'fatal': fatal,
        if (error is ApiException) ...{
          'status_code': error.statusCode,
          'message': error.message.length > 200
              ? error.message.substring(0, 200)
              : error.message,
        },
      },
    );
  }

  /// The join form was shown. [joinAttemptId] goes with the submission too,
  /// which is how BQ7 follows one attempt from form to join.
  void joinFormOpened({required int groupId, required String joinAttemptId}) =>
      _record(
        'join_form_opened',
        screen: Screens.joinForm,
        properties: {'group_id': groupId, 'join_attempt_id': joinAttemptId},
      );

  void _record(
    String name, {
    String? screen,
    Map<String, Object?> properties = const {},
  }) {
    _queue.add({
      'event_id': newUuid(),
      'name': name,
      'occurred_at': _clock().toUtc().toIso8601String(),
      'session_id': _context.sessionId,
      'screen': ?screen,
      'app': ClientContext.app,
      'app_version': _context.appVersion,
      // The backend only knows these two; anything else (a browser) would
      // get the whole batch rejected.
      if (_context.platform == 'android' || _context.platform == 'ios')
        'platform': _context.platform,
      'device_model': _context.deviceModel,
      'os_version': _context.osVersion,
      'properties': properties,
    });
    // Trimming while a batch is in flight would shift what it removes after.
    if (_flushing == null && _queue.length > maxQueued) {
      _queue.removeRange(0, _queue.length - maxQueued);
    }
    _store.save(_queue);
  }

  // --- Sending ---------------------------------------------------------------

  /// Sends everything queued. Safe to call any time: overlapping calls share
  /// one send, and a batch that fails stays queued for the next try.
  Future<void> flush() =>
      _flushing ??= _send().whenComplete(() => _flushing = null);

  Future<void> _send() async {
    while (_queue.isNotEmpty) {
      final batch = _queue.take(batchSize).toList();
      try {
        await _api.post('/analytics/events', body: {'events': batch});
      } on ApiException catch (e) {
        final status = e.statusCode;
        // Offline, server trouble, or signed out mid-way: try again later.
        // Any other refusal won't change on a retry; dropping the batch keeps
        // it from blocking everything queued after it.
        final retry =
            status == null || status >= 500 || status == 401 || status == 429;
        if (retry) return;
      }
      _queue.removeRange(0, batch.length);
      await _store.save(_queue);
    }
  }
}
