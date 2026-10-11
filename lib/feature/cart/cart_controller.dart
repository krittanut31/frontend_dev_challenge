import 'package:get/get.dart';

import '../../repository/order_repo.dart';
import '../../service/api_exception.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class CartController extends GetxController {
  final CartService cartService;
  final OrderRepo orderRepo;

  CartController({required this.cartService, required this.orderRepo});

  final isCheckingOut = false.obs;

  Future<void> checkout() async {
    if (cartService.items.isEmpty || isCheckingOut.value) return;
    if (cartService.hasPendingHolds) {
      // The button is disabled meanwhile; this only guards a race.
      return;
    }
    isCheckingOut.value = true;
    try {
      // Holds expire after 5 minutes. Re-reserve expired lines first; if one
      // cannot be held it is removed (with a notice) and the user reviews the
      // bag before paying, rather than paying for a different bag.
      if (!await cartService.ensureHolds()) return;
      await _placeOrder(retryOnExpiredHold: true);
    } finally {
      isCheckingOut.value = false;
    }
  }

  Future<void> _placeOrder({required bool retryOnExpiredHold}) async {
    try {
      final order = await orderRepo.checkout(cartService.items.toList());
      cartService.clear();
      Get.snackbar(
        'Order confirmed',
        'Order #${order.id} — pick up soon!',
        snackPosition: SnackPosition.BOTTOM,
      );
    } on ApiException catch (e) {
      LogService.error('checkout failed', e);
      if (e.statusCode == 410 && retryOnExpiredHold) {
        // A hold expired (or is unknown to the backend) between our check and
        // the order. The bag is unchanged, so renew all holds and try once
        // more; if any line cannot be held, stop and let the user review.
        if (await cartService.renewAllHolds()) {
          await _placeOrder(retryOnExpiredHold: false);
        }
        return;
      }
      Get.snackbar(
        'Checkout failed',
        e.statusCode == 410
            ? 'Some items are no longer held for you. Please review your '
                'bag and try again.'
            : e.message,
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }
}
