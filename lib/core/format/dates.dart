/// Date and time labels in the style the prototype uses (`Sat, Aug 22`,
/// `8:00 AM`). Always in the phone's local time zone.
abstract final class Dates {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// `Sat, Aug 22`
  static String day(DateTime value) {
    final local = value.toLocal();
    return '${_weekdays[local.weekday - 1]}, ${monthDay(local)}';
  }

  /// `Aug 22`
  static String monthDay(DateTime value) {
    final local = value.toLocal();
    return '${_months[local.month - 1]} ${local.day}';
  }

  /// `8:00 AM`
  static String time(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }

  /// `Sat, Aug 22 · 8:00 AM`
  static String dayAndTime(DateTime value) => '${day(value)} · ${time(value)}';

  /// `Oct 2 - Oct 8, 2026`
  static String range(DateTime start, DateTime end) =>
      '${monthDay(start)} - ${monthDay(end)}, ${end.toLocal().year}';

  /// How long ago, for inbox items: `just now`, `5m ago`, `2h ago`, `3d ago`,
  /// then the date.
  static String ago(DateTime value, {DateTime? now}) {
    final elapsed = (now ?? DateTime.now()).difference(value);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
    if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
    if (elapsed.inDays < 7) return '${elapsed.inDays}d ago';
    return monthDay(value);
  }
}
