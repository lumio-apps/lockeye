import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

/// Takes a photo with the front camera, without showing any preview.
/// The camera is warmed up while the lock screen is open, so the photo is
/// ready the moment a wrong PIN is typed.
class IntruderService {
  CameraController? _controller;
  Future<bool>? _preparing;
  DateTime? _readyAt;

  /// Opens the front camera. Asks for the camera permission the first time.
  /// Returns false when there is no front camera or the permission is denied.
  Future<bool> prepare() => _preparing ??= _open();

  Future<bool> _open() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.where((c) => c.lensDirection == CameraLensDirection.front);
      if (front.isEmpty) return false;
      final controller = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      _controller = controller;
      await controller.initialize();
      try {
        await controller.setFlashMode(FlashMode.off);
      } catch (_) {}
      _readyAt = DateTime.now();
      return true;
    } catch (_) {
      await release();
      return false;
    }
  }

  /// Returns the saved photo path, or null if no photo could be taken.
  Future<String?> capture(String id) async {
    final ok = await prepare();
    final controller = _controller;
    if (!ok || controller == null || !controller.value.isInitialized) return null;

    // Give auto exposure a moment after the camera opened.
    final readyAt = _readyAt;
    if (readyAt != null) {
      final wait = 500 - DateTime.now().difference(readyAt).inMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    }

    try {
      if (controller.value.isTakingPicture) return null;
      final shot = await controller.takePicture();
      final dir = await photosDir();
      final dest = '${dir.path}/$id.jpg';
      await File(shot.path).copy(dest);
      try {
        await File(shot.path).delete();
      } catch (_) {}
      return dest;
    } catch (_) {
      return null;
    }
  }

  Future<void> release() async {
    final controller = _controller;
    _controller = null;
    _preparing = null;
    _readyAt = null;
    try {
      await controller?.dispose();
    } catch (_) {}
  }

  /// Private app folder: other apps and the gallery cannot see these photos.
  static Future<Directory> photosDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/intruders');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
