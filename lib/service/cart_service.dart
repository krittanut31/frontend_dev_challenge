import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../util/log_service.dart';

/// App-wide cart. Lives for the whole session.
///
/// NOTE: the starter cart is purely local — it does not reserve stock on the
/// backend. See the "Reservations" feature task in PROBLEM.md.
class CartService extends GetxService {
  CartService({DateTime Function() clock = DateTime.now}) : _clock = clock;

  final DateTime Function() _clock;

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// Adds one of [deal]. Returns false when nothing was added: the flash sale
  /// has ended, or there is no more stock.
  bool add(DealModel deal) {
    if (deal.isFlashExpiredAt(_clock())) {
      LogService.log('cart: flash sale for deal ${deal.id} has ended');
      return false;
    }
    final existing = items.firstWhereOrNull((i) => i.deal.id == deal.id);
    if (existing != null) {
      if (existing.quantity >= deal.quantityLeft) {
        LogService.log('cart: cannot add more of deal ${deal.id}');
        return false;
      }
      existing.quantity++;
      items.refresh();
    } else {
      items.add(CartItemModel(deal: deal));
    }
    _recount();
    return true;
  }

  /// Removes every line whose flash sale has ended at [now] and returns the
  /// removed deals, so the caller can tell the user.
  List<DealModel> removeExpiredFlashDeals(DateTime now) {
    final expired = items
        .where((i) => i.deal.isFlashExpiredAt(now))
        .map((i) => i.deal)
        .toList();
    if (expired.isEmpty) return const [];
    items.removeWhere((i) => i.deal.isFlashExpiredAt(now));
    _recount();
    return expired;
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    existing.quantity--;
    if (existing.quantity <= 0) {
      items.removeWhere((i) => i.deal.id == dealId);
    } else {
      items.refresh();
    }
    _recount();
  }

  void remove(int dealId) {
    items.removeWhere((i) => i.deal.id == dealId);
    _recount();
  }

  void clear() {
    items.clear();
    _recount();
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _recount() {
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }
}
