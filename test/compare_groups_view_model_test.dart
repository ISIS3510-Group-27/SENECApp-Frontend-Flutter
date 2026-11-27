import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:senecapp/data/api/api_client.dart';
import 'package:senecapp/data/models/recommendation.dart';
import 'package:senecapp/data/models/rso.dart';
import 'package:senecapp/data/models/rso_category.dart';
import 'package:senecapp/data/repositories/recommendations_repository.dart';
import 'package:senecapp/features/compare_groups/compare_groups_view_model.dart';

void main() {
  late _Recommendations repository;
  late CompareGroupsViewModel vm;
  late int session;

  setUp(() {
    session = 0;
    repository = _Recommendations();
    vm = CompareGroupsViewModel(
      recommendations: repository,
      sessionVersion: () => session,
    );
  });

  tearDown(() => vm.dispose());

  test(
    'loads one response with its attribution and recommendation reasons',
    () async {
      expect(vm.ready, isFalse);
      final loading = vm.load();
      expect(vm.loading, isTrue);
      expect(vm.canOpenGroup, isFalse);
      await loading;

      expect(repository.calls, 1);
      expect(vm.ready, isTrue);
      expect(vm.loading, isFalse);
      expect(vm.result!.requestId, 'request-1');
      expect(vm.result!.modelVersion, 'model-1');
      expect(vm.items.first.reasons, ['Matches your interests']);
      expect(vm.hasEnoughGroups, isTrue);
      expect(vm.canOpenGroup, isTrue);
    },
  );

  test(
    'reuses an in-flight request, even from a synchronous listener',
    () async {
      final response = Completer<GroupRecommendations>();
      repository.fetch = () => response.future;
      Future<void>? fromListener;
      vm.addListener(() {
        if (vm.loading) fromListener = vm.load();
      });
      final first = vm.load();
      final second = vm.load();
      expect(identical(first, second), isTrue);
      expect(identical(first, fromListener), isTrue);
      expect(repository.calls, 1);

      response.complete(_response());
      await Future.wait([first, second]);
      expect(vm.items, hasLength(2));
    },
  );

  test('selection stays local and rejects duplicate or unknown IDs', () async {
    await vm.load();
    vm.selectFirst(1);
    vm.selectSecond(1);
    vm.selectSecond(99);
    expect(vm.second, isNull);
    vm.selectSecond(2);
    expect(vm.canCompare, isTrue);
    vm.selectFirst(2);
    expect(vm.first!.group.id, 1);
    expect(repository.calls, 1);
    vm.selectFirst(null);
    expect(vm.canCompare, isFalse);
  });

  test(
    'refresh retains existing choices and replaces the request ID',
    () async {
      await vm.load();
      vm.selectFirst(1);
      vm.selectSecond(2);
      repository.fetch = () async =>
          _response(requestId: 'request-2', ids: [2, 1]);
      await vm.load();
      expect(vm.first!.group.id, 1);
      expect(vm.second!.group.id, 2);
      expect(vm.result!.requestId, 'request-2');

      repository.fetch = () async => _response(ids: [2, 3]);
      await vm.load();
      expect(vm.first, isNull);
      expect(vm.second!.group.id, 2);
    },
  );

  test('uses distinct groups and handles zero or one recommendation', () async {
    repository.fetch = () async => _response(ids: [1, 1]);
    await vm.load();
    expect(vm.items, hasLength(1));
    expect(vm.hasEnoughGroups, isFalse);
    expect(() => vm.items.clear(), throwsUnsupportedError);
    repository.fetch = () async => _response(ids: []);
    await vm.load();
    expect(vm.ready, isTrue);
    expect(vm.items, isEmpty);
    expect(vm.hasEnoughGroups, isFalse);
    expect(vm.error, isNull);
  });

  test('failed refresh clears actionable results and allows a retry', () async {
    await vm.load();
    repository.fetch = () async => throw const ApiException(403, 'Not allowed');
    await vm.load();
    expect(vm.error, 'Not allowed');
    expect(vm.result, isNull);
    expect(vm.canOpenGroup, isFalse);
    expect(vm.loading, isFalse);

    repository.fetch = () async => _response(requestId: 'retry');
    await vm.load();
    expect(vm.error, isNull);
    expect(vm.result!.requestId, 'retry');
  });

  test(
    'unexpected exception shows a generic message without leaking details',
    () async {
      repository.fetch = () async =>
          throw const FormatException('private payload');
      await vm.load();
      expect(vm.error, 'Could not load recommendations. Try again.');
      expect(vm.ready, isTrue);
      expect(vm.canOpenGroup, isFalse);
    },
  );

  test('a session change hides old data and ignores pending results', () async {
    await vm.load();
    final response = Completer<GroupRecommendations>();
    repository.fetch = () => response.future;
    var notifications = 0;
    vm.addListener(() => notifications++);
    final loading = vm.load();
    final beforeChange = notifications;
    session++;
    expect(vm.result, isNull);
    response.complete(_response(requestId: 'old-session'));
    await loading;
    await vm.load();
    expect(vm.result, isNull);
    expect(vm.error, isNull);
    expect(vm.canOpenGroup, isFalse);
    expect(notifications, beforeChange);
    expect(repository.calls, 2);
  });

  test('disposed models ignore both pending successes and failures', () async {
    for (final fails in [false, true]) {
      final pending = Completer<GroupRecommendations>();
      repository.fetch = () => pending.future;
      final model = CompareGroupsViewModel(
        recommendations: repository,
        sessionVersion: () => session,
      );
      var notifications = 0;
      model.addListener(() => notifications++);
      final loading = model.load();
      model.dispose();
      if (fails) {
        pending.completeError(const ApiException(null, 'Offline'));
      } else {
        pending.complete(_response());
      }
      await loading;
      expect(notifications, 1);
      expect(model.result, isNull);
      expect(model.error, isNull);
    }
  });
}

GroupRecommendations _response({
  String requestId = 'request-1',
  List<int> ids = const [1, 2],
}) => GroupRecommendations(
  requestId: requestId,
  modelVersion: 'model-1',
  items: [
    for (final id in ids)
      GroupRecommendation(
        group: Rso(
          id: id,
          name: 'Group $id',
          category: RsoCategory.technology,
          members: 12,
          description: 'A student organization',
          tags: const [],
          color: Colors.blue,
          verified: true,
        ),
        reasons: const ['Matches your interests'],
      ),
  ],
);

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

/// The repository override never makes an HTTP request in these unit tests.
class _UnusedApi implements ApiClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected HTTP request: ${invocation.memberName}');
}
