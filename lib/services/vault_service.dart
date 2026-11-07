import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../core/app_state.dart';
import '../core/keyring.dart';
import '../core/models.dart';
import 'vault_crypto.dart';

enum VaultKind { photos, files }

class VaultItem {
  const VaultItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  /// The encrypted file inside the app's private folder.
  final String path;

  /// The original name, read from the encrypted file.
  final String name;
  final int size;
  final DateTime modified;
}

/// Everything in the vault lives in the app's private folder, one folder per
/// space: `vault/mine` and `vault/family`. Every photo, file and the notes are
/// encrypted (`.lky`). The original file names are encrypted too.
class VaultService {
  static const String ext = '.lky';

  static Future<Directory> _dir(VaultSpace space, [VaultKind? kind]) async {
    final base = await getApplicationDocumentsDirectory();
    final suffix = kind == null ? '' : '/${kind.name}';
    final dir = Directory('${base.path}/vault/${space.name}$suffix');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _basename(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? path : path.substring(i + 1);
  }

  static int _counter = 0;

  static String _newName() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${now.toRadixString(36)}-${(_counter++).toRadixString(36)}$ext';
  }

  // ---- photos and files ---------------------------------------------------

  static Future<List<VaultItem>> list(VaultSpace space, VaultKind kind) async {
    final key = Keyring.of(space);
    if (key == null) return [];
    final dir = await _dir(space, kind);
    final items = <VaultItem>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith(ext)) continue;
      final meta = await VaultCrypto.readMeta(key, entity.path);
      if (meta == null) continue;
      String name = 'File';
      int size = -1;
      int added = 0;
      try {
        final json = jsonDecode(meta) as Map<String, dynamic>;
        name = json['name'] as String? ?? name;
        size = (json['size'] as num?)?.toInt() ?? -1;
        added = (json['added'] as num?)?.toInt() ?? 0;
      } catch (_) {}
      final stat = await entity.stat();
      items.add(VaultItem(
        path: entity.path,
        name: name,
        size: size >= 0 ? size : stat.size,
        modified: added > 0 ? DateTime.fromMillisecondsSinceEpoch(added) : stat.modified,
      ));
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  static Future<int> count(VaultSpace space, VaultKind kind) async {
    final dir = await _dir(space, kind);
    var n = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith(ext)) n++;
    }
    return n;
  }

  /// Opens the system picker and encrypts what the person picks straight into
  /// the vault: no plain copy is made on the way.
  static Future<ImportResult> pickAndImport(AppState state, VaultSpace space, VaultKind kind) async {
    final key = Keyring.of(space);
    if (key == null) return ImportResult.none;
    final dir = await _dir(space, kind);
    return state.keepUnlocked(
      () => VaultCrypto.importPick(key, dir.path, photos: kind == VaultKind.photos),
    );
  }

  /// Asks Android to delete the gallery originals of the last photo import.
  static Future<bool> deleteOriginals(AppState state) =>
      state.keepUnlocked(VaultCrypto.deleteOriginals);

  /// The decrypted photo, or null if it cannot be read.
  static Future<Uint8List?> photoBytes(VaultSpace space, String path) async {
    final cached = Keyring.photoCache[path];
    if (cached != null) return cached;
    final key = Keyring.of(space);
    if (key == null) return null;
    final bytes = await VaultCrypto.readBytes(key, path);
    if (bytes != null) Keyring.remember(path, bytes);
    return bytes;
  }

  /// Decrypts a file to a temporary copy so another app can open it. The copy
  /// is deleted the next time Lockeye unlocks or starts.
  static Future<String?> decryptForOpening(VaultSpace space, VaultItem item) async {
    final key = Keyring.of(space);
    if (key == null) return null;
    final temp = await _tempDir();
    final safe = item.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final out = '${temp.path}/${DateTime.now().microsecondsSinceEpoch}_$safe';
    final ok = await VaultCrypto.decryptToFile(key, item.path, out);
    return ok ? out : null;
  }

  static Future<Directory> _tempDir() async {
    final base = await getTemporaryDirectory();
    final dir = Directory('${base.path}/lockeye_open');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Removes the temporary plain copies made for opening files.
  static Future<void> clearTemp() async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}/lockeye_open');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  static Future<void> delete(String path) async {
    try {
      Keyring.photoCache.remove(path);
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ---- notes --------------------------------------------------------------

  static Future<File> _notesFile(VaultSpace space) async {
    final dir = await _dir(space);
    return File('${dir.path}/notes$ext');
  }

  static Future<List<VaultNote>> notes(VaultSpace space) async {
    try {
      final key = Keyring.of(space);
      if (key == null) return [];
      final file = await _notesFile(space);
      if (!await file.exists()) return [];
      final bytes = await VaultCrypto.readBytes(key, file.path);
      if (bytes == null) return [];
      final list = jsonDecode(utf8.decode(bytes)) as List;
      final notes = list.map((e) => VaultNote.fromJson(e as Map<String, dynamic>)).toList();
      notes.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      return notes;
    } catch (_) {
      return [];
    }
  }

  static Future<int> noteCount(VaultSpace space) async => (await notes(space)).length;

  static Future<void> _writeNotes(VaultSpace space, List<VaultNote> notes) async {
    final key = Keyring.of(space);
    if (key == null) return;
    final file = await _notesFile(space);
    final data = utf8.encode(jsonEncode(notes.map((e) => e.toJson()).toList()));
    await VaultCrypto.encryptBytes(key, Uint8List.fromList(data), file.path);
  }

  static Future<void> saveNote(VaultSpace space, VaultNote note) async {
    final all = await notes(space);
    final i = all.indexWhere((e) => e.id == note.id);
    if (i >= 0) {
      all[i] = note;
    } else {
      all.add(note);
    }
    await _writeNotes(space, all);
  }

  static Future<void> deleteNote(VaultSpace space, String id) async {
    final all = await notes(space);
    all.removeWhere((e) => e.id == id);
    await _writeNotes(space, all);
  }

  // ---- update from older versions ----------------------------------------

  /// Versions before 1.2.0 kept photos, files and notes as plain files. This
  /// encrypts whatever is still plain, and is safe to run again if it was
  /// interrupted.
  static Future<void> migrateLegacy(VaultSpace space, Uint8List key) async {
    for (final kind in VaultKind.values) {
      final dir = await _dir(space, kind);
      final plain = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && !entity.path.endsWith(ext) && !entity.path.endsWith('.tmp')) {
          plain.add(entity);
        }
      }
      for (final file in plain) {
        try {
          final stat = await file.stat();
          final meta = jsonEncode({
            'name': _basename(file.path),
            'size': stat.size,
            'added': stat.modified.millisecondsSinceEpoch,
            'kind': kind == VaultKind.photos ? 'photo' : 'file',
          });
          await VaultCrypto.encryptFile(key, file.path, '${dir.path}/${_newName()}', meta);
          await file.delete();
        } catch (_) {
          // Leave this one for the next run.
        }
      }
    }

    final space0 = await _dir(space);
    final oldNotes = File('${space0.path}/notes.json');
    if (await oldNotes.exists()) {
      try {
        final target = await _notesFile(space);
        if (!await target.exists()) {
          final bytes = await oldNotes.readAsBytes();
          await VaultCrypto.encryptBytes(key, bytes, target.path);
          await oldNotes.delete();
        }
      } catch (_) {}
    }
  }
}
