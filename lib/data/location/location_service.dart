import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Why the phone's position isn't available.
enum LocationProblem {
  /// The student said no; asking again shows the system prompt.
  denied,

  /// The student said "don't ask again"; only the system settings can undo
  /// it.
  deniedForever,

  /// Location is switched off for the whole phone.
  serviceOff,

  /// Allowed, but no fix arrived in time (indoors, emulator without a
  /// location...).
  unavailable,
}

/// A position, or the reason there isn't one.
@immutable
class LocationResult {
  const LocationResult.found(double this.latitude, double this.longitude)
    : problem = null;

  const LocationResult.failed(LocationProblem this.problem)
    : latitude = null,
      longitude = null;

  final double? latitude;
  final double? longitude;
  final LocationProblem? problem;

  bool get found => problem == null;
}

/// The phone's GPS: the sensor behind "Free right now".
abstract interface class LocationService {
  /// Asks for permission if it hasn't been decided yet, then reads the
  /// current position.
  Future<LocationResult> current();

  /// Opens the system settings where a permanent "no", or location switched
  /// off, can be changed.
  Future<void> openSettings(LocationProblem problem);
}

/// [LocationService] on top of the `geolocator` plugin.
class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  /// A walking-distance answer doesn't need more than this; waiting longer
  /// for a better fix only delays the suggestions.
  static const _timeLimit = Duration(seconds: 10);

  @override
  Future<LocationResult> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const LocationResult.failed(LocationProblem.serviceOff);
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      switch (permission) {
        case LocationPermission.denied:
          return const LocationResult.failed(LocationProblem.denied);
        case LocationPermission.deniedForever:
          return const LocationResult.failed(LocationProblem.deniedForever);
        case LocationPermission.whileInUse ||
            LocationPermission.always ||
            LocationPermission.unableToDetermine:
          break;
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: _timeLimit,
          ),
        );
        return LocationResult.found(position.latitude, position.longitude);
      } on TimeoutException {
        // A recent fix is still good enough to say which building is close.
        final last = kIsWeb ? null : await Geolocator.getLastKnownPosition();
        return last == null
            ? const LocationResult.failed(LocationProblem.unavailable)
            : LocationResult.found(last.latitude, last.longitude);
      }
    } on Exception {
      return const LocationResult.failed(LocationProblem.unavailable);
    }
  }

  @override
  Future<void> openSettings(LocationProblem problem) async {
    if (problem == LocationProblem.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
