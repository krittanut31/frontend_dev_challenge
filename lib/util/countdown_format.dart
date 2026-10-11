/// Formats the time left on a countdown: `mm:ss`, or `hh:mm:ss` from one hour
/// up. Partial seconds round up, so the display reaches `00:00` exactly when
/// the time is up rather than a second early.
String formatCountdown(Duration remaining) {
  if (remaining <= Duration.zero) return '00:00';
  final totalSeconds = (remaining.inMilliseconds / 1000).ceil();
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}
