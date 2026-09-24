import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera permission state as the UI needs it.
enum CameraAccess { granted, denied, permanentlyDenied }

/// Thin wrapper over the permission plugin so that screens can be tested.
abstract interface class PermissionGateway {
  Future<CameraAccess> cameraStatus();

  /// Asks the user (at the point of use).
  Future<CameraAccess> requestCamera();

  Future<void> openSettings();
}

class SystemPermissionGateway implements PermissionGateway {
  const SystemPermissionGateway();

  @override
  Future<CameraAccess> cameraStatus() async =>
      _map(await Permission.camera.status);

  @override
  Future<CameraAccess> requestCamera() async =>
      _map(await Permission.camera.request());

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }

  static CameraAccess _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return CameraAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraAccess.permanentlyDenied;
    }
    return CameraAccess.denied;
  }
}

/// Picks a photo from the gallery; returns its path or null when cancelled.
abstract interface class GalleryPicker {
  Future<String?> pick();
}

class SystemGalleryPicker implements GalleryPicker {
  const SystemGalleryPicker();

  @override
  Future<String?> pick() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    return file?.path;
  }
}

final permissionGatewayProvider = Provider<PermissionGateway>(
  (ref) => const SystemPermissionGateway(),
);

final galleryPickerProvider = Provider<GalleryPicker>(
  (ref) => const SystemGalleryPicker(),
);
