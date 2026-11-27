import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/local/local_store.dart';
import 'package:senecapp/data/local/recommendation_snapshot_store.dart';
import 'package:senecapp/data/local/sqlite_local_store.dart';
import 'package:senecapp/data/models/recommendation.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';
import 'package:senecapp/data/repositories/recommendations_repository.dart';
import 'package:senecapp/features/compare_groups/compare_groups_view_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late DateTime now;
  late _Documents documents;
  late RecommendationSnapshotStore snapshots;
  late _Recommendations repository;
  late int session;
  late bool online;
  late CompareGroupsViewModel vm;

  setUp(() {
    now = DateTime.utc(2026, 11, 27, 10);
    documents = _Documents(() => now);
    snapshots = RecommendationSnapshotStore(store: documents, clock: () => now);
    repository = _Recommendations();
    session = 0;
    online = true;
    vm = CompareGroupsViewModel(
      recommendations: repository,
      sessionVersion: () => session,
      snapshots: snapshots,
      isOnline: () => online,
    );
  });

  tearDown(() => vm.dispose());

  group('Snapshot format and expiry', () {
    test(
      'stores comparison fields without attribution or private profile data',
      () async {
        await snapshots.write(_response(image: '/media/cover.jpg'));
        final saved = await snapshots.read();
        expect(saved!.value.requestId, isEmpty);
        expect(saved.savedAt, now);
        expect(saved.value.items.first.group.name, 'Group 1');
        expect(saved.value.items.first.group.members, 12);
        expect(
          saved.value.items.first.group.color.toARGB32(),
          Colors.blue.toARGB32(),
        );
        expect(saved.value.items.first.group.imageUrl, '/media/cover.jpg');
        expect(saved.value.items.first.reasons, ['Matches your interests']);
        final json = jsonEncode(
          documents.values.map((key, value) => MapEntry(key, value.value)),
        );
        expect(json, isNot(contains('request_id')));
        expect(json, isNot(contains('request-live')));
        expect(json, isNot(contains('contact_email')));
      },
    );

    test('24-hour age is exclusive and reads never renew it', () async {
      await snapshots.write(_response());
      final original = now;
      now = now.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      expect((await snapshots.read())!.savedAt, original);
      now = now.add(const Duration(seconds: 1));
      expect(await snapshots.read(), isNull);
      now = original.subtract(const Duration(seconds: 1));
      expect(await snapshots.read(), isNull);
    });

    test('ignores incompatible or malformed snapshots', () async {
      for (final payload in [
        null,
        {'version': 2},
        {'version': 1, 'items': 'bad'},
        {
          'version': 1,
          'items': [false],
          'model_version': 'v1',
        },
      ]) {
        await documents.saveDocument(RecommendationSnapshotStore.key, payload);
        expect(await snapshots.read(), isNull);
      }
    });

    test('limits disk payload to ten groups and 128 KiB', () async {
      await snapshots.write(_response(count: 20));
      expect((await snapshots.read())!.value.items, hasLength(10));
      final writes = documents.writes;
      await snapshots.write(_response(description: 'x' * (128 * 1024)));
      expect(documents.writes, writes);
      expect((await snapshots.read())!.value.items, hasLength(10));
    });

    test('does not persist signed image URLs or URL credentials', () async {
      for (final image in [
        'https://example.com/cover?token=secret',
        'https://user:secret@example.com/cover',
        'https://example.com/cover#secret',
        'file:///private/cover.jpg',
      ]) {
        await snapshots.write(_response(image: image));
        expect(
          (await snapshots.read())!.value.items.first.group.imageUrl,
          isNull,
        );
        expect(
          jsonEncode(
            documents.values.map((key, value) => MapEntry(key, value.value)),
          ),
          isNot(contains('secret')),
        );
      }
    });
  });

  group('Comparison loading', () {
    test(
      'offline comparison reads disk without making an HTTP request',
      () async {
        await snapshots.write(_response());
        online = false;
        await vm.load();
        expect(repository.calls, 0);
        expect(vm.fromCache, isTrue);
        expect(vm.result!.requestId, isEmpty);
        expect(vm.savedAt, now);
        vm.selectFirst(1);
        vm.selectSecond(2);
        expect(vm.canCompare, isTrue);
        expect(vm.canOpenGroup, isFalse);
        expect(vm.error, isNull);
      },
    );

    test(
      'unreachable backend uses cache without rewriting its timestamp',
      () async {
        await snapshots.write(_response());
        final writes = documents.writes;
        repository.fetch = () async =>
            throw const ApiException(503, 'Unavailable');
        now = now.add(const Duration(hours: 2));
        await vm.load();
        expect(vm.fromCache, isTrue);
        expect(vm.failure, isNull);
        expect(vm.savedAt, now.subtract(const Duration(hours: 2)));
        expect(documents.writes, writes);
        expect(vm.canOpenGroup, isFalse);
      },
    );

    test('missing and expired copies cannot be shown offline', () async {
      online = false;
      await vm.load();
      expect(vm.error, isNotNull);
      await snapshots.write(_response());
      now = now.add(const Duration(hours: 24));
      await vm.load();
      expect(vm.result, isNull);
      expect(vm.fromCache, isFalse);
      expect(vm.canOpenGroup, isFalse);
    });

    for (final status in [401, 403, 404, 422]) {
      test('HTTP $status is not hidden with saved recommendations', () async {
        await snapshots.write(_response());
        repository.fetch = () async => throw ApiException(status, 'Rejected');
        await vm.load();
        expect(vm.result, isNull);
        expect(vm.fromCache, isFalse);
        expect(vm.error, 'Rejected');
      });
    }

    test('storage failures never hide live recommendations', () async {
      documents.failRead = true;
      documents.failWrite = true;
      await vm.load();
      expect(vm.result!.requestId, 'request-live');
      expect(vm.error, isNull);
      expect(vm.fromCache, isFalse);
      expect(vm.canOpenGroup, isTrue);
    });

    test('live response does not wait for a slow disk read', () async {
      final gate = Completer<void>();
      documents.readGate = gate.future;
      await vm.load();
      expect(vm.result!.requestId, 'request-live');
      expect(gate.isCompleted, isFalse);
      gate.complete();
    });

    test(
      'session change prevents a late response from being saved or shown',
      () async {
        final pending = Completer<GroupRecommendations>();
        repository.fetch = () => pending.future;
        final loading = vm.load();
        session++;
        pending.complete(_response());
        await loading;
        expect(vm.result, isNull);
        expect(documents.writes, 0);
        session++;
        await vm.load();
        expect(repository.calls, 1);
      },
    );

    test(
      'session change during local restore does not publish the old copy',
      () async {
        await snapshots.write(_response());
        final gate = Completer<void>();
        documents.readGate = gate.future;
        online = false;
        final loading = vm.load();
        session++;
        gate.complete();
        await loading;
        expect(vm.result, isNull);
        expect(vm.error, isNull);
      },
    );

    test(
      'reconnecting during disk restore still fetches a fresh result',
      () async {
        await snapshots.write(_response());
        online = false;
        final gate = Completer<void>();
        documents.readGate = gate.future;
        final loading = vm.load();
        online = true;
        final reconnecting = vm.refreshAfterReconnect();
        gate.complete();
        await Future.wait([loading, reconnecting]);
        expect(repository.calls, 1);
        expect(vm.fromCache, isFalse);
        expect(vm.result!.requestId, 'request-live');
        expect(vm.canOpenGroup, isTrue);
      },
    );

    test(
      'reconnecting reuses a successful network request already in progress',
      () async {
        final pending = Completer<GroupRecommendations>();
        repository.fetch = () => pending.future;
        final loading = vm.load();
        final reconnecting = vm.refreshAfterReconnect();
        pending.complete(_response());
        await Future.wait([loading, reconnecting]);
        expect(repository.calls, 1);
      },
    );

    test('refresh replaces saved attribution with a fresh response and keeps choices', () async {
      await snapshots.write(_response());
      online = false;
      await vm.load();
      vm.selectFirst(1);
      vm.selectSecond(2);
      online = true;
      await vm.refreshAfterReconnect();
      expect(vm.fromCache, isFalse);
      expect(vm.first!.group.id, 1);
      expect(vm.second!.group.id, 2);
      expect(vm.result!.requestId, 'request-live');
      expect(vm.canOpenGroup, isTrue);
    });

    test('an expired visible copy cannot be selected or opened', () async {
      await snapshots.write(_response());
      online = false;
      await vm.load();
      now = now.add(const Duration(hours: 24));
      expect(vm.items, isEmpty);
      expect(vm.error, contains('expired'));
      expect(vm.canCompare, isFalse);
      expect(vm.canOpenGroup, isFalse);
    });
  });

  group('SQLite persistence', () {
    sqfliteFfiInit();
    late Directory directory;
    late SqliteLocalStore database;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('senecapp_comparison_');
      database = SqliteLocalStore(
        factory: databaseFactoryFfi,
        directory: directory.path,
        clock: () => now,
      );
      await database.open('first@uniandes.edu.co');
    });
    tearDown(() async {
      await database.wipe();
      await directory.delete(recursive: true);
    });

    test('restores after closing and reopening the account database', () async {
      await RecommendationSnapshotStore(
        store: database,
        clock: () => now,
      ).write(_response());
      await database.open('other@uniandes.edu.co');
      await database.open('first@uniandes.edu.co');
      final reopened = RecommendationSnapshotStore(
        store: database,
        clock: () => now,
      );
      expect((await reopened.read())!.value.items, hasLength(2));
      expect((await reopened.read())!.value.requestId, isEmpty);
    });

    test('another account cannot read the snapshot', () async {
      final cache = RecommendationSnapshotStore(
        store: database,
        clock: () => now,
      );
      await cache.write(_response());
      await database.open('second@uniandes.edu.co');
      expect(await cache.read(), isNull);
    });

    test('sign-out wipe removes the account snapshot', () async {
      final cache = RecommendationSnapshotStore(
        store: database,
        clock: () => now,
      );
      await cache.write(_response());
      await database.wipe();
      await database.open('first@uniandes.edu.co');
      expect(await cache.read(), isNull);
    });
  });
}

GroupRecommendations _response({
  int count = 2,
  String? image,
  String description = 'Student community',
}) => GroupRecommendations(
  requestId: 'request-live',
  modelVersion: 'model-1',
  items: [
    for (var id = 1; id <= count; id++)
      GroupRecommendation(
        group: Rso(
          id: id,
          name: 'Group $id',
          category: RsoCategory.technology,
          members: 12,
          description: description,
          tags: const [],
          color: Colors.blue,
          verified: true,
          imageUrl: image,
          contactEmail: 'private@example.com',
        ),
        reasons: const ['Matches your interests'],
      ),
  ],
);

class _Documents extends NoLocalStore {
  _Documents(this.clock);
  final DateTime Function() clock;
  final values = <String, Cached<Object?>>{};
  int writes = 0;
  bool failRead = false;
  bool failWrite = false;
  Future<void>? readGate;

  @override
  Future<Cached<Object?>?> document(String key) async {
    final value = values[key];
    await readGate;
    if (failRead) throw StateError('Unreadable storage');
    return value;
  }

  @override
  Future<void> saveDocument(String key, Object? json) async {
    if (failWrite) throw StateError('Disk full');
    values[key] = Cached(json, clock());
    writes++;
  }
}

class _Recommendations extends RecommendationsRepository {
  _Recommendations() : super(_UnusedApi());
  int calls = 0;
  Future<GroupRecommendations> Function() fetch = () async => _response();
  @override
  Future<GroupRecommendations> groups({int limit = 10}) {
    calls++;
    return fetch();
  }
}

class _UnusedApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected HTTP request');
}
