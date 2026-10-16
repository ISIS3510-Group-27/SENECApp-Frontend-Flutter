import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

enum PhotoSource { camera, gallery }

/// Picks a photo from the camera or the gallery. The upload itself goes to the
/// SENECApp backend (`GroupsRepository.uploadCover`). Part of `AppServices`, so
/// tests can swap in a fake.
abstract interface class PhotoPicker {
  bool get enabled;

  /// The photo's bytes, or null if the student cancelled.
  Future<Uint8List?> pick(PhotoSource source);
}

/// No camera or gallery available (tests).
class DisabledPhotoPicker implements PhotoPicker {
  const DisabledPhotoPicker();

  @override
  bool get enabled => false;

  @override
  Future<Uint8List?> pick(PhotoSource source) async => null;
}

/// [PhotoPicker] on top of the `image_picker` plugin.
class DevicePhotoPicker implements PhotoPicker {
  DevicePhotoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// The backend resizes to this anyway; picking it smaller saves upload time.
  static const _maxSide = 1600.0;

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
      imageQuality: 85,
    );
    return file?.readAsBytes();
  }
}
