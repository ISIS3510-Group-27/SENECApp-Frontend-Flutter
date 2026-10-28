import 'package:flutter/foundation.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/auth/auth_service.dart';
import '../../data/local/event_draft_store.dart';
import '../../data/models/campus_event.dart';
import '../../data/models/event_draft.dart';
import '../../data/repositories/events_repository.dart';

/// Local-first editing, with an explicit, single publication attempt online.
class EventDraftViewModel extends ChangeNotifier {
  EventDraftViewModel({
    required this.groupId,
    required AuthService auth,
    required EventDraftStore store,
    required EventsRepository events,
    required bool Function() isOnline,
    required bool Function() sessionActive,
    Analytics? analytics,
  }) : _auth = auth,
       _store = store,
       _events = events,
       _isOnline = isOnline,
       _analytics = analytics,
       _sessionActive = sessionActive;

  final int groupId;
  final AuthService _auth;
  final EventDraftStore _store;
  final EventsRepository _events;
  final bool Function() _isOnline;
  final bool Function() _sessionActive;
  final Analytics? _analytics;

  bool _disposed = false;
  bool _loading = true;
  bool _busy = false;
  bool _loaded = false;
  String? _owner;
  EventDraft? _saved;
  String? _error;

  bool get loading => _loading;
  bool get busy => _busy;
  bool get ready => _loaded && _owner != null;
  EventDraft? get saved => _saved;
  String? get error => _error;
  bool get needsReview => _saved?.delivery == DraftDelivery.needsReview;
  bool get alreadyPublished => _saved?.delivery == DraftDelivery.published;
  bool get _active => !_disposed && _sessionActive();

  bool hasChanges(EventDraft form) =>
      _saved == null ? !form.isEmpty : !form.sameFields(_saved!);

  Future<void> load() async {
    if (_busy || !_active) return;
    _busy = true;
    _loading = true;
    _error = null;
    _notify();
    try {
      final account = await _auth.restore();
      if (!_active) return;
      if (account == null || !account.emailVerified) {
        throw StateError('No verified session.');
      }
      final owner = account.email.trim().toLowerCase();
      final draft = await _store.read(owner, groupId);
      if (!_active) return;
      _owner = owner;
      _saved = draft;
      _loaded = true;
    } on Object {
      if (_active) _error = "Couldn't load your draft. Try again.";
    } finally {
      _busy = false;
      _loading = false;
      _notify();
    }
  }

  Future<bool> _sameAccount() async {
    if (!_active) return false;
    final account = await _auth.restore();
    final same =
        _active &&
        account != null &&
        account.emailVerified &&
        account.email.trim().toLowerCase() == _owner;
    if (!same && _active) {
      _error = 'Your session changed. Reopen this form.';
    }
    return same;
  }

  Future<void> _save(EventDraft form) async {
    // Editing content must never silently clear an uncertain publication.
    final value = form.withDelivery(
      _saved?.delivery ?? DraftDelivery.editing,
      eventId: _saved?.publishedEventId,
    );
    await _store.write(_owner!, groupId, value);
    _saved = value;
  }

  Future<bool> save(EventDraft form) async {
    if (!ready || _busy || !_active) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      if (!await _sameAccount()) return false;
      await _save(form);
      return _active;
    } on Object {
      if (_active) _error = "Couldn't save the draft. Your form is still here.";
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<CampusEvent?> publish(EventDraft form) async {
    if (!ready || _busy || !_active || needsReview || alreadyPublished) {
      return null;
    }
    if (!form.canPublish(DateTime.now())) {
      _error = 'Check the title, future start time and capacity.';
      _notify();
      return null;
    }
    _busy = true;
    _error = null;
    _notify();
    try {
      if (!await _sameAccount()) return null;
      await _save(form);
      if (!_active || !await _sameAccount() || !_isOnline()) return null;

      // Persist before POST: a lost response or app restart must not resend it.
      final pending = form.withDelivery(DraftDelivery.needsReview);
      await _store.write(_owner!, groupId, pending);
      _saved = pending;
      if (!_active || !await _sameAccount()) return null;
      final start = form.startsAt!;
      final event = await _events.create(
        groupId,
        title: form.title.trim(),
        startsAt: start,
        endsAt: start.add(Duration(minutes: form.durationMinutes)),
        buildingId: form.buildingId,
        locationDetail: form.room.trim().isEmpty ? null : form.room.trim(),
        description: form.description.trim().isEmpty
            ? null
            : form.description.trim(),
        capacity: form.capacityValue,
      );
      final published = form.withDelivery(
        DraftDelivery.published,
        eventId: event.id,
      );
      _saved = published;
      // Cleanup failing after success must not turn a successful POST into retry.
      try {
        await _store.write(_owner!, groupId, published);
        await _store.remove(_owner!, groupId);
      } on Object {
        // At least the pre-POST review marker remains.
      }
      return _active ? event : null;
    } on ApiException catch (e) {
      if (_active) _analytics?.error(e, screen: Screens.createEvent);
      if (e.statusCode != null &&
          e.statusCode! >= 400 &&
          e.statusCode! < 500 &&
          e.statusCode != 408) {
        final refused = form.withDelivery(DraftDelivery.editing);
        try {
          await _store.write(_owner!, groupId, refused);
          _saved = refused;
        } on Object {
          // Keep the review marker if the refusal cannot be persisted.
        }
      }
      if (_active) _error = e.message;
      return null;
    } on Object {
      if (_active) {
        _error = "Couldn't finish publishing. Your draft stays on this device.";
      }
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Only after the organizer checked the group's events for a lost response.
  Future<bool> allowRetry() => _changeStored(discard: false);
  Future<bool> discard() => _changeStored(discard: true);

  Future<bool> _changeStored({required bool discard}) async {
    if (!ready || _busy || !_active) return false;
    if (!discard && !_isOnline()) return false;
    _busy = true;
    _error = null;
    _notify();
    try {
      if (!await _sameAccount()) return false;
      if (discard) {
        await _store.remove(_owner!, groupId);
        _saved = null;
      } else if (needsReview) {
        final draft = _saved!.withDelivery(DraftDelivery.editing);
        await _store.write(_owner!, groupId, draft);
        _saved = draft;
      }
      return _active;
    } on Object {
      if (_active) _error = "Couldn't update the draft. Try again.";
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
