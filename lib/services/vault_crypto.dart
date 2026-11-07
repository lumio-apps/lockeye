// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:flutter/services.dart';

/// What the picker brought into the vault.
class ImportResult {
  const ImportResult({required this.added, required this.deletable});

  static const none = ImportResult(added: 0, deletable: 0);

  /// How many items were encrypted into the vault.
  final int added;

  /// How many of them are gallery photos that can be deleted from the gallery.
  final int deletable;
}

/// The encryption itself runs in Kotlin (AES-256-GCM, PBKDF2, Android Keystore).
/// This is only the doorway to it.
class VaultCrypto {
  static const _channel = MethodChannel('com.lumioapps.lockeye/vault');

  static Future<Uint8List> kek(String pin, Uint8List salt, int iterations) async {
    final out = await _channel.invokeMethod<Uint8List>('kek', {
      'pin': pin,
      'salt': salt,
      'iters': iterations,
    });
    return out!;
  }

  static Future<Uint8List> seal(Uint8List key, Uint8List data) async {
    final out = await _channel.invokeMethod<Uint8List>('seal', {'key': key, 'data': data});
    return out!;
  }

  /// Null when the key is wrong.
  static Future<Uint8List?> open(Uint8List key, Uint8List data) =>
      _channel.invokeMethod<Uint8List>('open', {'key': key, 'data': data});

  static Future<Uint8List> pepperSeal(Uint8List data) async {
    final out = await _channel.invokeMethod<Uint8List>('pepperSeal', {'data': data});
    return out!;
  }

  static Future<Uint8List?> pepperOpen(Uint8List data) =>
      _channel.invokeMethod<Uint8List>('pepperOpen', {'data': data});

  static Future<void> encryptBytes(Uint8List key, Uint8List data, String path, [String meta = '{}']) =>
      _channel.invokeMethod<void>('encryptBytes', {
        'key': key,
        'data': data,
        'path': path,
        'meta': meta,
      });

  static Future<void> encryptFile(Uint8List key, String src, String path, String meta) =>
      _channel.invokeMethod<void>('encryptFile', {
        'key': key,
        'src': src,
        'path': path,
        'meta': meta,
      });

  /// The decrypted content, or null if the file cannot be read with this key.
  static Future<Uint8List?> readBytes(Uint8List key, String path) async {
    try {
      return await _channel.invokeMethod<Uint8List>('readBytes', {'key': key, 'path': path});
    } catch (_) {
      return null;
    }
  }

  static Future<String?> readMeta(Uint8List key, String path) async {
    try {
      return await _channel.invokeMethod<String>('readMeta', {'key': key, 'path': path});
    } catch (_) {
      return null;
    }
  }

  static Future<bool> decryptToFile(Uint8List key, String path, String out) async {
    try {
      return await _channel.invokeMethod<bool>('decryptToFile', {
            'key': key,
            'path': path,
            'out': out,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system picker and encrypts what is picked straight into [dir].
  static Future<ImportResult> importPick(Uint8List key, String dir, {required bool photos}) async {
    try {
      final map = await _channel.invokeMapMethod<String, dynamic>('importPick', {
        'key': key,
        'dir': dir,
        'photos': photos,
      });
      if (map == null) return ImportResult.none;
      return ImportResult(
        added: (map['added'] as num?)?.toInt() ?? 0,
        deletable: (map['deletable'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return ImportResult.none;
    }
  }

  /// Asks Android to delete the gallery originals of the last photo import.
  /// Android shows its own confirmation. True when they were deleted.
  static Future<bool> deleteOriginals() async {
    try {
      return await _channel.invokeMethod<bool>('deleteOriginals') ?? false;
    } catch (_) {
      return false;
    }
  }
}
