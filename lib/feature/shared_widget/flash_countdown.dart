import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../service/clock_service.dart';
import '../../util/countdown_format.dart';

/// The live `mm:ss` / `hh:mm:ss` text of a flash sale.
///
/// This is the only widget that rebuilds every second: the [Obx] wraps just
/// the [Text], so cards, lists and the rail around it stay untouched.
class FlashCountdownText extends StatelessWidget {
  final DateTime endsAt;
  final TextStyle? style;

  const FlashCountdownText({super.key, required this.endsAt, this.style});

  @override
  Widget build(BuildContext context) {
    final clock = Get.find<ClockService>();
    return Obx(() => Text(
          formatCountdown(endsAt.difference(clock.now.value)),
          style: style,
        ));
  }
}

/// Builds [builder] with whether the flash sale has ended, and rebuilds
/// exactly once: when [endsAt] passes. Used for the card-level "Expired"
/// state, which must not rebuild with every tick of the countdown.
class FlashExpiryBuilder extends StatefulWidget {
  final DateTime endsAt;
  final Widget Function(BuildContext context, bool isExpired) builder;

  const FlashExpiryBuilder(
      {super.key, required this.endsAt, required this.builder});

  @override
  State<FlashExpiryBuilder> createState() => _FlashExpiryBuilderState();
}

class _FlashExpiryBuilderState extends State<FlashExpiryBuilder> {
  final _clock = Get.find<ClockService>();
  Timer? _expiryTimer;
  late bool _isExpired;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(FlashExpiryBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.endsAt != widget.endsAt) _schedule();
  }

  void _schedule() {
    _expiryTimer?.cancel();
    final remaining = widget.endsAt.difference(_clock.current());
    _isExpired = remaining <= Duration.zero;
    if (!_isExpired) {
      // Cancelled in dispose, so this never fires on an unmounted state.
      _expiryTimer = Timer(remaining, () => setState(() => _isExpired = true));
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _isExpired);
}
