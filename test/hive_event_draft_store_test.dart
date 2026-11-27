import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:senecapp/data/local/event_draft_store.dart';
import 'package:senecapp/data/local/hive_event_draft_store.dart';
import 'package:senecapp/data/models/event_draft.dart';
import 'package:senecapp/features/create_event/event_draft_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fakes.dart';

const _owner = 's.arango@uniandes.edu.co';
const _draft = EventDraft(
  title: 'Offline practice',
  room: 'ML entrance',
  description: 'Bring a racket.',
  capacity: '12',
  startMinute: 600,
  buildingId: 1,
  durationMinutes: 60,
);

void main() {
  late Directory directory;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('senecapp-hive-drafts-');
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<Box<dynamic>> openBox() =>
      Hive.openBox<dynamic>('drafts', path: directory.path);

  SqliteEventDraftStore sqlite() {
    final store = SqliteEventDraftStore(
      factory: databaseFactoryFfi,
      databasePath: '${directory.path}/legacy.db',
    );
    addTearDown(store.close);
    return store;
  }

  EventDraftViewModel viewModel(
    EventDraftStore store,
    FakeBackend backend, {
    bool online = true,
    http.Client? client,
  }) {
    final auth = signedInAuth();
    final vm = EventDraftViewModel(
      groupId: 1,
      auth: auth,
      store: store,
      events: testServices(
        auth: auth,
        backend: client ?? backend.client,
      ).events,
      isOnline: () => online,
      sessionActive: () => true,
    );
    addTearDown(vm.dispose);
    return vm;
  }

  test(
    'Hive survives close/reopen and isolates normalized accounts and groups',
    () async {
      var store = HiveEventDraftStore(openBox: openBox);
      final draft = EventDraft.fromJson({
        ..._draft.toJson(),
        'date': '2030-01-02T00:00:00.000',
      });
      await store.write(_owner, 1, draft);
      await store.write(_owner, 2, const EventDraft(title: 'Other group'));
      await store.write(
        'other@uniandes.edu.co',
        1,
        const EventDraft(title: 'Other account'),
      );
      await store.close();
      store = HiveEventDraftStore(openBox: openBox);
      expect(
        (await store.read(' S.ARANGO@uniandes.edu.co ', 1))!.toJson(),
        draft.toJson(),
      );
      expect((await store.read(_owner, 2))!.title, 'Other group');
      expect(
        (await store.read('other@uniandes.edu.co', 1))!.title,
        'Other account',
      );
      await store.remove(_owner, 1);
      await store.close();
      store = HiveEventDraftStore(openBox: openBox);
      expect(await store.read(_owner, 1), isNull);
      expect(await store.read(_owner, 2), isNotNull);
      expect(await store.read('other@uniandes.edu.co', 1), isNotNull);
    },
  );

  for (final delivery in DraftDelivery.values) {
    test('migrates SQLite $delivery only after durable Hive storage', () async {
      final legacy = sqlite();
      final draft = _draft.withDelivery(
        delivery,
        eventId: delivery == DraftDelivery.published ? 42 : null,
      );
      await legacy.write(_owner, 1, draft);
      await legacy.write(
        _owner,
        2,
        const EventDraft(title: 'Not migrated yet'),
      );
      var store = HiveEventDraftStore(openBox: openBox, legacy: legacy);
      expect((await store.read(_owner, 1))!.toJson(), draft.toJson());
      expect(await legacy.read(_owner, 1), isNull);
      expect(await legacy.read(_owner, 2), isNotNull);
      await store.close();
      store = HiveEventDraftStore(openBox: openBox, legacy: legacy);
      expect((await store.read(_owner, 1))!.toJson(), draft.toJson());
    });
  }

  for (final failFlush in [false, true]) {
    test(
      'migration retains SQLite when Hive ${failFlush ? 'flush' : 'write'} fails',
      () async {
        final legacy = sqlite();
        await legacy.write(
          _owner,
          1,
          _draft.withDelivery(DraftDelivery.needsReview),
        );
        final box = _FaultyBox(await openBox())
          ..failWrites = !failFlush
          ..failFlush = failFlush;
        final store = HiveEventDraftStore(
          openBox: () async => box,
          legacy: legacy,
        );
        await expectLater(store.read(_owner, 1), throwsStateError);
        expect(
          (await legacy.read(_owner, 1))!.delivery,
          DraftDelivery.needsReview,
        );
      },
    );
  }

  test('box opening can be retried without losing legacy data', () async {
    final legacy = sqlite();
    await legacy.write(_owner, 1, _draft);
    var attempts = 0;
    final store = HiveEventDraftStore(
      legacy: legacy,
      openBox: () async {
        if (attempts++ == 0) throw StateError('Disk unavailable');
        return openBox();
      },
    );
    await expectLater(store.read(_owner, 1), throwsStateError);
    expect((await legacy.read(_owner, 1))!.title, _draft.title);
    expect((await store.read(_owner, 1))!.title, _draft.title);
    expect(await legacy.read(_owner, 1), isNull);
  });

  test(
    'failed legacy cleanup never resurrects a deleted draft after restart',
    () async {
      final legacy = _LegacyStore()..failRemove = true;
      await legacy.write(_owner, 1, _draft);
      var store = HiveEventDraftStore(openBox: openBox, legacy: legacy);
      await store.read(_owner, 1);
      await store.write(_owner, 1, const EventDraft(title: 'New copy'));
      expect((await store.read(_owner, 1))!.title, 'New copy');
      await store.remove(_owner, 1);
      expect(await legacy.read(_owner, 1), isNotNull);
      await store.close();
      store = HiveEventDraftStore(openBox: openBox, legacy: legacy);
      expect(await store.read(_owner, 1), isNull);
    },
  );

  test(
    'a legacy read failure is not treated as an empty editable draft',
    () async {
      final store = HiveEventDraftStore(
        openBox: openBox,
        legacy: _LegacyStore()..failRead = true,
      );
      final backend = FakeBackend(adminOf: {1});
      final vm = viewModel(store, backend);
      await vm.load();
      expect(vm.ready, isFalse);
      expect(vm.error, isNotNull);
      expect(await vm.publish(_draft), isNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    },
  );

  test(
    'unsupported Hive data blocks editing instead of restoring stale SQLite',
    () async {
      final legacy = sqlite();
      final store = HiveEventDraftStore(openBox: openBox, legacy: legacy);
      await store.write(
        _owner,
        1,
        _draft.withDelivery(DraftDelivery.needsReview),
      );
      final box = await openBox();
      await box.put(box.keys.single, {'version': 99, 'draft': _draft.toJson()});
      await legacy.write(_owner, 1, _draft);
      await expectLater(store.read(_owner, 1), throwsFormatException);
      final vm = viewModel(store, FakeBackend(adminOf: {1}));
      await vm.load();
      expect(vm.ready, isFalse);
      expect(vm.error, isNotNull);
      expect((await legacy.read(_owner, 1))!.delivery, DraftDelivery.editing);
    },
  );

  test('migration is serialized with a newer save and delete', () async {
    final legacy = _LegacyStore()..gate = Completer<void>();
    await legacy.write(_owner, 1, _draft);
    final store = HiveEventDraftStore(openBox: openBox, legacy: legacy);
    final reading = store.read(_owner, 1);
    await legacy.started.future;
    final saving = store.write(_owner, 1, const EventDraft(title: 'Newer'));
    final deleting = store.remove(_owner, 1);
    legacy.gate!.complete();
    expect((await reading)!.title, _draft.title);
    await saving;
    await deleting;
    expect(await store.read(_owner, 1), isNull);
  });

  test(
    'offline ViewModel restores from reopened Hive without making a POST',
    () async {
      final backend = FakeBackend(adminOf: {1});
      var store = HiveEventDraftStore(openBox: openBox);
      final first = viewModel(store, backend, online: false);
      await first.load();
      expect(await first.save(_draft), isTrue);
      await store.close();
      store = HiveEventDraftStore(openBox: openBox);
      final restored = viewModel(store, backend, online: false);
      await restored.load();
      expect(restored.saved!.toJson(), _draft.toJson());
      expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    },
  );

  test(
    'a failed Hive flush never confirms a save or allows publication',
    () async {
      final box = _FaultyBox(await openBox())..failFlush = true;
      final store = HiveEventDraftStore(openBox: () async => box);
      final backend = FakeBackend(adminOf: {1});
      final vm = viewModel(store, backend);
      await vm.load();
      final draft = EventDraft.fromJson({
        ..._draft.toJson(),
        'date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      });
      expect(await vm.save(draft), isFalse);
      expect(await vm.publish(draft), isNull);
      expect(vm.error, isNotNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
    },
  );

  test(
    'explicit successful publication removes the Hive draft across reopen',
    () async {
      final backend = FakeBackend(adminOf: {1});
      var store = HiveEventDraftStore(openBox: openBox);
      final vm = viewModel(store, backend);
      await vm.load();
      final draft = EventDraft.fromJson({
        ..._draft.toJson(),
        'date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      });
      expect(await vm.save(draft), isTrue);
      expect(backend.requestsTo('POST', '/groups/1/events'), isEmpty);
      expect(await vm.publish(draft), isNotNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
      await store.close();
      store = HiveEventDraftStore(openBox: openBox);
      expect(await store.read(_owner, 1), isNull);
    },
  );

  test(
    'lost POST response keeps needsReview after Hive closes and reopens',
    () async {
      final backend = FakeBackend(adminOf: {1});
      final client = MockClient((request) async {
        await backend.client.post(
          request.url,
          headers: request.headers,
          body: request.body,
        );
        throw http.ClientException('Response lost');
      });
      var store = HiveEventDraftStore(openBox: openBox);
      final first = viewModel(store, backend, client: client);
      await first.load();
      final draft = EventDraft.fromJson({
        ..._draft.toJson(),
        'date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
      });
      expect(await first.publish(draft), isNull);
      expect(first.needsReview, isTrue);
      await store.close();
      store = HiveEventDraftStore(openBox: openBox);
      final restored = viewModel(store, backend);
      await restored.load();
      expect(restored.needsReview, isTrue);
      expect(await restored.publish(draft), isNull);
      expect(backend.requestsTo('POST', '/groups/1/events'), hasLength(1));
    },
  );
}

class _FaultyBox extends Fake implements Box<dynamic> {
  _FaultyBox(this.box);
  final Box<dynamic> box;
  bool failWrites = false;
  bool failFlush = false;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      box.get(key, defaultValue: defaultValue);

  @override
  Future<void> put(dynamic key, dynamic value) async {
    if (failWrites) throw StateError('Write failed');
    await box.put(key, value);
  }

  @override
  Future<void> flush() async {
    if (failFlush) throw StateError('Flush failed');
    await box.flush();
  }
}

class _LegacyStore extends MemoryEventDraftStore {
  bool failRemove = false;
  bool failRead = false;
  Completer<void>? gate;
  final started = Completer<void>();

  @override
  Future<EventDraft?> read(String account, int groupId) async {
    if (failRead) throw StateError('Legacy storage failed');
    if (!started.isCompleted) started.complete();
    await gate?.future;
    return super.read(account, groupId);
  }

  @override
  Future<void> remove(String account, int groupId) async {
    if (failRemove) throw StateError('Cleanup failed');
    await super.remove(account, groupId);
  }
}
