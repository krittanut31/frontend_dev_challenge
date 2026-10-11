import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/pickup_window_model.dart';

/// Builds the API payload for a window given in the device's local wall-clock
/// time, the way the backend sends it: ISO-8601 UTC instants.
PickupWindowModel _window(DateTime localStart, DateTime localEnd) =>
    PickupWindowModel.fromJson({
      'start': localStart.toUtc().toIso8601String(),
      'end': localEnd.toUtc().toIso8601String(),
    });

void main() {
  // The bug only shows when the device is not on UTC; on a UTC machine these
  // tests pass either way. Run with e.g. `TZ=Asia/Bangkok flutter test`.
  final offset = DateTime(2026, 1, 2).timeZoneOffset;
  final note = offset == Duration.zero
      ? ' (device is on UTC, so this cannot catch the bug here)'
      : '';

  group('label$note', () {
    test('shows the store hours in local time', () {
      final bakery = _window(
          DateTime(2026, 1, 2, 6, 0), DateTime(2026, 1, 2, 9, 30));
      expect(bakery.label, '06:00 – 09:30');
    });

    test('shows an overnight window in local time', () {
      final bar = _window(
          DateTime(2026, 1, 2, 22, 0), DateTime(2026, 1, 3, 1, 0));
      expect(bar.label, '22:00 – 01:00');
    });
  });

  group('isTodayAt$note', () {
    final morning = DateTime(2026, 1, 2, 5, 0);

    test('includes an early-morning window today', () {
      final bakery = _window(
          DateTime(2026, 1, 2, 6, 0), DateTime(2026, 1, 2, 9, 30));
      expect(bakery.isTodayAt(morning), isTrue);
    });

    test('includes a window later today', () {
      final dinner = _window(
          DateTime(2026, 1, 2, 18, 0), DateTime(2026, 1, 2, 21, 0));
      expect(dinner.isTodayAt(morning), isTrue);
    });

    test('excludes tomorrow', () {
      final tomorrow = _window(
          DateTime(2026, 1, 3, 6, 0), DateTime(2026, 1, 3, 9, 30));
      expect(tomorrow.isTodayAt(morning), isFalse);
    });

    test('excludes the same day of another month', () {
      final nextMonth = _window(
          DateTime(2026, 2, 2, 6, 0), DateTime(2026, 2, 2, 9, 30));
      expect(nextMonth.isTodayAt(morning), isFalse);
    });

    test('includes an overnight window still open after midnight', () {
      final bar = _window(
          DateTime(2026, 1, 1, 22, 0), DateTime(2026, 1, 2, 1, 0));
      expect(bar.isTodayAt(DateTime(2026, 1, 2, 0, 30)), isTrue);
    });
  });
}
