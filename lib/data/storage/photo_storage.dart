import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

class PhotoUploadException implements Exception {
  const PhotoUploadException(this.message);

  final String message;

  @override
  String toString() => 'PhotoUploadException: $message';
}

abstract interface class PhotoStorage {
  bool get enabled;

  Future<Uint8List?> pick(PhotoSource source);

  Future<String> uploadGroupCover(int groupId, Uint8List bytes);
}

class DisabledPhotoStorage implements PhotoStorage {
  const DisabledPhotoStorage();

  @override
  bool get enabled => false;

  @override
  Future<Uint8List?> pick(PhotoSource source) async => null;

  @override
  Future<String> uploadGroupCover(int groupId, Uint8List bytes) =>
      Future.error(
        const PhotoUploadException('Photo uploads need Firebase.'),
      );
}

class FirebasePhotoStorage implements PhotoStorage {
  FirebasePhotoStorage({FirebaseStorage? storage, ImagePicker? picker})
    : _storage = storage ?? FirebaseStorage.instance,
      _picker = picker ?? ImagePicker();

  final FirebaseStorage _storage;
  final ImagePicker _picker;

  static const _maxSide = 1600.0;
  static const _maxBytes = 5 * 1024 * 1024;

  @override
  bool get enabled => true;

  @override
  Future<Uint8List?> pick(PhotoSource source) async {
    final file = await _picker.pickImage(
      source: source == PhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: _maxSide,
      maxHeight: _maxSide,
      imageQuality: 80,
    );
    return file?.readAsBytes();
  }

  @override
  Future<String> uploadGroupCover(int groupId, Uint8List bytes) async {
    if (bytes.length > _maxBytes) {
      throw const PhotoUploadException('That photo is too large (max 5 MB).');
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('groups/$groupId/cover_$stamp.jpg');
    try {
      final snapshot = await ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      throw PhotoUploadException(switch (e.code) {
        'unauthorized' || 'unauthenticated' =>
          'Storage refused the upload. Check the Firebase Storage rules.',
        'retry-limit-exceeded' || 'canceled' =>
          'The upload did not finish. Check your connection.',
        _ => 'Upload failed (${e.code}).',
      });
    }
  }
}
