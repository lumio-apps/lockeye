import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/phone_lock_service.dart';
import 'models.dart';
import 'pin_hasher.dart';

const int kPinLength = 4;

/// After this many wrong PINs in a row the keypad is locked for a while.
const int kFreeTries = 5;

/// Everything the app remembers: PINs (hashed), settings, the intruder log
/// and which space is currently unlocked (null = locked).
class AppState extends ChangeNotifier {
  AppState._(this._prefs) {
    _intruders = _readLog();
  }

  static Future<AppState> load() async => AppState._(await SharedPreferences.getInstance());

  static const _kMine = 'pin_mine';
  static const _kFamily = 'pin_family';
  static const _kFamilyOn = 'family_on';
  static const _kPhoto = 'photo_on_wrong';
  static const _kPhoneLock = 'phone_lock_on';
  static const _kTheme = 'theme_mode';
  static const _kFails = 'fail_count';
  static const _kLockUntil = 'lock_until';
  static const _kLog = 'intruder_log';
  static const _kSeen = 'intruders_seen';

  final SharedPreferences _prefs;
  late List<IntruderEntry> _intruders;
  int _suspendCount = 0;

  /// The unlocked space, or null while the app is locked.
  VaultSpace? space;

  // ---- setup & PINs -------------------------------------------------------

  bool get isSetUp => _prefs.getString(_kMine) != null;
  bool get hasFamilyPin => _prefs.getString(_kFamily) != null;
  bool get familyEnabled => hasFamilyPin && (_prefs.getBool(_kFamilyOn) ?? true);

  Future<void> completeSetup(String minePin, {String? familyPin}) async {
    await _prefs.setString(_kMine, PinHasher.create(minePin));
    if (familyPin != null) {
      await _prefs.setString(_kFamily, PinHasher.create(familyPin));
      await _prefs.setBool(_kFamilyOn, true);
    }
    space = VaultSpace.mine;
    notifyListeners();
  }

  bool matchesMine(String pin) {
    final stored = _prefs.getString(_kMine);
    return stored != null && PinHasher.verify(pin, stored);
  }

  bool matchesFamily(String pin) {
    final stored = _prefs.getString(_kFamily);
    return stored != null && PinHasher.verify(pin, stored);
  }

  Future<void> setMinePin(String pin) async {
    await _prefs.setString(_kMine, PinHasher.create(pin));
    notifyListeners();
  }

  Future<void> setFamilyPin(String pin) async {
    await _prefs.setString(_kFamily, PinHasher.create(pin));
    await _prefs.setBool(_kFamilyOn, true);
    notifyListeners();
  }

  Future<void> setFamilyEnabled(bool value) async {
    await _prefs.setBool(_kFamilyOn, value);
    notifyListeners();
  }

  // ---- unlocking ----------------------------------------------------------

  int get failCount => _prefs.getInt(_kFails) ?? 0;

  Duration get lockRemaining {
    final until = _prefs.getInt(_kLockUntil) ?? 0;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    return left > 0 ? Duration(milliseconds: left) : Duration.zero;
  }

  UnlockResult unlock(String pin) {
    if (lockRemaining > Duration.zero) return UnlockResult.lockedOut;
    if (matchesMine(pin)) {
      _succeed(VaultSpace.mine);
      return UnlockResult.mine;
    }
    if (familyEnabled && matchesFamily(pin)) {
      _succeed(VaultSpace.family);
      return UnlockResult.family;
    }
    _registerFailure();
    return UnlockResult.wrong;
  }

  void _succeed(VaultSpace target) {
    _prefs.setInt(_kFails, 0);
    _prefs.setInt(_kLockUntil, 0);
    space = target;
    notifyListeners();
  }

  void _registerFailure() {
    final count = failCount + 1;
    _prefs.setInt(_kFails, count);
    if (count % kFreeTries == 0) {
      final level = count ~/ kFreeTries;
      final seconds = min(30 * (1 << min(level - 1, 4)), 300);
      final until = DateTime.now().add(Duration(seconds: seconds));
      _prefs.setInt(_kLockUntil, until.millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  void lock() {
    if (space == null) return;
    space = null;
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
