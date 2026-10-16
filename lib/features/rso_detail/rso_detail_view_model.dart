import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../data/analytics/analytics.dart';
import '../../data/api/api_client.dart';
import '../../data/models/entry_point.dart';
import '../../data/models/rso.dart';
import '../../data/repositories/groups_repository.dart';
import '../../data/storage/photo_picker.dart';

/// The state behind [RsoDetailScreen]: the group's full profile and the
/// leader and member actions on it (cover photo, admin requests).
///
/// The profile is fetched once per visit: the backend records each fetch as a
/// view, with [entryPoint] saying how the student got here.
class RsoDetailViewModel extends ChangeNotifier {
  RsoDetailViewModel({
    required this.rsoId,
    required this.entryPoint,
    this.recRequestId,
    required GroupsRepository groups,
    required PhotoPicker photos,
    required Analytics analytics,
  }) : _groups = groups,
       _photos = photos,
       _analytics = analytics;

  final int rsoId;
  final EntryPoint entryPoint;

  /// The recommendation list this group was picked from (BQ2).
  final String? recRequestId;

  final GroupsRepository _groups;
  final PhotoPicker _photos;
  final Analytics _analytics;
  bool _disposed = false;

  Rso? _detail;
  String? _error;
  bool _uploadingCover = false;
  bool _requestingAdmin = false;

  /// The full profile, once loaded.
  Rso? get detail => _detail;
  String? get error => _error;
  bool get ready => _detail != null || _error != null;

  bool get uploadingCover => _uploadingCover;
  bool get requestingAdmin => _requestingAdmin;

  /// Whether this device can take or pick a photo at all.
  bool get canPickPhotos => _photos.enabled;

  Future<void> load() async {
    _error = null;
    notifyListeners();
    try {
      final detail = await _groups.detail(
        rsoId,
        entryPoint: entryPoint,
        recRequestId: recRequestId,
      );
      if (_disposed) return;
      _detail = detail;
    } on ApiException catch (e) {
      if (_disposed) return;
      _analytics.error(e, screen: Screens.groupDetail);
      _error = e.message;
    }
    notifyListeners();
  }

  /// Takes or picks a photo and uploads it as the group's cover (admins only).
  ///
  /// Returns the message to show, or `null` when the student cancelled.
  Future<String?> changeCover(PhotoSource source) async {
    _uploadingCover = true;
    notifyListeners();
    try {
      final bytes = await _photos.pick(source);
      if (bytes == null) return null;
      final updated = await _groups.uploadCover(rsoId, bytes);
      if (!_disposed) _detail = updated;
      return 'Cover photo updated.';
    } on PlatformException {
      // Camera or gallery permission refused, or no camera.
      return "Couldn't open the camera or gallery.";
    } on ApiException catch (e) {
      if (!_disposed) _analytics.error(e, screen: Screens.groupDetail);
      return e.message;
    } finally {
      if (!_disposed) {
        _uploadingCover = false;
        notifyListeners();
      }
    }
  }

  /// Asks the group's admins to make the student one too, then reloads so the
  /// request shows as pending.
  ///
  /// Returns the message to show.
  Future<String> requestAdmin({String? note}) async {
    _requestingAdmin = true;
    notifyListeners();
    try {
      await _groups.requestAdmin(rsoId, note: note);
      if (!_disposed) unawaited(load());
      return "Request sent to the group's admins.";
    } on ApiException catch (e) {
      if (!_disposed) _analytics.error(e, screen: Screens.groupDetail);
      return e.message;
    } finally {
      if (!_disposed) {
        _requestingAdmin = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
