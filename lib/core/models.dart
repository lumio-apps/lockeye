/// The two spaces of the vault. The owner's PIN opens [mine] (and can also
/// look into [family]); the family PIN opens only [family].
enum VaultSpace { mine, family }

enum UnlockResult { mine, family, wrong, lockedOut }

/// Where a wrong attempt happened.
const String kSourceApp = 'app';
const String kSourcePhone = 'phone';

/// One wrong PIN attempt. [path] is null when no photo could be taken.
/// [source] is [kSourceApp] (Lockeye's own keypad) or [kSourcePhone] (the
/// phone's lock screen). A phone attempt number of 0 is a test photo.
class IntruderEntry {
  const IntruderEntry({
    required this.id,
    required this.path,
    required this.timeMs,
    required this.attempt,
    this.source = kSourceApp,
  });

  final String id;
  final String? path;
  final int timeMs;
  final int attempt;
  final String source;

  bool get isPhone => source == kSourcePhone;
  bool get isTest => isPhone && attempt == 0;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(timeMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'time': timeMs,
        'attempt': attempt,
        'source': source,
      };

  factory IntruderEntry.fromJson(Map<String, dynamic> json) => IntruderEntry(
        id: json['id'] as String? ?? '',
        path: json['path'] as String?,
        timeMs: json['time'] as int? ?? 0,
        attempt: json['attempt'] as int? ?? 1,
        source: json['source'] as String? ?? kSourceApp,
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
