String _two(int n) => n.toString().padLeft(2, '0');

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "Today, 21:47", "Yesterday, 08:12", "Mon, 23:30" or "20 Oct 2026, 09:05".
String formatWhen(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  final hm = '${_two(time.hour)}:${_two(time.minute)}';
  if (diff == 0) return 'Today, $hm';
  if (diff == 1) return 'Yesterday, $hm';
  if (diff > 1 && diff < 7) return '${_weekdays[time.weekday - 1]}, $hm';
  return '${time.day} ${_months[time.month - 1]} ${time.year}, $hm';
}

String formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
