import 'dart:convert';
import 'dart:io';
import 'dart:math';
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/native_bridge.dart';
import '../services/phone_lock_service.dart';
import '../services/vault_service.dart';
import 'key_vault.dart';
import 'keyring.dart';
import 'models.dart';
import 'pin_hasher.dart';

/// A new PIN must have at least this many digits. PINs made by older versions
/// (4 digits) still work until they are changed.
const int kMinNewPin = 6;
const int kMinAnyPin = 4;
const int kMaxPin = 12;

/// True for PINs that are too easy to guess, such as 000000 or 123456.
bool isWeakPin(String pin) {
  if (pin.isEmpty) return true;
  if (pin.split('').every((c) => c == pin[0])) return true;
  const runs = '01234567890123456789';
  const back = '98765432109876543210';
  return runs.contains(pin) || back.contains(pin);
}

/// How many milliseconds of a lockout are left. [setAt] and [now] come from
/// the phone's uptime clock, so changing the date or time does not help. After
/// a restart the uptime clock starts over; then the whole lockout begins again.
int remainingLockMs({required int durationMs, required int setAt, required int now}) {
  if (durationMs <= 0) return 0;
  if (now < setAt) return durationMs;
  final left = durationMs - (now - setAt);
  return left > 0 ? left : 0;
}

/// After this many wrong PINs in a row the keypad is locked for a while.
const int kFreeTries = 5;

/// Everything the app remembers: PINs (hashed), settings, the intruder log
/// and which space is currently unlocked (null = locked).
class AppState extends ChangeNotifier {
  AppState._(this._prefs, this._keys) {
    _intruders = _readLog();
  }

  static Future<AppState> load() async {
    final prefs = await SharedPreferences.getInstance();
    final state = AppState._(prefs, await KeyVault.load());
    await state.syncClock();
    await NativeBridge.setSecure(state.blockScreenshots);
    await VaultService.clearTemp();
    return state;
  }

  static const _kMine = 'pin_mine';
  static const _kFamily = 'pin_family';
  static const _kFamilyOn = 'family_on';
  static const _kPhoto = 'photo_on_wrong';
  static const _kPhoneLock = 'phone_lock_on';
  static const _kCameraAsked = 'camera_asked';
  static const _kTheme = 'theme_mode';
  static const _kFails = 'fail_count';
  static const _kLockDur = 'lock_dur_ms';
  static const _kLockSet = 'lock_set_elapsed';
  static const _kSecure = 'block_screens';
  static const _kHint = 'show_lock_hint';
  static const _kShortPin = 'pin_is_short';
  static const _kLog = 'intruder_log';
  static const _kSeen = 'intruders_seen';

  final SharedPreferences _prefs;
  final KeyVault _keys;
  late List<IntruderEntry> _intruders;
  int _suspendCount = 0;

  /// The unlocked space, or null while the app is locked.
  VaultSpace? space;

  // ---- setup & PINs -------------------------------------------------------

  /// True while old vault files are being encrypted after an update.
  bool migrating = false;

  bool get isSetUp => _keys.exists || _prefs.getString(_kMine) != null;

  bool get hasFamilyPin =>
      _keys.exists ? _keys.hasFamilyPin : _prefs.getString(_kFamily) != null;

  bool get familyEnabled => hasFamilyPin && (_prefs.getBool(_kFamilyOn) ?? true);

  /// The owner's PIN is shorter than [kMinNewPin] digits (an older PIN).
  bool get pinIsShort => _prefs.getBool(_kShortPin) ?? false;

  Future<void> completeSetup(String minePin, {String? familyPin}) async {
    final keys = await _keys.create(minePin, familyPin: familyPin);
    if (familyPin != null) await _prefs.setBool(_kFamilyOn, true);
    await _prefs.setBool(_kShortPin, minePin.length < kMinNewPin);
    Keyring.set(mine: keys.mine, family: keys.family);
    space = VaultSpace.mine;
    notifyListeners();
  }

  /// Checks a PIN without unlocking anything or counting a failure.
  Future<bool> verifyMine(String pin) async => (await _keys.openMine(pin)) != null;

  Future<bool> verifyFamily(String pin) async {
    if (!hasFamilyPin) return false;
    if (await _keys.openFamily(pin) != null) return true;
    final legacy = _prefs.getString(_kFamily);
    return legacy != null && _keys.familyPending && PinHasher.verify(pin, legacy);
  }

  Future<void> setMinePin(String pin) async {
    final key = Keyring.mine;
    if (key == null) return;
    await _keys.setMinePin(pin, key);
    await _prefs.setBool(_kShortPin, pin.length < kMinNewPin);
    notifyListeners();
  }

  Future<void> setFamilyPin(String pin) async {
    final key = Keyring.family;
    if (key == null) return;
    await _keys.setFamilyPin(pin, key);
    await _prefs.remove(_kFamily);
    await _prefs.setBool(_kFamilyOn, true);
    notifyListeners();
  }

  Future<void> setFamilyEnabled(bool value) async {
    await _prefs.setBool(_kFamilyOn, value);
    notifyListeners();
  }

  // ---- unlocking ----------------------------------------------------------

  int get failCount => _prefs.getInt(_kFails) ?? 0;

  // The lockout is timed with the phone's uptime clock, not its date and time.
  int _baseElapsed = 0;
  final Stopwatch _watch = Stopwatch()..start();
  bool _clockKnown = false;

  /// Reads the uptime clock from Android. Called at start, on resume and
  /// before every PIN check.
  Future<void> syncClock() async {
    final elapsed = await NativeBridge.elapsedRealtime();
    if (elapsed == null) return;
    _baseElapsed = elapsed;
    _watch
      ..reset()
      ..start();
    _clockKnown = true;
  }

  int get _nowElapsed => _clockKnown
      ? _baseElapsed + _watch.elapsedMilliseconds
      : DateTime.now().millisecondsSinceEpoch;

  Duration get lockRemaining => Duration(
        milliseconds: remainingLockMs(
          durationMs: _prefs.getInt(_kLockDur) ?? 0,
          setAt: _prefs.getInt(_kLockSet) ?? 0,
          now: _nowElapsed,
        ),
      );

  Future<UnlockResult> unlock(String pin) async {
    await syncClock();
    if (lockRemaining > Duration.zero) return UnlockResult.lockedOut;

    if (!_keys.exists) return _unlockLegacy(pin);

    final owner = await _keys.openMine(pin);
    if (owner != null) {
      if (!_keys.migrated) {
        migrating = true;
        notifyListeners();
        try {
          await VaultService.migrateLegacy(VaultSpace.mine, owner.mine);
          await VaultService.migrateLegacy(VaultSpace.family, owner.family);
          await _keys.markMigrated();
        } finally {
          migrating = false;
        }
      }
      await _prefs.setBool(_kShortPin, pin.length < kMinNewPin);
      _succeed(VaultSpace.mine, mine: owner.mine, family: owner.family);
      return UnlockResult.mine;
    }

    if (familyEnabled) {
      final family = await _openFamily(pin);
      if (family != null) {
        _succeed(VaultSpace.family, family: family);
        return UnlockResult.family;
      }
    }
    _registerFailure();
    return UnlockResult.wrong;
  }

  /// An install from before 1.2.0: only a hash of the PIN is stored. The first
  /// time the owner's PIN is typed, the vault gets its keys and its files are
  /// encrypted. Until then the Family PIN has nothing to open.
  Future<UnlockResult> _unlockLegacy(String pin) async {
    final stored = _prefs.getString(_kMine);
    if (stored != null && PinHasher.verify(pin, stored)) {
      migrating = true;
      notifyListeners();
      try {
        final hasFamily = _prefs.getString(_kFamily) != null;
        final keys = await _keys.create(pin, familyPending: hasFamily, migrated: false);
        Keyring.set(mine: keys.mine, family: keys.family);
        await VaultService.migrateLegacy(VaultSpace.mine, keys.mine);
        await VaultService.migrateLegacy(VaultSpace.family, keys.family);
        await _keys.markMigrated();
        await _prefs.remove(_kMine);
        await _prefs.setBool(_kShortPin, pin.length < kMinNewPin);
        _succeed(VaultSpace.mine, mine: keys.mine, family: keys.family);
      } finally {
        migrating = false;
      }
      return UnlockResult.mine;
    }
    final legacyFamily = _prefs.getString(_kFamily);
    if (familyEnabled && legacyFamily != null && PinHasher.verify(pin, legacyFamily)) {
      return UnlockResult.needsOwner;
    }
    _registerFailure();
    return UnlockResult.wrong;
  }

  Future<Uint8List?> _openFamily(String pin) async {
    final key = await _keys.openFamily(pin);
    if (key != null) return key;
    final legacy = _prefs.getString(_kFamily);
    if (legacy != null && _keys.familyPending && PinHasher.verify(pin, legacy)) {
      final pending = await _keys.openPendingFamily();
      if (pending != null) {
        await _keys.setFamilyPin(pin, pending);
        await _prefs.remove(_kFamily);
        return pending;
      }
    }
    return null;
  }

  void _succeed(VaultSpace target, {Uint8List? mine, Uint8List? family}) {
    _prefs.setInt(_kFails, 0);
    _prefs.setInt(_kLockDur, 0);
    Keyring.set(mine: mine, family: family);
    space = target;
    VaultService.clearTemp();
    notifyListeners();
  }

  void _registerFailure() {
    final count = failCount + 1;
    _prefs.setInt(_kFails, count);
    if (count % kFreeTries == 0) {
      final level = count ~/ kFreeTries;
      final seconds = min(30 * (1 << min(level - 1, 4)), 300);
      _prefs.setInt(_kLockDur, seconds * 1000);
      _prefs.setInt(_kLockSet, _nowElapsed);
    }
    notifyListeners();
  }

  void lock() {
    if (space == null) return;
    space = null;
    Keyring.clear();
    notifyListeners();
  }

  /// Wrap anything that leaves the app for a moment (file picker) so the vault
  /// does not lock itself while the person is picking.
  Future<T> keepUnlocked<T>(Future<T> Function() action) async {
    _suspendCount++;
    try {
      return await action();
    } finally {
      _suspendCount--;
    }
  }

  DateTime? _holdUntil;

  /// Call right before sending the person to an Android settings page, so the
  /// vault does not lock itself while they are there. Expires after 2 minutes
  /// and ends as soon as they come back.
  void holdLockUntilResume() {
    _holdUntil = DateTime.now().add(const Duration(minutes: 2));
  }

  void onAppResumed() {
    _holdUntil = null;
    syncClock();
  }

  void onAppPaused() {
    final hold = _holdUntil;
    if (hold != null && DateTime.now().isBefore(hold)) return;
    if (_suspendCount == 0) lock();
  }

  // ---- settings -----------------------------------------------------------

  bool get photoOnWrong => _prefs.getBool(_kPhoto) ?? true;

  Future<void> setPhotoOnWrong(bool value) async {
    await _prefs.setBool(_kPhoto, value);
    notifyListeners();
  }

  /// Blocks screenshots, screen recording and the preview in Recent apps.
  bool get blockScreenshots => _prefs.getBool(_kSecure) ?? true;

  Future<void> setBlockScreenshots(bool value) async {
    await _prefs.setBool(_kSecure, value);
    await NativeBridge.setSecure(value);
    notifyListeners();
  }

  /// The "Wrong PIN? Lockeye takes a photo." note on the lock screen. Off by
  /// default, because it tells the person at the keypad that a photo is coming.
  bool get showLockHint => _prefs.getBool(_kHint) ?? false;

  Future<void> setShowLockHint(bool value) async {
    await _prefs.setBool(_kHint, value);
    notifyListeners();
  }

  bool get cameraPrompted => _prefs.getBool(_kCameraAsked) ?? false;

  Future<void> markCameraPrompted() => _prefs.setBool(_kCameraAsked, true);

  /// Photo on the phone's own lock screen. The Android side keeps its own copy
  /// of this switch, because it must work while the app is closed.
  bool get phoneLockEnabled => _prefs.getBool(_kPhoneLock) ?? false;

  Future<void> setPhoneLockEnabled(bool value) async {
    await _prefs.setBool(_kPhoneLock, value);
    await PhoneLockService.configure(enabled: value);
    notifyListeners();
  }

  /// Called when the app opens or comes back: refreshes the Android side and
  /// adds the lock screen attempts that happened meanwhile to the log.
  Future<int> syncPhoneLock() async {
    await PhoneLockService.configure(enabled: phoneLockEnabled);
    return importPhoneShots();
  }

  bool _importing = false;

  Future<int> importPhoneShots() async {
    if (_importing) return 0;
    _importing = true;
    try {
      final shots = await PhoneLockService.takePending();
      if (shots.isEmpty) return 0;
      for (final shot in shots) {
        _insertEntry(
          IntruderEntry(
            id: 'phone_${shot.timeMs}_${shot.attempt}',
            path: shot.path,
            timeMs: shot.timeMs,
            attempt: shot.attempt,
            source: kSourcePhone,
          ),
        );
      }
      await _trimLog();
      await _writeLog();
      notifyListeners();
      return shots.length;
    } finally {
      _importing = false;
    }
  }

  ThemeMode get themeMode {
    switch (_prefs.getString(_kTheme)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(_kTheme, mode.name);
    notifyListeners();
  }

  // ---- intruder log -------------------------------------------------------

  /// Newest first.
  List<IntruderEntry> get intruders => List.unmodifiable(_intruders);

  int get unseenIntruders {
    final seen = _prefs.getInt(_kSeen) ?? 0;
    return _intruders.where((e) => e.timeMs > seen).length;
  }

  List<IntruderEntry> get unseenList {
    final seen = _prefs.getInt(_kSeen) ?? 0;
    return _intruders.where((e) => e.timeMs > seen).toList();
  }

  List<IntruderEntry> _readLog() {
    final raw = _prefs.getString(_kLog);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => IntruderEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeLog() =>
      _prefs.setString(_kLog, jsonEncode(_intruders.map((e) => e.toJson()).toList()));

  Future<void> addIntruder({
    required String? path,
    required int attempt,
    required DateTime time,
  }) async {
    _insertEntry(
      IntruderEntry(
        id: '${time.microsecondsSinceEpoch}',
        path: path,
        timeMs: time.millisecondsSinceEpoch,
        attempt: attempt,
      ),
    );
    await _trimLog();
    await _writeLog();
    notifyListeners();
  }

  /// Keeps the log newest first, even when old lock screen attempts arrive late.
  void _insertEntry(IntruderEntry entry) {
    if (_intruders.any((e) => e.id == entry.id)) return;
    _intruders.add(entry);
    _intruders.sort((a, b) => b.timeMs.compareTo(a.timeMs));
  }

  Future<void> _trimLog() async {
    while (_intruders.length > 200) {
      await _deleteFile(_intruders.removeLast().path);
    }
  }

  Future<void> removeIntruder(String id) async {
    final index = _intruders.indexWhere((e) => e.id == id);
    if (index < 0) return;
    await _deleteFile(_intruders.removeAt(index).path);
    await _writeLog();
    notifyListeners();
  }

  Future<void> clearIntruders() async {
    for (final entry in _intruders) {
      await _deleteFile(entry.path);
    }
    _intruders.clear();
    await _writeLog();
    notifyListeners();
  }

  Future<void> markIntrudersSeen() async {
    await _prefs.setInt(_kSeen, DateTime.now().millisecondsSinceEpoch);
    notifyListeners();
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
