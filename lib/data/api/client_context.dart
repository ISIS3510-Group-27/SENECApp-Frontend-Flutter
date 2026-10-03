import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Who is calling: the app, its version and the device, plus the current usage
/// session.
///
/// Sent as `X-*` headers on every request so the analytics the backend records
/// (searches, views, joins...) carry the same context as the events the app
/// sends itself. BQ11 and BQ14 break results down by these values.
class ClientContext with WidgetsBindingObserver {
  ClientContext({
    required this.appVersion,
    required this.platform,
    required this.deviceModel,
    required this.osVersion,
    DateTime Function() clock = DateTime.now,
  }) : _clock = clock,
       _sessionId = _newSessionId();

  /// A new session starts when the app comes back after this long in the
  /// background (event taxonomy, section 1).
  static const sessionTimeout = Duration(minutes: 30);

  static const app = 'flutter';

  final String appVersion;

  /// `android`, `ios` or `web`.
  final String platform;

  /// e.g. `samsung SM-A145M`.
  final String deviceModel;

  /// Major OS version, e.g. `14`.
  final String osVersion;

  final DateTime Function() _clock;
  String _sessionId;
  DateTime? _backgroundedAt;

  String get sessionId => _sessionId;

  Map<String, String> get headers => {
    'X-Session-Id': _sessionId,
    'X-App': app,
    'X-App-Version': appVersion,
    'X-Platform': platform,
    'X-Device-Model': deviceModel,
    'X-OS-Version': osVersion,
  };

  /// Reads the app and device details. Anything the platform won't report is
  /// sent as `unknown` rather than blocking launch.
  static Future<ClientContext> load() async {
    var appVersion = 'unknown';
    try {
      appVersion = (await PackageInfo.fromPlatform()).version;
    } on Exception {
      // Keep the placeholder.
    }

    final platform = kIsWeb
        ? 'web'
        : switch (defaultTargetPlatform) {
            TargetPlatform.android => 'android',
            TargetPlatform.iOS => 'ios',
            final other => other.name,
          };

    var deviceModel = 'unknown';
    var osVersion = 'unknown';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final info = await deviceInfo.webBrowserInfo;
        deviceModel = info.browserName.name;
        osVersion = info.platform ?? 'unknown';
      } else if (defaultTargetPlatform == TargetPlatform.android) {
        final info = await deviceInfo.androidInfo;
        deviceModel = '${info.manufacturer} ${info.model}';
        osVersion = _major(info.version.release);
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final info = await deviceInfo.iosInfo;
        deviceModel = info.modelName;
        osVersion = _major(info.systemVersion);
      }
    } on Exception {
      // Keep the placeholders.
    }

    return ClientContext(
      appVersion: appVersion,
      platform: platform,
      deviceModel: deviceModel,
      osVersion: osVersion,
    );
  }

  /// Starts following app lifecycle changes, to rotate the session id.
  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused || AppLifecycleState.hidden:
        _backgroundedAt ??= _clock();
      case AppLifecycleState.resumed:
        final since = _backgroundedAt;
        _backgroundedAt = null;
        if (since != null && _clock().difference(since) >= sessionTimeout) {
          _sessionId = _newSessionId();
        }
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  static String _major(String version) => version.split('.').first;

  static String _newSessionId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
