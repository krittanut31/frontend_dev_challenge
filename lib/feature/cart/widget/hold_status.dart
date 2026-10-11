import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../model/cart_item_model.dart';
import '../../../service/cart_service.dart';
import '../../../service/clock_service.dart';
import '../../../util/countdown_format.dart';

/// One bag line's stock hold: "Reserving…", "Held for 4:32", or
/// "Hold expired · Reserve again".
///
/// Rebuilt by its own Obx once a second (for the countdown), so the rest of
/// the bag line does not rebuild with the clock.
class HoldStatus extends StatelessWidget {
  final CartItemModel item;

  const HoldStatus({super.key, required this.item});

  static const _warnBelow = Duration(minutes: 1);

  @override
  Widget build(BuildContext context) {
    final clock = Get.find<ClockService>();
    final cart = Get.find<CartService>();
    return Obx(() {
      final now = clock.now.value;
      const small = TextStyle(fontSize: 12);
      if (item.isReserving) {
        return const Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5)),
          SizedBox(width: 6),
          Text('Reserving…', style: small),
        ]);
      }
      final hold = item.reservation;
      if (hold != null && item.isHeldAt(now)) {
        final left = hold.expiresAt.difference(now);
        final color =
            left < _warnBelow ? Colors.red.shade700 : Colors.grey.shade700;
        return Text('Held for ${formatCountdown(left)}',
            style: small.copyWith(
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()]));
      }
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Text('Hold expired',
            style: small.copyWith(color: Colors.orange.shade800)),
        TextButton(
          style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6)),
          onPressed: () => cart.reserveAgain(item.deal.id),
          child: const Text('Reserve again', style: small),
        ),
      ]);
    });
  }
}
