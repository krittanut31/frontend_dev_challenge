import 'package:get/get.dart';

import 'cart_service.dart';
import 'clock_service.dart';

/// Removes flash deals from the bag when their sale ends, and tells the user.
///
/// Kept out of [CartService] so the cart stays free of UI calls; this is the
/// glue between the clock, the cart and the snackbar.
class FlashSaleExpiryService extends GetxService {
  FlashSaleExpiryService({required this.clock, required this.cart});

  final ClockService clock;
  final CartService cart;
  late final Worker _tickWorker;

  @override
  void onInit() {
    super.onInit();
    _tickWorker = ever(clock.now, (_) => sweep());
  }

  /// Removes ended flash deals now. Runs on every clock tick.
  void sweep() {
    final removed = cart.removeExpiredFlashDeals(clock.current());
    if (removed.isEmpty) return;
    final names = removed.map((d) => d.name).join(', ');
    Get.snackbar(
      'Removed from your bag',
      'The flash sale ended for $names.',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void onClose() {
    _tickWorker.dispose();
    super.onClose();
  }
}
