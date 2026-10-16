import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/data/location/location_service.dart';
import 'package:senecapp/data/models/entry_point.dart';
import 'package:senecapp/data/models/student_profile.dart';
import 'package:senecapp/data/storage/photo_picker.dart';
import 'package:senecapp/features/check_in/check_in_view_model.dart';
import 'package:senecapp/features/discover/discover_view_model.dart';
import 'package:senecapp/features/event_detail/event_detail_view_model.dart';
import 'package:senecapp/features/events/event_filters.dart';
import 'package:senecapp/features/events/events_view_model.dart';
import 'package:senecapp/features/free_now/free_now_view_model.dart';
import 'package:senecapp/features/rso_detail/rso_detail_view_model.dart';
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

  /// Starts over against [fake], e.g. one with a live event or admin rights.
  void use(FakeBackend fake) {
    backend = fake;
    services = testServices(auth: signedInAuth(), backend: backend.client);
  }

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

  group('RsoDetailViewModel', () {
    RsoDetailViewModel detail({
      PhotoPicker photos = const DisabledPhotoPicker(),
    }) => RsoDetailViewModel(
      rsoId: 3,
      entryPoint: EntryPoint.recommendation,
      recRequestId: FakeBackend.recRequestId,
      groups: services.groups,
      photos: photos,
      analytics: services.analytics,
    );

    test('the view is attributed to the recommendation it came from', () async {
      final vm = detail();
      await vm.load();

      expect(vm.ready, isTrue);
      expect(vm.detail!.id, 3);
      final url = backend.requestsTo('GET', '/groups/3').single.url;
      expect(url.queryParameters['entry_point'], 'recommendation');
      expect(url.queryParameters['rec_request_id'], FakeBackend.recRequestId);
      vm.dispose();
    });

    test('a cancelled photo pick uploads nothing', () async {
      final vm = detail(photos: const _FakePhotoPicker(null));
      await vm.load();

      expect(vm.canPickPhotos, isTrue);
      expect(await vm.changeCover(PhotoSource.gallery), isNull);
      expect(vm.uploadingCover, isFalse);
      expect(backend.requestsTo('POST', '/groups/3/cover'), isEmpty);
      vm.dispose();
    });

    test('an admin request is sent once, then refused', () async {
      final vm = detail();
      await vm.load();

      expect(
        await vm.requestAdmin(note: 'I run the socials'),
        "Request sent to the group's admins.",
      );
      expect(vm.requestingAdmin, isFalse);
      expect(await vm.requestAdmin(), 'You already asked');
      vm.dispose();
    });
  });

  group('EventDetailViewModel', () {
    Future<EventDetailViewModel> detail(int eventId) async {
      final state = appState();
      await state.load();
      return EventDetailViewModel(
        eventId: eventId,
        entryPoint: EventEntryPoint.events,
        events: services.events,
        me: services.me,
        appState: state,
        analytics: services.analytics,
      );
    }

    test('an organizer gets the venue QR code', () async {
      use(FakeBackend(adminOf: {5}));
      final vm = await detail(2);
      await vm.load();
      await settle();

      expect(vm.event!.id, 2);
      expect(vm.organizerCode!.code, FakeBackend.checkInCode(2));
      expect(vm.conflicts, isNotNull);
      vm.dispose();
    });

    test("non-members aren't asked for the code", () async {
      final vm = await detail(4);
      await vm.load();
      await settle();

      expect(backend.requestsTo('GET', '/events/4/check-in-code'), isEmpty);
      expect(vm.organizerCode, isNull);
      vm.dispose();
    });

    test('a check-in marks the event', () async {
      final vm = await detail(2);
      await vm.load();
      vm.markCheckedIn();

      expect(vm.event!.checkedIn, isTrue);
      vm.dispose();
    });
  });

  group('CheckInViewModel', () {
    const live = 2;
    final validCode =
        'senecapp://check-in?event_id=$live'
        '&code=${FakeBackend.checkInCode(live)}';
    var checkedIn = 0;

    CheckInViewModel checkIn({bool optedIn = true}) {
      checkedIn = 0;
      use(FakeBackend(liveEventId: live));
      return CheckInViewModel(
        events: services.events,
        location: FakeLocationService(),
        locationOptIn: () => optedIn,
        onCheckedIn: () => checkedIn++,
        analytics: services.analytics,
      );
    }

    test('a foreign QR code is a hint, and scanning carries on', () async {
      final vm = checkIn()..onScanned('https://example.com');
      await settle();

      expect(vm.hint, "That isn't a SENECApp check-in code.");
      expect(vm.scanning, isTrue);
      expect(backend.requestsTo('POST', '/events/$live/check-in'), isEmpty);
      vm.dispose();
    });

    test('a valid code checks in with the GPS position', () async {
      final vm = checkIn()..onScanned(validCode);
      expect(vm.submitting, isTrue);
      await settle();
      await settle();

      expect(vm.result, isNotNull);
      expect(vm.scanning, isFalse);
      expect(checkedIn, 1);
      final sent = backend.requestsTo('POST', '/events/$live/check-in').single;
      expect(sent.body, contains('latitude'));
      vm.dispose();
    });

    test('without consent only the code is sent', () async {
      final vm = checkIn(optedIn: false);
      await vm.submit(live, FakeBackend.checkInCode(live));

      final sent = backend.requestsTo('POST', '/events/$live/check-in').single;
      expect(sent.body, isNot(contains('latitude')));
      vm.dispose();
    });

    test('a refused code stops scanning until "scan again"', () async {
      final vm = checkIn();
      await vm.submit(live, 'WRONG');

      expect(vm.refusal, 'Invalid check-in code');
      expect(vm.scanning, isFalse);
      expect(checkedIn, 0);

      vm.scanAgain();
      expect(vm.refusal, isNull);
      expect(vm.scanning, isTrue);
      vm.dispose();
    });
  });
}

/// A camera or gallery that hands back [bytes] (null: the student cancelled).
class _FakePhotoPicker implements PhotoPicker {
  const _FakePhotoPicker(this.bytes);

  final Uint8List? bytes;

  @override
  bool get enabled => true;

  @override
  Future<Uint8List?> pick(PhotoSource source) async => bytes;
}
