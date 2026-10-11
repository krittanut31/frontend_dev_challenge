import 'dart:async';

import 'package:get/get.dart';

/// One app-wide one-second tick for everything that shows live time.
///
/// A single timer instead of one per countdown: with 100+ flash deals on
/// screen, each countdown only subscribes to [now] and rebuilds its own text.
class ClockService extends GetxService {
  ClockService({DateTime Function() clock = DateTime.now}) : _clock = clock;

  /// Source of the current time; injectable so tests can control it.
  final DateTime Function() _clock;

  late final Rx<DateTime> now = _clock().obs;
  Timer? _ticker;

  /// The current time, read straight from the clock (not the last tick).
  DateTime current() => _clock();

  @override
  void onInit() {
    super.onInit();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  /// Publishes the current time to listeners. Called by the ticker every
  /// second; tests call it directly after moving their fake clock.
  void tick() => now.value = _clock();

  @override
  void onClose() {
    _ticker?.cancel();
    super.onClose();
  }
}
