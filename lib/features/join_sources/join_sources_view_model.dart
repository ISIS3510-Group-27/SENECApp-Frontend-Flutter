import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/repositories/join_sources_repository.dart';

/// The state behind [JoinSourcesScreen].
///
/// Listens to [JoinSourcesRepository.watch], which can answer twice (the
/// phone's copy, then the backend's), and to the reconnection stream: a screen
/// left showing the saved copy offline refreshes by itself when the
/// connection returns.
class JoinSourcesViewModel extends ChangeNotifier {
  JoinSourcesViewModel({
    required this.groupId,
    required JoinSourcesRepository repository,
    required Analytics analytics,
    required Stream<void> reconnected,
  }) : _repository = repository,
       _analytics = analytics {
    _reconnection = reconnected.listen((_) {
      if (_view?.fromPhone ?? _error != null) load(force: true);
    });
  }

  final int groupId;
  final JoinSourcesRepository _repository;
  final Analytics _analytics;
  late final StreamSubscription<void> _reconnection;
  StreamSubscription<JoinSourcesView>? _answers;
  Completer<void>? _pending;

  JoinSourcesView? _view;
  ApiException? _error;
  bool _disposed = false;

  JoinSourcesView? get view => _view;
  ApiException? get error => _error;
  bool get ready => _view != null || _error != null;

  /// A request is running (the saved copy, if any, is on screen meanwhile).
  bool get refreshing => _answers != null;

  /// Starts a new request, dropping any that is still running. Completes
  /// when the last answer has arrived.
  Future<void> load({bool force = false}) {
    final done = Completer<void>();
    // A cancelled request never finishes on its own: let its caller go on.
    _answers?.cancel();
    if (_pending case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    _pending = done;
    _error = null;
    notifyListeners();
    late final StreamSubscription<JoinSourcesView> subscription;
    void finish() {
      // A newer load may have replaced this one already.
      if (_answers == subscription) _answers = null;
      if (!_disposed) notifyListeners();
      if (!done.isCompleted) done.complete();
    }

    _answers = subscription = _repository
        .watch(groupId, force: force)
        .listen(
          (view) {
            _view = view;
            notifyListeners();
          },
          onError: (Object e) {
            if (e is ApiException) {
              _analytics.error(e, screen: Screens.joinSources);
              // An answer on screen stays: the error only matters without one.
              if (e.statusCode == 401 || e.statusCode == 403) _view = null;
              if (_view == null) _error = e;
            } else {
              debugPrint('Join sources: $e');
            }
            // cancelOnError: onDone won't run, so finish here.
            finish();
          },
          onDone: finish,
          cancelOnError: true,
        );
    return done.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _answers?.cancel();
    if (_pending case final pending? when !pending.isCompleted) {
      pending.complete();
    }
    _reconnection.cancel();
    super.dispose();
  }
}
