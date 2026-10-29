import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_state.dart';
import '../core/models.dart';

enum VaultKind { photos, files }

class VaultItem {
  const VaultItem({
    required this.path,
    required this.name,
    required this.size,
    required this.modified,
  });

  final String path;
  final String name;
  final int size;
  final DateTime modified;
}

/// Everything in the vault lives in the app's private folder, one folder per
/// space: `vault/mine` and `vault/family`.
class VaultService {
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

  static File _uniqueFile(Directory dir, String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    var file = File('${dir.path}/$name');
    var n = 1;
    while (file.existsSync()) {
      file = File('${dir.path}/$stem ($n)$ext');
      n++;
    }
    return file;
  }

  // ---- photos and files ---------------------------------------------------

  static Future<List<VaultItem>> list(VaultSpace space, VaultKind kind) async {
    final dir = await _dir(space, kind);
    final items = <VaultItem>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final stat = await entity.stat();
      items.add(VaultItem(
        path: entity.path,
        name: _basename(entity.path),
        size: stat.size,
        modified: stat.modified,
      ));
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    return items;
  }

  static Future<int> count(VaultSpace space, VaultKind kind) async {
    final dir = await _dir(space, kind);
    var n = 0;
    await for (final entity in dir.list()) {
      if (entity is File) n++;
    }
    return n;
  }

  static Future<int> importPaths(VaultSpace space, VaultKind kind, List<String> paths) async {
    final dir = await _dir(space, kind);
    var added = 0;
    for (final path in paths) {
      try {
        final dest = _uniqueFile(dir, _basename(path));
        await File(path).copy(dest.path);
        added++;
      } catch (_) {}
    }
    return added;
  }

  /// Opens the system picker and copies what the person picked into the vault.
  /// The picker's temporary copies are removed afterwards. Returns how many
  /// items were added (0 if cancelled).
  static Future<int> pickAndImport(AppState state, VaultSpace space, VaultKind kind) async {
    final result = await state.keepUnlocked(
      () => FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: kind == VaultKind.photos ? FileType.image : FileType.any,
      ),
    );
    if (result == null) return 0;
    final paths = result.paths.whereType<String>().toList();
    final added = await importPaths(space, kind, paths);
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
    return added;
  }

  static Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ---- notes --------------------------------------------------------------

  static Future<File> _notesFile(VaultSpace space) async {
    final dir = await _dir(space);
    return File('${dir.path}/notes.json');
  }

  static Future<List<VaultNote>> notes(VaultSpace space) async {
    try {
      final file = await _notesFile(space);
      if (!await file.exists()) return [];
      final list = jsonDecode(await file.readAsString()) as List;
      final notes = list.map((e) => VaultNote.fromJson(e as Map<String, dynamic>)).toList();
      notes.sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
      return notes;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeNotes(VaultSpace space, List<VaultNote> notes) async {
    final file = await _notesFile(space);
    await file.writeAsString(jsonEncode(notes.map((e) => e.toJson()).toList()));
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
}
