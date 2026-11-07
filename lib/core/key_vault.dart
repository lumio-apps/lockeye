import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../services/vault_crypto.dart';

/// The two vault keys, opened by a PIN.
class VaultKeys {
  const VaultKeys({required this.mine, required this.family});

  final Uint8List mine;
  final Uint8List family;
}

/// Where the vault keys are kept: `keys.json` in the app's private folder.
///
/// There are two random 256-bit keys, one per space. They are never stored as
/// they are, only wrapped:
///
/// - the owner's key is wrapped with a key made from the owner's PIN
///   (PBKDF2, 150 000 rounds) and then again with a key from the Android
///   Keystore, which never leaves the phone;
/// - the family key is wrapped the same way with the family PIN, and also with
///   the owner's key, so the owner can open the Family space without the
///   family PIN.
///
/// Changing a PIN only re-wraps a key. The files are not touched.
class KeyVault {
  KeyVault._(this._data);

  static const int iterations = 150000;
  static final Random _random = Random.secure();

  Map<String, dynamic>? _data;

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/keys.json');
  }

  static Future<KeyVault> load() async {
    try {
      final file = await _file();
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map<String, dynamic>) return KeyVault._(json);
      }
    } catch (_) {}
    return KeyVault._(null);
  }

  bool get exists => _data != null;

  /// False while old, unencrypted vault files may still be waiting to be encrypted.
  bool get migrated => _data?['mig'] == true;

  Map<String, dynamic>? get _fam => _data?['fam'] as Map<String, dynamic>?;

  /// A family PIN exists (or waits for its first use after an update).
  bool get hasFamilyPin => _fam != null && (_fam!['wrap'] != null || _fam!['tmp'] != null);

  /// After an update from an older version the family key is held by the phone
  /// alone until the family PIN is typed once.
  bool get familyPending => _fam != null && _fam!['wrap'] == null && _fam!['tmp'] != null;

  static Uint8List _bytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => _random.nextInt(256)));
  static String _b64(Uint8List b) => base64Encode(b);
  static Uint8List _unb64(Object? s) => Uint8List.fromList(base64Decode(s as String));

  Future<void> _save() async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_data), flush: true);
    await tmp.rename(file.path);
  }

  /// PIN → wrapped key.
  Future<Map<String, String>> _wrap(String pin, Uint8List key) async {
    final salt = _bytes(16);
    final kek = await VaultCrypto.kek(pin, salt, iterations);
    final inner = await VaultCrypto.seal(kek, key);
    final outer = await VaultCrypto.pepperSeal(inner);
    return {'salt': _b64(salt), 'wrap': _b64(outer)};
  }

  Future<Uint8List?> _unwrap(String pin, Map<String, dynamic> entry) async {
    try {
      final kek = await VaultCrypto.kek(pin, _unb64(entry['salt']), iterations);
      final inner = await VaultCrypto.pepperOpen(_unb64(entry['wrap']));
      if (inner == null) return null;
      return await VaultCrypto.open(kek, inner);
    } catch (_) {
      return null;
    }
  }

  /// Makes brand new keys. With [familyPending] the family PIN is not known yet
  /// (an update from an old version, where only a hash of it was stored).
  Future<VaultKeys> create(
    String minePin, {
    String? familyPin,
    bool familyPending = false,
    bool migrated = true,
  }) async {
    final mine = _bytes(32);
    final family = _bytes(32);
    final fam = <String, dynamic>{'viaMine': _b64(await VaultCrypto.seal(mine, family))};
    if (familyPin != null) {
      fam.addAll(await _wrap(familyPin, family));
    } else if (familyPending) {
      fam['tmp'] = _b64(await VaultCrypto.pepperSeal(family));
    }
    _data = {
      'v': 2,
      'iters': iterations,
      'mig': migrated,
      'mine': await _wrap(minePin, mine),
      'fam': fam,
    };
    await _save();
    return VaultKeys(mine: mine, family: family);
  }

  /// Both keys if [pin] is the owner's PIN, else null.
  Future<VaultKeys?> openMine(String pin) async {
    final data = _data;
    if (data == null) return null;
    final mine = await _unwrap(pin, data['mine'] as Map<String, dynamic>);
    if (mine == null) return null;
    final via = _fam?['viaMine'];
    if (via == null) return null;
    final family = await VaultCrypto.open(mine, _unb64(via));
    if (family == null) return null;
    return VaultKeys(mine: mine, family: family);
  }

  /// The family key if [pin] is the family PIN, else null.
  Future<Uint8List?> openFamily(String pin) async {
    final fam = _fam;
    if (fam == null || fam['wrap'] == null) return null;
    return _unwrap(pin, fam);
  }

  /// The family key of an updated install that still waits for the family PIN.
  /// The caller must already have checked the PIN against the old hash.
  Future<Uint8List?> openPendingFamily() async {
    final tmp = _fam?['tmp'];
    if (tmp == null) return null;
    return VaultCrypto.pepperOpen(_unb64(tmp));
  }

  /// Sets or changes the family PIN.
  Future<void> setFamilyPin(String pin, Uint8List familyKey) async {
    final fam = _fam;
    if (fam == null) return;
    fam.addAll(await _wrap(pin, familyKey));
    fam.remove('tmp');
    await _save();
  }

  Future<void> setMinePin(String pin, Uint8List mineKey) async {
    final data = _data;
    if (data == null) return;
    data['mine'] = await _wrap(pin, mineKey);
    await _save();
  }

  Future<void> markMigrated() async {
    final data = _data;
    if (data == null) return;
    data['mig'] = true;
    await _save();
  }
}
