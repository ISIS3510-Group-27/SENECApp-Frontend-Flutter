import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/theme/app_theme.dart';
import 'package:senecapp/data/location/location_service.dart';
import 'package:senecapp/data/location/maps_service.dart';
import 'package:senecapp/data/models/campus_event.dart';
import 'package:senecapp/features/event_detail/event_directions_sheet.dart';
import 'package:senecapp/features/event_detail/event_directions_view_model.dart';

import 'support/fakes.dart';

const venue = (latitude: 4.6026, longitude: -74.0649);

CampusEvent event({
  double? latitude = 4.6026,
  double? longitude = -74.0649,
  bool cancelled = false,
}) => CampusEvent(
  id: 2,
  rsoId: 5,
  rsoName: 'AI Club',
  title: 'Campus workshop',
  startsAt: DateTime.utc(2030, 1, 6, 18),
  endsAt: DateTime.utc(2030, 1, 6, 20),
  color: Colors.amber,
  buildingName: 'Edificio Mario Laserna',
  locationDetail: 'Auditorium',
  buildingLatitude: latitude,
  buildingLongitude: longitude,
  isCancelled: cancelled,
);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('walking URL has explicit origin, destination and pedestrian mode', () {
    final url = GoogleMapsService.walkingRouteUrl(
      origin: (latitude: 4.6036, longitude: -74.0649),
      destination: venue,
    );
    expect(url.scheme, 'https');
    expect(url.host, 'www.google.com');
    expect(url.path, '/maps/dir/');
    expect(url.queryParameters, {
      'api': '1',
      'origin': '4.6036,-74.0649',
      'destination': '4.6026,-74.0649',
      'travelmode': 'walking',
    });
    final pin = GoogleMapsService.placeUrl(venue);
    expect(pin.path, '/maps/search/');
    expect(pin.queryParameters, {'api': '1', 'query': '4.6026,-74.0649'});
  });

  test(
    'opening destination never reads or shares the student position',
    () async {
      final location = FakeLocationService();
      final maps = FakeMapsService();
      final vm = EventDirectionsViewModel(
        event: event(),
        location: location,
        maps: maps,
      );
      addTearDown(vm.dispose);
      expect(location.reads, 0);
      await vm.openWalkingRoute();
      expect(maps.routes, isEmpty);
      await vm.openPlace();
      expect(location.reads, 0);
      expect(maps.places, [venue]);
      expect(maps.routes, isEmpty);
    },
  );

  test(
    'GPS gives straight-line distance and route opens only on request',
    () async {
      final location = FakeLocationService(
        result: const LocationResult.found(4.6036, -74.0649),
      );
      final maps = FakeMapsService();
      final vm = EventDirectionsViewModel(
        event: event(),
        location: location,
        maps: maps,
      );
      addTearDown(vm.dispose);
      await vm.locate();
      expect(location.reads, 1);
      expect(vm.distanceMeters, closeTo(111.2, 1));
      expect(maps.routes, isEmpty);
      await vm.openWalkingRoute();
      expect(maps.routes.single.origin, (
        latitude: 4.6036,
        longitude: -74.0649,
      ));
      expect(maps.routes.single.destination, venue);
      await vm.openPlace();
      expect(maps.places, [venue]);
    },
  );

  for (final problem in LocationProblem.values) {
    test('$problem leaves venue-only fallback available', () async {
      final location = FakeLocationService(
        result: LocationResult.failed(problem),
      );
      final maps = FakeMapsService();
      final vm = EventDirectionsViewModel(
        event: event(),
        location: location,
        maps: maps,
      );
      addTearDown(vm.dispose);
      await vm.locate();
      expect(vm.problem, problem);
      expect(vm.distanceMeters, isNull);
      await vm.openWalkingRoute();
      expect(maps.routes, isEmpty);
      await vm.openPlace();
      expect(maps.places, [venue]);
      await vm.openSettings();
      expect(location.settingsOpened, switch (problem) {
        LocationProblem.deniedForever ||
        LocationProblem.serviceOff => [problem],
        _ => isEmpty,
      });
      location.result = const LocationResult.found(4.6026, -74.0649);
      await vm.locate();
      expect(vm.problem, isNull);
      expect(vm.distanceMeters, 0);
    });
  }

  test(
    'invalid destinations and cancelled events never request GPS or maps',
    () async {
      for (final candidate in [
        event(latitude: null),
        event(longitude: null),
        event(latitude: double.nan),
        event(latitude: double.infinity),
        event(latitude: 91),
        event(longitude: -181),
        event(cancelled: true),
      ]) {
        final location = FakeLocationService();
        final maps = FakeMapsService();
        final vm = EventDirectionsViewModel(
          event: candidate,
          location: location,
          maps: maps,
        );
        expect(vm.available, false);
        await vm.locate();
        await vm.openPlace();
        expect(location.reads, 0);
        expect(maps.places, isEmpty);
        vm.dispose();
      }
      expect(
        EventDirectionsViewModel.destinationFor(
          event(latitude: 0, longitude: 0),
        ),
        (latitude: 0.0, longitude: 0.0),
      );
    },
  );

  test('failed map launch is recoverable', () async {
    final maps = FakeMapsService()..succeeds = false;
    final vm = EventDirectionsViewModel(
      event: event(),
      location: FakeLocationService(),
      maps: maps,
    );
    addTearDown(vm.dispose);
    await vm.openPlace();
    expect(vm.error, contains("Couldn't open Google Maps"));
    expect(vm.opening, false);
    maps.succeeds = true;
    await vm.openPlace();
    expect(vm.error, isNull);
  });

  test(
    'duplicate GPS requests and completion after disposal are safe',
    () async {
      final location = _PendingLocation();
      final vm = EventDirectionsViewModel(
        event: event(),
        location: location,
        maps: FakeMapsService(),
      );
      var notifications = 0;
      vm.addListener(() => notifications++);
      final pending = vm.locate();
      await vm.locate();
      expect(location.reads, 1);
      expect(vm.locating, true);
      vm.dispose();
      location.answer.complete(const LocationResult.found(4.6026, -74.0649));
      await pending;
      expect(notifications, 1);
    },
  );

  test(
    'platform exceptions become recoverable location and map failures',
    () async {
      final vm = EventDirectionsViewModel(
        event: event(),
        location: _ThrowingLocation(),
        maps: _ThrowingMaps(),
      );
      addTearDown(vm.dispose);
      await vm.locate();
      expect(vm.problem, LocationProblem.unavailable);
      expect(vm.locating, false);
      await vm.openPlace();
      expect(vm.error, isNotNull);
      expect(vm.opening, false);
    },
  );

  Future<void> openSheet(
    WidgetTester tester, {
    required FakeLocationService location,
    required FakeMapsService maps,
    CampusEvent? candidate,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Provider<AppServices>.value(
        value: testServices(location: location, maps: maps),
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      EventDirectionsSheet.show(context, candidate ?? event()),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('sheet requires explicit GPS and route actions', (tester) async {
    final location = FakeLocationService();
    final maps = FakeMapsService();
    await openSheet(tester, location: location, maps: maps);
    expect(location.reads, 0);
    expect(find.text('Open walking route in Google Maps'), findsNothing);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.text('0 m away'), findsOneWidget);
    expect(maps.routes, isEmpty);
    await tester.ensureVisible(find.text('Open walking route in Google Maps'));
    await tester.tap(find.text('Open walking route in Google Maps'));
    await tester.pumpAndSettle();
    expect(maps.routes, hasLength(1));
  });

  testWidgets('blocked GPS offers settings and destination without GPS', (
    tester,
  ) async {
    final location = FakeLocationService(
      result: const LocationResult.failed(LocationProblem.deniedForever),
    );
    final maps = FakeMapsService();
    await openSheet(tester, location: location, maps: maps);
    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Location is blocked'), findsOneWidget);
    await tester.tap(find.text('Open location settings'));
    await tester.pumpAndSettle();
    expect(location.settingsOpened, [LocationProblem.deniedForever]);
    await tester.ensureVisible(find.text('View venue in Google Maps'));
    await tester.tap(find.text('View venue in Google Maps'));
    await tester.pumpAndSettle();
    expect(maps.places, [venue]);
    expect(maps.routes, isEmpty);
  });

  for (final size in [const Size(375, 667), const Size(844, 390)]) {
    testWidgets('directions fit $size with large text', (tester) async {
      await openSheet(
        tester,
        location: FakeLocationService(),
        maps: FakeMapsService(),
        size: size,
        textScale: 2,
      );
      await tester.ensureVisible(find.text('Use my location'));
      await tester.tap(find.text('Use my location'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View venue in Google Maps'));
      expect(tester.takeException(), isNull);
    });
  }
}

class _PendingLocation implements LocationService {
  final answer = Completer<LocationResult>();
  int reads = 0;

  @override
  Future<LocationResult> current() {
    reads++;
    return answer.future;
  }

  @override
  Future<void> openSettings(LocationProblem problem) async {}
}

class _ThrowingLocation implements LocationService {
  @override
  Future<LocationResult> current() async =>
      throw PlatformException(code: 'unavailable');

  @override
  Future<void> openSettings(LocationProblem problem) async {}
}

class _ThrowingMaps implements MapsService {
  @override
  Future<bool> openPlace(MapCoordinates destination) async =>
      throw PlatformException(code: 'no-handler');

  @override
  Future<bool> openWalkingRoute({
    required MapCoordinates origin,
    required MapCoordinates destination,
  }) async => false;
}
