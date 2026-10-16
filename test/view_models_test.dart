import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/data/location/location_service.dart';
import 'package:senecapp/data/models/student_profile.dart';
import 'package:senecapp/features/discover/discover_view_model.dart';
import 'package:senecapp/features/events/event_filters.dart';
import 'package:senecapp/features/events/events_view_model.dart';
import 'package:senecapp/features/free_now/free_now_view_model.dart';
import 'package:senecapp/state/app_state.dart';

import 'support/fakes.dart';

/// The screens' ViewModels on their own, without any widget: they only need
/// the repositories (and the shared [AppState]) they are given.
void main() {
  late FakeBackend backend;
  late AppServices services;

  AppState appState({bool locationOptIn = true}) => AppState(
    student: StudentProfile(
      id: 1,
      name: 'Sofía Arango',
      email: 's.arango@uniandes.edu.co',
      interests: const ['AI/ML'],
      locationOptIn: locationOptIn,
    ),
    me: services.me,
    groups: services.groups,
    events: services.events,
    notifications: services.notifications,
  );

  setUp(() {
    backend = FakeBackend();
    services = testServices(auth: signedInAuth(), backend: backend.client);
  });

  /// Lets every pending request answer.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('DiscoverViewModel', () {
    DiscoverViewModel discover() => DiscoverViewModel(
      groups: services.groups,
      recommendations: services.recommendations,
      analytics: services.analytics,
      debounce: const Duration(milliseconds: 10),
    );

    test('start loads the groups and the recommendations', () async {
      final vm = discover()..start();
      expect(vm.loading, isTrue);
      expect(vm.ready, isFalse);

      await settle();

      expect(vm.ready, isTrue);
      expect(vm.loading, isFalse);
      expect(vm.results!.items, isNotEmpty);
      expect(vm.featured, hasLength(3));
      expect(vm.recommendations!.requestId, FakeBackend.recRequestId);
      vm.dispose();
    });

    test('typing is debounced into one search', () async {
      final vm = discover()..start();
      await settle();
      final before = backend.requestsTo('GET', '/groups').length;

      vm
        ..setQuery('t')
        ..setQuery('te')
        ..setQuery('tennis');
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final searches = backend.requestsTo('GET', '/groups');
      expect(searches.length, before + 1);
      expect(searches.last.url.queryParameters['q'], 'tennis');
      vm.dispose();
    });

    test('a failing recommender falls back to popular groups', () async {
      backend.recommenderDown = true;
      final vm = discover()..start();
      await settle();

      expect(vm.recommendationsFailed, isTrue);
      expect(vm.featured, isNotEmpty);
      vm.dispose();
    });
  });

  group('EventsViewModel', () {
    test('each list is fetched once, then kept', () async {
      final vm = EventsViewModel(
        events: services.events,
        appState: appState(),
        analytics: services.analytics,
      )..start();
      await settle();
      expect(vm.events, isNotEmpty);

      vm.select(joinedOnly: true);
      await settle();
      vm.select(joinedOnly: false);
      vm.select(joinedOnly: true);
      await settle();

      expect(backend.requestsTo('GET', '/events'), hasLength(2));
      expect(vm.joinedOnly, isTrue);
      vm.dispose();
    });

    test('filters narrow what is visible and clear together', () async {
      final vm = EventsViewModel(
        events: services.events,
        appState: appState(),
        analytics: services.analytics,
      )..start();
      await settle();
      final all = vm.visibleEvents(DateTime.now())!.length;

      vm.setQuery('no event is called this');
      expect(vm.visibleEvents(DateTime.now()), isEmpty);
      expect(vm.hasFilters, isTrue);

      vm.clearFilters();
      expect(vm.query, isEmpty);
      expect(vm.dateFilter, EventDateFilter.any);
      expect(vm.visibleEvents(DateTime.now()), hasLength(all));
      vm.dispose();
    });

    test('a failed load becomes a message', () async {
      backend.failing.add('/events');
      final vm = EventsViewModel(
        events: services.events,
        appState: appState(),
        analytics: services.analytics,
      )..start();
      await settle();

      expect(vm.ready, isTrue);
      expect(vm.events, isNull);
      expect(vm.error, isNotNull);
      vm.dispose();
    });
  });

  group('FreeNowViewModel', () {
    test('asks for consent first and loads nothing', () async {
      final location = FakeLocationService();
      final vm = FreeNowViewModel(
        recommendations: services.recommendations,
        location: location,
        appState: appState(locationOptIn: false),
        analytics: services.analytics,
      )..start();
      await settle();

      expect(vm.askingConsent, isTrue);
      expect(vm.ready, isTrue);
      expect(location.reads, 0);
      expect(
        backend.requestsTo('GET', '/recommendations/events/free-now'),
        isEmpty,
      );
      vm.dispose();
    });

    test('with consent, sends the GPS fix with the request', () async {
      final location = FakeLocationService();
      final vm = FreeNowViewModel(
        recommendations: services.recommendations,
        location: location,
        appState: appState(),
        analytics: services.analytics,
      )..start();
      await settle();
      await settle();

      expect(location.reads, 1);
      expect(vm.result!.requestId, FakeBackend.freeNowRequestId);
      final request = backend
          .requestsTo('GET', '/recommendations/events/free-now')
          .single;
      expect(request.url.queryParameters['latitude'], '4.6026');
      vm.dispose();
    });

    test('remembers why GPS was not used', () async {
      final vm = FreeNowViewModel(
        recommendations: services.recommendations,
        location: FakeLocationService(
          result: const LocationResult.failed(LocationProblem.serviceOff),
        ),
        appState: appState(),
        analytics: services.analytics,
      )..start();
      await settle();
      await settle();

      expect(vm.result, isNotNull);
      expect(vm.locationProblem, LocationProblem.serviceOff);
      vm.dispose();
    });
  });
}
