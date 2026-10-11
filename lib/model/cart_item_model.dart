import 'deal_model.dart';
import 'reservation_model.dart';

class CartItemModel {
  final DealModel deal;
  int quantity;

  /// Stock hold for this line item, covering `reservation.quantity` units
  /// until `reservation.expiresAt`. Null until the first hold succeeds.
  ReservationModel? reservation;

  /// True while a hold for the current [quantity] is being requested.
  bool isReserving;

  CartItemModel({
    required this.deal,
    this.quantity = 1,
    this.reservation,
    this.isReserving = false,
  });

  num get lineTotal => deal.price * quantity;

  /// Whether [reservation] is still valid at [now] and covers [quantity].
  bool isHeldAt(DateTime now) {
    final hold = reservation;
    return hold != null &&
        now.isBefore(hold.expiresAt) &&
        hold.quantity >= quantity;
  }
}
