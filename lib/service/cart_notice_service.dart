import 'dart:async';

import 'package:get/get.dart';

import 'cart_service.dart';

/// Shows [CartService.notices] (changes to the bag the user did not make,
/// e.g. a hold that failed and was rolled back) as snackbars on any screen.
class CartNoticeService extends GetxService {
  CartNoticeService({required this.cart});

  final CartService cart;
  late final StreamSubscription<String> _subscription;

  @override
  void onInit() {
    super.onInit();
    _subscription = cart.notices.listen((message) => Get.snackbar(
          'Your bag changed',
          message,
          snackPosition: SnackPosition.BOTTOM,
          duration: const Duration(seconds: 4),
        ));
  }

  @override
  void onClose() {
    _subscription.cancel();
    super.onClose();
  }
}
