import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/concurrency/cover_compressor.dart';
import '../data/api/api_client.dart';
import '../data/local/cover_outbox_store.dart';

typedef CoverUpload = Future<void> Function(int groupId, Uint8List bytes);
typedef CoverCompress = Future<Uint8List> Function(Uint8List bytes);

class CoverResult {
  const CoverResult({
    required this.groupId,
    required this.uploaded,
    this.message,
  });

  final int groupId;
  final bool uploaded;
  final String? message;
}

class CoverOutbox extends ChangeNotifier {
  CoverOutbox({
    required CoverOutboxStore store,
    required String account,
    required CoverUpload upload,
    required Stream<void> reconnected,
    CoverCompress? compress,
  }) : _store = store,
       _account = account,
       _upload = upload,
       _reconnected = reconnected,
       _compress = compress ?? CoverCompressor.compress;

  final CoverOutboxStore _store;
  final String _account;
  final CoverUpload _upload;
  final Stream<void> _reconnected;
  final CoverCompress _compress;
  final _results = StreamController<CoverResult>.broadcast();
  final _pending = <int>{};
  StreamSubscription<void>? _subscription;
  bool _flushing = false;
  bool _disposed = false;

  Stream<CoverResult> get results => _results.stream;

  bool hasPending(int groupId) => _pending.contains(groupId);

  Future<void> start() async {
    _subscription ??= _reconnected.listen((_) => flush());
    try {
      final saved = await _store.pending(_account);
      _pending.addAll(saved.map((cover) => cover.groupId));
    } on Object {
      return;
    }
    if (_disposed) return;
    notifyListeners();
    if (_pending.isNotEmpty) await flush();
  }

  Future<CoverResult?> submit(int groupId, Uint8List photo) async {
    final small = await _compress(photo);
    await _store.put(_account, groupId, small);
    _pending.add(groupId);
    if (!_disposed) notifyListeners();
    final results = await flush();
    for (final result in results) {
      if (result.groupId == groupId) return result;
    }
    return null;
  }

  Future<List<CoverResult>> flush() async {
    if (_flushing) return const [];
    _flushing = true;
    final done = <CoverResult>[];
    try {
      final covers = await _store.pending(_account);
      for (final cover in covers) {
        final result = await _send(cover);
        if (result == null) break;
        done.add(result);
      }
    } finally {
      _flushing = false;
    }
    for (final result in done) {
      if (!_results.isClosed) _results.add(result);
    }
    if (!_disposed) notifyListeners();
    return done;
  }

  Future<CoverResult?> _send(PendingCover cover) async {
    try {
      await _upload(cover.groupId, cover.bytes);
      await _forget(cover);
      return CoverResult(groupId: cover.groupId, uploaded: true);
    } on ApiException catch (e) {
      if (e.isUnreachable) return null;
      await _forget(cover);
      return CoverResult(
        groupId: cover.groupId,
        uploaded: false,
        message: e.message,
      );
    }
  }

  Future<void> _forget(PendingCover sent) async {
    final current = await _store.read(_account, sent.groupId);
    if (current != null && !listEquals(current.bytes, sent.bytes)) return;
    await _store.remove(_account, sent.groupId);
    _pending.remove(sent.groupId);
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _results.close();
    super.dispose();
  }
}
