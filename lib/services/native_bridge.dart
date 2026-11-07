import 'package:flutter/services.dart';

/// Small things only the Android side can do. Safe to call anywhere: when the
/// Android side is missing (tests) every call just returns null / does nothing.
class NativeBridge {
  static const _channel = MethodChannel('com.lumioapps.lockeye/phonelock');

  /// Milliseconds since the phone started, including sleep. It does not change
  /// when someone changes the date or time of the phone.
  static Future<int?> elapsedRealtime() async {
    try {
      return await _channel.invokeMethod<int>('elapsed');
    } catch (_) {
      return null;
    }
  }

  /// Blocks screenshots, screen recording and the preview in the recent apps list.
  static Future<void> setSecure(bool on) async {
    try {
      await _channel.invokeMethod<void>('setSecure', {'on': on});
    } catch (_) {}
  }
}
