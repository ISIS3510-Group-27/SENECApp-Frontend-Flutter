import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:senecapp/app_services.dart';
import 'package:senecapp/core/theme/app_colors.dart';
import 'package:senecapp/core/widgets/primary_button.dart';
import 'package:senecapp/data/local/event_draft_store.dart';
import 'package:senecapp/data/models/event_draft.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';
import 'package:senecapp/features/create_event/create_event_screen.dart';
import 'package:senecapp/features/create_event/event_draft_view_model.dart';
import 'package:senecapp/state/connection_status.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

const owner = 's.arango@uniandes.edu.co';
const group = Rso(
  id: 1,
  name: 'Tennis Uniandes',
  category: RsoCategory.sports,
  members: 3,
  description: '',
  tags: [],
  color: AppColors.primary,
  verified: true,
  myRole: 'admin',
);

EventDraft draft() {
  final day = DateTime.now().add(const Duration(days: 2));
  return EventDraft(
    title: 'Offline practice',
    date: DateTime(day.year, day.month, day.day),
    startMinute: 600,
    durationMinutes: 60,
    buildingId: 1,
    room: 'Main entrance',
    capacity: '12',
    description: 'Bring a racket.',
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    sqfliteFfiInit();
  });

  test('partial draft and delivery state round-trip without losing input', () {
    const partial = EventDraft(title: 'A', capacity: '0', startMinute: 90);
    final restored = EventDraft.fromJson(
      jsonDecode(jsonEncode(partial.toJson())),
    );
    expect(restored.sameFields(partial), isTrue);
    expect(restored.canPublish(DateTime.now()), isFalse);
    final pending = draft().withDelivery(DraftDelivery.needsReview);
    expect(EventDraft.fromJson(pending.toJson()).delivery, pending.delivery);
  });

  test('old dates and invalid capacities cannot be published', () {
    expect(draft().canPublish(DateTime.now()), isTrue);
    expect(
      draft().canPublish(DateTime.now().add(const Duration(days: 3))),
      isFalse,
    );
    expect(
      const EventDraft(title: 'Partial').canPublish(DateTime.now()),
      isFalse,
    );
    expect(
      EventDraft.fromJson({
        ...draft().toJson(),
        'capacity': '0',
      }).canPublish(DateTime.now()),
      isFalse,
    );
    expect(
      () => EventDraft.fromJson({...draft().toJson(), 'start_minute': 1440}),
      throwsFormatException,
    );
  });

  test(
    'SQLite restores drafts after close and isolates accounts and groups',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'senecapp-drafts-',
      );
      final location = '${directory.path}/drafts.db';
      var store = SqliteEventDraftStore(
        factory: databaseFactoryFfi,
        databasePath: location,
      );
      try {
        await store.write(owner, 1, draft());
        await store.write(owner, 2, const EventDraft(title: 'Other group'));
        await store.write(
          'other@uniandes.edu.co',
          1,
          const EventDraft(title: 'Other account'),
        );
        await store.close();
        store = SqliteEventDraftStore(
          factory: databaseFactoryFfi,
          databasePath: location,
        );
        expect(
          (await store.read(
            ' S.ARANGO@uniandes.edu.co ',
            1,
          ))!.sameFields(draft()),
          isTrue,
        );
        expect((await store.read(owner, 2))!.title, 'Other group');
        expect(
          (await store.read('other@uniandes.edu.co', 1))!.title,
          'Other account',
        );
        await store.remove(owner, 1);
        expect(await store.read(owner, 1), isNull);
        expect(await store.read(owner, 2), isNotNull);
        expect(await store.read('other@uniandes.edu.co', 1), isNotNull);
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('browser fallback persists partial drafts per account', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = PrefsEventDraftStore(preferences);
    await store.write(owner, 1, const EventDraft(title: 'Incomplete'));
    expect(
      (await PrefsEventDraftStore(preferences).read(owner, 1))!.title,
      'Incomplete',
    );
    expect(await store.read('other@uniandes.edu.co', 1), isNull);
    await store.remove(owner, 1);
    expect(await store.read(owner, 1), isNull);
  });

  late FakeBackend backend;
  late FakeAuthService auth;
  late EventDraftStore store;
  late bool online;
  late bool sessionActive;

  setUp(() {
    backend = FakeBackend(adminOf: {1});
    auth = signedInAuth();
    store = MemoryEventDraftStore();
    online = true;
    sessionActive = true;
  });

  EventDraftViewModel viewModel({http.Client? client}) => EventDraftViewModel(
    groupId: 1,
    auth: auth,
    store: store,
    events: testServices(auth: auth, backend: client ?? backend.client).events,
    isOnline: () => online,
    sessionActive: () => sessionActive,
  );

  test('offline save and reopen make no publication request', () async {
    online = false;
    final first = viewModel();
    await first.load();
    expect(await first.save(draft()), isTrue);
    first.dispose();
    final restored = viewModel();
    await restored.load();
    expect(restored.saved!.sameFields(draft()), isTrue);
    expect(restored.hasChanges(draft()), isFalse);
    expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    restored.dispose();
  });

  test(
    'reconnection does not publish; explicit publish sends once and clears draft',
    () async {
      online = false;
      final vm = viewModel();
      await vm.load();
      await vm.save(draft());
      online = true;
      expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
      final published = await vm.publish(draft());
      expect(published, isNotNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
      expect(await store.read(owner, 1), isNull);
      expect(await vm.publish(draft()), isNull);
      vm.dispose();
    },
  );

  test('offline publish fallback saves locally and never sends', () async {
    online = false;
    final vm = viewModel();
    await vm.load();
    expect(await vm.publish(draft()), isNull);
    expect(vm.saved!.delivery, DraftDelivery.editing);
    expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    vm.dispose();
  });

  for (final status in [403, 422]) {
    test(
      'HTTP $status retains an editable draft with the server reason',
      () async {
        final vm = viewModel(
          client: MockClient(
            (_) async => jsonResponse({'detail': 'Refused'}, status),
          ),
        );
        await vm.load();
        expect(await vm.publish(draft()), isNull);
        expect(vm.error, 'Refused');
        expect(vm.needsReview, isFalse);
        expect((await store.read(owner, 1))!.delivery, DraftDelivery.editing);
        vm.dispose();
      },
    );
  }

  test(
    'lost response persists review state across restart and blocks resending',
    () async {
      final client = MockClient((request) async {
        await backend.client.post(
          request.url,
          headers: request.headers,
          body: request.body,
        );
        throw http.ClientException('Response lost');
      });
      final first = viewModel(client: client);
      await first.load();
      await first.publish(draft());
      expect(first.needsReview, isTrue);
      first.dispose();
      final restored = viewModel();
      await restored.load();
      expect(restored.needsReview, isTrue);
      expect(await restored.publish(draft()), isNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
      await restored.save(const EventDraft(title: 'Edited'));
      expect(restored.needsReview, isTrue);
      restored.dispose();
    },
  );

  test('503 is ambiguous and requires explicit organizer review', () async {
    final vm = viewModel(
      client: MockClient(
        (_) async => jsonResponse({'detail': 'Unavailable'}, 503),
      ),
    );
    await vm.load();
    await vm.publish(draft());
    expect(vm.needsReview, isTrue);
    expect(await vm.allowRetry(), isTrue);
    expect(vm.needsReview, isFalse);
    vm.dispose();
  });

  test('a failed local write prevents POST and never claims a save', () async {
    store = _FailingStore()..failWrites = true;
    final vm = viewModel();
    await vm.load();
    expect(await vm.save(draft()), isFalse);
    expect(await vm.publish(draft()), isNull);
    expect(vm.saved, isNull);
    expect(vm.error, isNotNull);
    expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    vm.dispose();
  });

  test(
    'cleanup failure after successful POST cannot enable duplicate publication',
    () async {
      store = _FailingStore()..failRemove = true;
      final vm = viewModel();
      await vm.load();
      expect(await vm.publish(draft()), isNotNull);
      vm.dispose();
      final restored = viewModel();
      await restored.load();
      expect(restored.alreadyPublished, isTrue);
      expect(await restored.publish(draft()), isNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
      restored.dispose();
    },
  );

  test('account switch never sends another account draft', () async {
    final vm = viewModel();
    await vm.load();
    await vm.save(draft());
    await auth.signIn(email: 'other@uniandes.edu.co', password: '');
    expect(await vm.publish(draft()), isNull);
    expect(await store.read('other@uniandes.edu.co', 1), isNull);
    expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    vm.dispose();
  });

  test('a session change while saving prevents the later POST', () async {
    final delayed = _DelayedStore();
    store = delayed;
    final vm = viewModel();
    await vm.load();
    final publication = vm.publish(draft());
    await delayed.started.future;
    sessionActive = false;
    delayed.release.complete();
    expect(await publication, isNull);
    expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    vm.dispose();
  });

  test(
    'failed success-marker write leaves the pre-POST review marker',
    () async {
      store = _FailingStore()..failOnWriteNumber = 3;
      final first = viewModel();
      await first.load();
      expect(await first.publish(draft()), isNotNull);
      first.dispose();
      final restored = viewModel();
      await restored.load();
      expect(restored.needsReview, isTrue);
      expect(await restored.publish(draft()), isNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
      restored.dispose();
    },
  );

  test('disposal during local persistence prevents a later POST', () async {
    final delayed = _DelayedStore();
    store = delayed;
    final vm = viewModel();
    await vm.load();
    final publication = vm.publish(draft());
    await delayed.started.future;
    vm.dispose();
    delayed.release.complete();
    expect(await publication, isNull);
    expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
  });

  test('concurrent taps produce at most one POST', () async {
    final vm = viewModel();
    await vm.load();
    await Future.wait([vm.publish(draft()), vm.publish(draft())]);
    expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
    vm.dispose();
  });

  Future<FakeConnectivity> openForm(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final network = FakeConnectivity()..connected = online;
    final connection = ConnectionStatus(network)..start();
    addTearDown(connection.dispose);
    final services = testServices(
      auth: auth,
      backend: backend.client,
      eventDrafts: store,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<AppServices>.value(value: services),
          ChangeNotifierProvider<ConnectionStatus>.value(value: connection),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    Navigator.of(context).push(CreateEventScreen.route(group)),
                child: const Text('Open form'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    return network;
  }

  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    double delta = 250,
  }) async {
    final scrollable = find
        .descendant(
          of: find.byType(CreateEventScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(finder, delta, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'offline form restores, saves edits, and reopens without publishing',
    (tester) async {
      online = false;
      await store.write(owner, 1, draft());
      await openForm(tester);
      expect(find.text('Offline practice'), findsOneWidget);
      final title = find.byType(TextField).first;
      await reveal(tester, title);
      await tester.enterText(title, 'Saved while offline');
      await reveal(tester, find.text('Save draft'));
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(
        find.text('Draft saved on this device. Not published.'),
        findsOneWidget,
      );
      expect((await store.read(owner, 1))!.title, 'Saved while offline');
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Publish event'),
            )
            .onPressed,
        isNull,
      );
      await reveal(tester, find.byTooltip('Back'), delta: -250);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open form'));
      await tester.pumpAndSettle();
      expect(find.text('Saved while offline'), findsOneWidget);
      expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    },
  );

  testWidgets(
    'reconnect enables explicit publishing without sending by itself',
    (tester) async {
      online = false;
      await store.write(owner, 1, draft());
      final network = await openForm(tester);
      await reveal(tester, find.text('Publish event'));
      network.set(connected: true);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Publish event'));
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Publish event'),
            )
            .onPressed,
        isNotNull,
      );
      expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
      await tester.tap(find.text('Publish event'));
      await tester.pumpAndSettle();
      expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
      expect(find.text('Open form'), findsOneWidget);
    },
  );

  testWidgets(
    'back navigation offers saving instead of silently losing edits',
    (tester) async {
      await openForm(tester);
      final title = find.byType(TextField).first;
      await reveal(tester, title);
      await tester.enterText(title, 'Incomplete offline draft');
      await reveal(tester, find.byTooltip('Back'), delta: -250);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Save your draft?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Save draft'));
      await tester.pumpAndSettle();
      expect((await store.read(owner, 1))!.title, 'Incomplete offline draft');
      expect(find.text('Open form'), findsOneWidget);
    },
  );

  for (final size in [const Size(375, 667), const Size(844, 390)]) {
    testWidgets('offline draft form fits $size with large text', (
      tester,
    ) async {
      online = false;
      await store.write(
        owner,
        1,
        draft().withDelivery(DraftDelivery.needsReview),
      );
      await openForm(tester, size: size, textScale: 2);
      await reveal(tester, find.text('Save draft'));
      expect(tester.takeException(), isNull);
    });
  }
}

class _FailingStore extends MemoryEventDraftStore {
  bool failWrites = false;
  bool failRemove = false;
  int? failOnWriteNumber;
  int writes = 0;
  @override
  Future<void> write(String account, int groupId, EventDraft draft) async {
    writes++;
    if (failWrites || writes == failOnWriteNumber) {
      throw StateError('Disk full');
    }
    await super.write(account, groupId, draft);
  }

  @override
  Future<void> remove(String account, int groupId) async {
    if (failRemove) throw StateError('Disk full');
    await super.remove(account, groupId);
  }
}

class _DelayedStore extends MemoryEventDraftStore {
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(String account, int groupId, EventDraft draft) async {
    if (!started.isCompleted) {
      started.complete();
      await release.future;
    }
    await super.write(account, groupId, draft);
  }
}
