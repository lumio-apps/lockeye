import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Which of the things the phone lock feature needs are switched on.
class PhoneLockStatus {
  const PhoneLockStatus({
    this.admin = false,
    this.overlay = false,
    this.camera = false,
    this.notifications = false,
  });

  final bool admin;
  final bool overlay;
  final bool camera;
  final bool notifications;

  /// Everything required for the photo to work. Notifications are only needed
  /// so the small "checking" notice is visible; the photo works without it.
  bool get ready => admin && overlay && camera;
}

/// One wrong attempt on the phone's own lock screen, reported by the Android side.
class PendingShot {
  const PendingShot({required this.timeMs, required this.attempt, required this.path});

  final int timeMs;
  final int attempt;
  final String? path;

  /// Reads the lines the Android side wrote. Broken lines are skipped and the
  /// result is oldest first.
  static List<PendingShot> parseLines(String text) {
    final shots = <PendingShot>[];
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final time = json['time'];
        if (time is! num) continue;
        final attempt = json['attempt'];
        final path = json['path'];
        shots.add(
          PendingShot(
            timeMs: time.toInt(),
            attempt: attempt is num ? attempt.toInt() : 1,
            path: path is String ? path : null,
          ),
        );
      } catch (_) {
        continue;
      }
    }
    shots.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return shots;
  }
}

/// Talks to the Android side that watches the phone's own lock screen.
/// Every call is safe to make anywhere: when the Android side is missing
/// (tests, other platforms) it just does nothing.
class PhoneLockService {
  static const _channel = MethodChannel('com.lumioapps.lockeye/phonelock');
  static const _pendingName = 'phone_lock_pending.jsonl';
  static const _importingName = 'phone_lock_importing.jsonl';

  static Future<PhoneLockStatus> status() async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('status');
      if (map == null) return const PhoneLockStatus();
      return PhoneLockStatus(
        admin: map['admin'] == true,
        overlay: map['overlay'] == true,
        camera: map['camera'] == true,
        notifications: map['notifications'] == true,
      );
    } catch (_) {
      return const PhoneLockStatus();
    }
  }

  /// Tells the Android side whether the feature is on and where photos go.
  static Future<void> configure({required bool enabled}) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      await _channel.invokeMethod<void>('configure', {'enabled': enabled, 'dir': dir.path});
    } catch (_) {}
  }

  static Future<void> requestAdmin() => _call('requestAdmin');
  static Future<void> requestOverlay() => _call('requestOverlay');
  static Future<void> requestPermissions() => _call('requestPermissions');
  static Future<void> openBatterySettings() => _call('openBatterySettings');
  static Future<void> removeAdmin() => _call('removeAdmin');

  /// Starts a test photo. Returns false if Android would not start it.
  static Future<bool> testCapture() async {
    try {
      return await _channel.invokeMethod<bool>('testCapture') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {}
  }

  /// Picks up the attempts the Android side recorded while the app was closed.
  /// The file is renamed first, so an attempt that arrives while reading is
  /// kept for next time instead of being lost.
  static Future<List<PendingShot>> takePending() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final pending = File('${base.path}/$_pendingName');
      final importing = File('${base.path}/$_importingName');

      if (await pending.exists()) {
        if (await importing.exists()) {
          // A previous import was cut short: add the new lines to it.
          await importing.writeAsString(await pending.readAsString(), mode: FileMode.append);
          await pending.delete();
        } else {
          await pending.rename(importing.path);
        }
      }
      if (!await importing.exists()) return const [];

      final shots = PendingShot.parseLines(await importing.readAsString());
      await importing.delete();
      return shots;
    } catch (_) {
      return const [];
    }
  }
}
