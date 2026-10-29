import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Stores PINs as `salt$hash`. The PIN itself is never saved.
class PinHasher {
  static const int _rounds = 5000;

  static String create(String pin) {
    final random = Random.secure();
    final salt = base64Url.encode(List<int>.generate(16, (_) => random.nextInt(256)));
    return '$salt\$${_hash(pin, salt)}';
  }

  static bool verify(String pin, String stored) {
    final i = stored.indexOf('\$');
    if (i <= 0) return false;
    final salt = stored.substring(0, i);
    final expected = stored.substring(i + 1);
    return _sameText(_hash(pin, salt), expected);
  }

  static String _hash(String pin, String salt) {
    final hmac = Hmac(sha256, utf8.encode(salt));
    var digest = hmac.convert(utf8.encode(pin));
    for (var i = 0; i < _rounds; i++) {
      digest = hmac.convert(digest.bytes);
    }
    return base64Url.encode(digest.bytes);
  }

  static bool _sameText(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
