import 'dart:typed_data';

import 'models.dart';

/// The vault keys while the app is unlocked. They live only in memory and are
/// wiped the moment the app locks.
class Keyring {
  static Uint8List? mine;
  static Uint8List? family;

  /// Decrypted photos kept for a moment so the grid does not decrypt them again
  /// on every scroll. Wiped together with the keys.
  static final Map<String, Uint8List> photoCache = <String, Uint8List>{};
  static const int _photoCacheMax = 24;

  static Uint8List? of(VaultSpace space) => space == VaultSpace.mine ? mine : family;

  static void set({Uint8List? mine, Uint8List? family}) {
    Keyring.mine = mine;
    Keyring.family = family;
  }

  static void remember(String path, Uint8List bytes) {
    photoCache.remove(path);
    photoCache[path] = bytes;
    while (photoCache.length > _photoCacheMax) {
      photoCache.remove(photoCache.keys.first);
    }
  }

  static void clear() {
    final m = mine;
    final f = family;
    if (m != null) m.fillRange(0, m.length, 0);
    if (f != null) f.fillRange(0, f.length, 0);
    mine = null;
    family = null;
    photoCache.clear();
  }
}
