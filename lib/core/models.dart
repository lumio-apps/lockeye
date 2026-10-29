/// The two spaces of the vault. The owner's PIN opens [mine] (and can also
/// look into [family]); the family PIN opens only [family].
enum VaultSpace { mine, family }

enum UnlockResult { mine, family, wrong, lockedOut }

/// One wrong PIN attempt. [path] is null when no photo could be taken.
class IntruderEntry {
  const IntruderEntry({
    required this.id,
    required this.path,
    required this.timeMs,
    required this.attempt,
  });

  final String id;
  final String? path;
  final int timeMs;
  final int attempt;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timeMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'time': timeMs,
        'attempt': attempt,
      };

  factory IntruderEntry.fromJson(Map<String, dynamic> json) => IntruderEntry(
        id: json['id'] as String? ?? '',
        path: json['path'] as String?,
        timeMs: json['time'] as int? ?? 0,
        attempt: json['attempt'] as int? ?? 1,
      );
}

class VaultNote {
  const VaultNote({
    required this.id,
    required this.title,
    required this.body,
    required this.updatedMs,
  });

  final String id;
  final String title;
  final String body;
  final int updatedMs;

  DateTime get updated => DateTime.fromMillisecondsSinceEpoch(updatedMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'updated': updatedMs,
      };

  factory VaultNote.fromJson(Map<String, dynamic> json) => VaultNote(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        body: json['body'] as String? ?? '',
        updatedMs: json['updated'] as int? ?? 0,
      );
}
