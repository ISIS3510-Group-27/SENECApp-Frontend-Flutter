import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/cache/lru_cache.dart';
import '../api/api_client.dart';
import '../local/join_history_store.dart';
import '../models/join_sources.dart';

/// What "Where your members come from" shows at one moment.
@immutable
class JoinSourcesView {
  const JoinSourcesView({
    required this.current,
    this.savedAt,
    this.previous,
    this.refreshing = false,
  });

  final JoinSources current;

  /// When [current] was saved on the phone; `null` when it just came from the
  /// backend.
  final DateTime? savedAt;

  /// The answer from the leader's previous visit, to say what changed.
  final JoinSnapshot? previous;

  /// A newer answer is on its way ([current] is the saved copy meanwhile).
  final bool refreshing;

  bool get fromPhone => savedAt != null;

  /// Joins from [entryPoint] since [previous], or `null` with nothing to
  /// compare against. Only meaningful when both answers cover the same days.
  int? newJoins(String entryPoint) {
    final before = previous?.sources;
    if (before == null || before.days != current.days) return null;
    final now = current.source(entryPoint)?.joins ?? 0;
    final then = before.source(entryPoint)?.joins ?? 0;
    return now - then;
  }
}

/// BQ6 for a group's leaders, **stale-while-revalidate**:
///
/// 1. **Memory** ([LruCache], 8 groups, 2 minutes): reopening the screen right
///    away shows the answer with no request at all.
/// 2. **Phone** ([JoinHistoryStore], SQLite): otherwise the last saved answer
///    is shown at once, *while* the request is already running; reading the
///    database and waiting for the backend happen at the same time.
/// 3. **Backend**: the fresh answer replaces it on screen and is saved as a
///    new snapshot (or replaces one from the last 6 hours).
///
/// [watch] is a [Stream] because the screen gets up to two answers for one
/// request: first the saved one, then the fresh one.
class JoinSourcesRepository {
  JoinSourcesRepository({
    required ApiClient api,
    required JoinHistoryStore store,
    DateTime Function()? clock,
  }) : _api = api,
       _store = store,
       _clock = clock ?? DateTime.now,
       _memory = LruCache(
         capacity: memoryCapacity,
         maxAge: memoryMaxAge,
         clock: clock,
       );

  static const memoryCapacity = 8;
  static const memoryMaxAge = Duration(minutes: 2);
  static const days = 90;

  final ApiClient _api;
  final JoinHistoryStore _store;
  final DateTime Function() _clock;
  final LruCache<int, JoinSourcesView> _memory;
  String? _account;

  /// Answers belong to the signed-in leader: switching accounts forgets the
  /// ones in memory. The phone's copy is kept per account, like the other leader
  /// insights, so one leader never sees another's.
  void useAccount(String? account) {
    final next = account?.trim().toLowerCase();
    if (next == _account) return;
    _account = next;
    _memory.clear();
  }

  Stream<JoinSourcesView> watch(int groupId, {bool force = false}) async* {
    final owner = _account;
    if (!force) {
      final kept = _memory[groupId];
      if (kept != null) {
        yield kept;
        return;
      }
    }

    // Start the request before touching the database, so both wait together.
    final fetching = _api.get(
      '/groups/$groupId/insights/join-sources',
      query: {'days': days},
    );
    // Mark a failure as handled until it's awaited below; the error itself
    // still reaches the `await`.
    unawaited(fetching.then((_) {}, onError: (Object _) {}));

    final history = owner == null
        ? const <JoinSnapshot>[]
        : await _recent(owner, groupId);
    final saved = history.isEmpty ? null : history.first;
    final previous = _previousVisit(history);
    if (saved != null) {
      yield JoinSourcesView(
        current: saved.sources,
        savedAt: saved.takenAt,
        previous: previous,
        refreshing: true,
      );
    }

    final JoinSources fresh;
    try {
      fresh = JoinSources.fromJson((await fetching)! as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (!e.isUnreachable || saved == null) rethrow;
      yield JoinSourcesView(
        current: saved.sources,
        savedAt: saved.takenAt,
        previous: previous,
      );
      return;
    }
    if (owner != _account) return;

    final view = JoinSourcesView(current: fresh, previous: previous);
    _memory[groupId] = view;
    yield view;
    if (owner != null) {
      try {
        await _store.add(
          owner,
          groupId,
          JoinSnapshot(takenAt: _clock(), sources: fresh),
        );
      } on Object catch (e) {
        debugPrint('Join history: $e');
      }
    }
  }

  /// The newest snapshot from an earlier visit: one older than the window in
  /// which refreshes overwrite each other.
  JoinSnapshot? _previousVisit(List<JoinSnapshot> history) {
    final now = _clock();
    for (final snapshot in history) {
      if (now.difference(snapshot.takenAt) >= JoinHistoryStore.mergeWithin) {
        return snapshot;
      }
    }
    return null;
  }

  Future<List<JoinSnapshot>> _recent(String owner, int groupId) async {
    try {
      return await _store.recent(owner, groupId);
    } on Object catch (e) {
      debugPrint('Join history: $e');
      return const [];
    }
  }
}
