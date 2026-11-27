import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../models/event_draft.dart';
import 'event_draft_store.dart';

/// Durable key/value documents, separate from the relational offline cache.
///
/// One draft per account/group. Legacy SQLite rows are retired only after the
/// Hive write is flushed. A deleted document leaves a small tombstone so failed
/// legacy cleanup can never restore a draft that was deleted or published.
/// Account keys isolate reads logically; this box is not encrypted.
class HiveEventDraftStore implements EventDraftStore {
  HiveEventDraftStore({
    EventDraftStore? legacy,
    Future<Box<dynamic>> Function()? openBox,
  }) : _legacy = legacy,
       _openBox = openBox ?? _openDefaultBox;

  final EventDraftStore? _legacy;
  final Future<Box<dynamic>> Function() _openBox;
  Future<Box<dynamic>>? _opening;
  Future<void> _tail = Future<void>.value();

  static Future<Box<dynamic>> _openDefaultBox() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(path.join(root.path, 'event_drafts'));
    await directory.create(recursive: true);
    return Hive.openBox<dynamic>('event_drafts_v1', path: directory.path);
  }

  static String _key(String account, int groupId) {
    final owner = account.trim().toLowerCase();
    if (owner.isEmpty) throw ArgumentError('An account is required.');
    return '${Uri.encodeComponent(owner)}:$groupId';
  }

  Future<Box<dynamic>> _box() => _opening ??= _open();

  Future<Box<dynamic>> _open() async {
    try {
      return await _openBox();
    } on Object {
      _opening = null;
      rethrow;
    }
  }

  // Migration must not race a newer save/delete in another open form. Errors
  // still reach the caller, without preventing the next queued operation.
  Future<T> _serial<T>(Future<T> Function() action) {
    final operation = _tail.then((_) => action());
    _tail = operation.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return operation;
  }

  static EventDraft? _decode(Object raw) {
    if (raw is! Map || raw['version'] != 1 || !raw.containsKey('draft')) {
      throw const FormatException('Unsupported stored event draft.');
    }
    final draft = raw['draft'];
    if (draft == null) return null;
    if (draft is! Map) throw const FormatException('Invalid event draft.');
    // Fail closed on invalid data: falling back to an older SQLite copy could
    // lose needsReview/published and make an uncertain publication retryable.
    return EventDraft.fromJson(Map<String, dynamic>.from(draft));
  }

  Future<void> _persist(Box<dynamic> box, String key, EventDraft? draft) async {
    await box.put(key, {'version': 1, 'draft': draft?.toJson()});
    await box.flush();
  }

  Future<void> _retireLegacy(String account, int groupId) async {
    try {
      await _legacy?.remove(account, groupId);
    } on Object {
      // The flushed Hive document/tombstone is authoritative. A leftover
      // legacy row must not invalidate a successful save or publication.
    }
  }

  @override
  Future<EventDraft?> read(String account, int groupId) => _serial(() async {
    final key = _key(account, groupId);
    final box = await _box();
    final raw = box.get(key);
    if (raw != null) return _decode(raw);

    final draft = await _legacy?.read(account, groupId);
    if (draft == null) return null;
    await _persist(box, key, draft);
    await _retireLegacy(account, groupId);
    return draft;
  });

  @override
  Future<void> write(String account, int groupId, EventDraft draft) =>
      _serial(() async {
        final key = _key(account, groupId);
        await _persist(await _box(), key, draft);
        await _retireLegacy(account, groupId);
      });

  @override
  Future<void> remove(String account, int groupId) => _serial(() async {
    final key = _key(account, groupId);
    await _persist(await _box(), key, null);
    await _retireLegacy(account, groupId);
  });

  /// Closes this box without deleting drafts (used by persistence tests).
  Future<void> close() => _serial(() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  });
}
