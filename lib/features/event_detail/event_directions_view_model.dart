import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/location/location_service.dart';
import '../../data/location/maps_service.dart';
import '../../data/models/campus_event.dart';

/// One-shot GPS for an event. Nothing is read on open, saved or sent to the
/// backend; the origin is shared with Maps only when the student opens a route.
class EventDirectionsViewModel extends ChangeNotifier {
  EventDirectionsViewModel({
    required this.event,
    required LocationService location,
    required MapsService maps,
  }) : _location = location,
       _maps = maps;

  final CampusEvent event;
  final LocationService _location;
  final MapsService _maps;
  bool _disposed = false;
  bool _locating = false;
  bool _opening = false;
  MapCoordinates? _origin;
  LocationProblem? _problem;
  String? _error;

  static bool _valid(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static MapCoordinates? destinationFor(CampusEvent event) =>
      _valid(event.buildingLatitude, event.buildingLongitude)
      ? (latitude: event.buildingLatitude!, longitude: event.buildingLongitude!)
      : null;

  MapCoordinates? get destination => destinationFor(event);
  bool get available => destination != null && !event.isCancelled;
  bool get locating => _locating;
  bool get opening => _opening;
  bool get hasOrigin => _origin != null;
  LocationProblem? get problem => _problem;
  String? get error => _error;

  /// Geodesic distance, not the length of a pedestrian route or an ETA.
  double? get distanceMeters {
    final origin = _origin;
    final target = destination;
    if (origin == null || target == null) return null;
    return Geolocator.distanceBetween(
      origin.latitude,
      origin.longitude,
      target.latitude,
      target.longitude,
    );
  }

  Future<void> locate() async {
    if (!available || _locating || _opening || _disposed) return;
    _locating = true;
    _origin = null;
    _problem = null;
    _error = null;
    notifyListeners();
    try {
      final fix = await _location.current();
      if (_disposed) return;
      if (fix.found && _valid(fix.latitude, fix.longitude)) {
        _origin = (latitude: fix.latitude!, longitude: fix.longitude!);
      } else {
        _problem = fix.problem ?? LocationProblem.unavailable;
      }
    } on Exception {
      if (!_disposed) _problem = LocationProblem.unavailable;
    } finally {
      if (!_disposed) {
        _locating = false;
        notifyListeners();
      }
    }
  }

  Future<void> openSettings() async {
    final problem = _problem;
    if (_disposed ||
        (problem != LocationProblem.deniedForever &&
            problem != LocationProblem.serviceOff)) {
      return;
    }
    try {
      await _location.openSettings(problem!);
    } on Exception {
      if (_disposed) return;
      _error = "Couldn't open location settings.";
      notifyListeners();
    }
  }

  Future<void> openPlace() => _open(walking: false);
  Future<void> openWalkingRoute() => _open(walking: true);

  Future<void> _open({required bool walking}) async {
    final target = destination;
    final origin = _origin;
    if (!available || _opening || _locating || _disposed) return;
    if (walking && origin == null) return;
    _opening = true;
    _error = null;
    notifyListeners();
    try {
      final opened = walking
          ? await _maps.openWalkingRoute(origin: origin!, destination: target!)
          : await _maps.openPlace(target!);
      if (!opened && !_disposed) {
        _error = "Couldn't open Google Maps. Try again.";
      }
    } on Exception {
      if (!_disposed) _error = "Couldn't open Google Maps. Try again.";
    } finally {
      if (!_disposed) {
        _opening = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
