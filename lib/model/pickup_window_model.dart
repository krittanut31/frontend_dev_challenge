import 'package:intl/intl.dart';

/// A store's pickup window. The API sends instants as ISO-8601 UTC strings,
/// and [start]/[end] keep them as UTC instants. Anything that reads them as
/// a wall-clock time (labels, "today") must convert to local time first.
class PickupWindowModel {
  final DateTime start;
  final DateTime end;

  const PickupWindowModel({required this.start, required this.end});

  factory PickupWindowModel.fromJson(Map<String, dynamic> json) {
    return PickupWindowModel(
      start: DateTime.parse(json['start'] as String? ?? ''),
      end: DateTime.parse(json['end'] as String? ?? ''),
    );
  }

  /// Human readable label in local time, e.g. "17:30 – 21:00".
  String get label {
    final format = DateFormat('HH:mm');
    return '${format.format(start.toLocal())} – ${format.format(end.toLocal())}';
  }

  /// Whether pickup is possible today.
  bool get isToday => isTodayAt(DateTime.now());

  /// [isToday] relative to a given [now], so it can be tested at any time.
  /// True when the window overlaps [now]'s local calendar day, which also
  /// covers an overnight window that started yesterday and is still open.
  bool isTodayAt(DateTime now) {
    final local = now.toLocal();
    final dayStart = DateTime(local.year, local.month, local.day);
    final dayEnd = DateTime(local.year, local.month, local.day + 1);
    return start.isBefore(dayEnd) && end.isAfter(dayStart);
  }

  /// Whether the store is currently accepting pickups.
  bool get isOpenNow {
    final now = DateTime.now();
    return now.isAfter(start) && now.isBefore(end);
  }

  Duration get untilStart => start.difference(DateTime.now());
}
