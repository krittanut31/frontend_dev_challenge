import 'dart:async';

import 'package:get/get.dart';

import '../model/cart_item_model.dart';
import '../model/deal_model.dart';
import '../model/reservation_model.dart';
import '../util/log_service.dart';

/// Places a hold of [quantity] units on a deal.
typedef ReserveStock = Future<ReservationModel> Function(int dealId,
    {int quantity});

/// Releases a hold.
typedef ReleaseStock = Future<void> Function(String reservationId);

/// App-wide cart. Lives for the whole session.
///
/// With [reserve]/[release] set, every change to a line is reflected in a
/// stock hold on the backend. The cart updates optimistically: a line changes
/// at once, the hold is requested in the background, and if it fails the
/// line goes back to the quantity the last successful hold covers, with a
/// message on [notices]. Without them (tests, previews) the cart is local.
class CartService extends GetxService {
  CartService({
    DateTime Function() clock = DateTime.now,
    this.reserve,
    this.release,
  }) : _clock = clock;

  final DateTime Function() _clock;
  final ReserveStock? reserve;
  final ReleaseStock? release;

  final items = <CartItemModel>[].obs;
  final itemCount = 0.obs;

  /// User-facing messages about changes the user did not make themselves
  /// (a failed hold rolled back). Shown by the UI layer.
  final _notices = StreamController<String>.broadcast();
  Stream<String> get notices => _notices.stream;

  /// Latest hold request per deal. A response for an older request is
  /// stale: the line has changed since, so the hold is released, not used.
  final _latestHoldRequest = <int, int>{};
  int _holdRequestSeq = 0;

  bool get hasPendingHolds => items.any((i) => i.isReserving);

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
    } else {
      items.add(CartItemModel(deal: deal));
    }
    _changed();
    _syncHold(deal.id);
    return true;
  }

  void decrement(int dealId) {
    final existing = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (existing == null) return;
    if (existing.quantity <= 1) {
      remove(dealId);
      return;
    }
    existing.quantity--;
    _changed();
    _syncHold(dealId);
  }

  void remove(int dealId) {
    final line = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (line == null) return;
    items.remove(line);
    _latestHoldRequest.remove(dealId); // any in-flight hold is now stale
    _releaseHold(line.reservation);
    _changed();
  }

  /// Empties the cart after a successful checkout. The holds were used by
  /// the order, so they are not released.
  void clear() {
    items.clear();
    _latestHoldRequest.clear();
    _changed();
  }

  /// Removes every line whose flash sale has ended at [now], releases their
  /// holds, and returns the removed deals so the caller can tell the user.
  List<DealModel> removeExpiredFlashDeals(DateTime now) {
    final expired = items.where((i) => i.deal.isFlashExpiredAt(now)).toList();
    for (final line in expired) {
      remove(line.deal.id);
    }
    return [for (final line in expired) line.deal];
  }

  /// Makes sure every line is covered by a live hold, re-reserving lines
  /// whose hold expired. Returns false if any line could not be held (it is
  /// then rolled back, with a notice), so checkout should stop and let the
  /// user review the bag.
  Future<bool> ensureHolds() async {
    if (reserve == null) return true;
    final now = _clock();
    final missing =
        items.where((i) => !i.isHeldAt(now) && !i.isReserving).toList();
    final results = await Future.wait(
        [for (final line in missing) _syncHold(line.deal.id)]);
    return results.every((ok) => ok);
  }

  /// Tries again to hold one line, e.g. after its hold expired.
  Future<bool> reserveAgain(int dealId) => _syncHold(dealId);

  /// Replaces every line's hold with a fresh one, e.g. after the backend
  /// rejected checkout with 410 (a hold expired or is unknown to it).
  Future<bool> renewAllHolds() async {
    if (reserve == null) return true;
    final results = await Future.wait(
        [for (final line in items.toList()) _syncHold(line.deal.id)]);
    return results.every((ok) => ok);
  }

  /// Requests a hold for the line's current quantity and swaps it in.
  /// Returns whether the line ended up held as the user left it.
  Future<bool> _syncHold(int dealId) async {
    final reserveFn = reserve;
    if (reserveFn == null) return true;
    final line = items.firstWhereOrNull((i) => i.deal.id == dealId);
    if (line == null) return true;

    final requestId = ++_holdRequestSeq;
    _latestHoldRequest[dealId] = requestId;
    final wanted = line.quantity;
    line.isReserving = true;
    items.refresh();

    bool isLatest() =>
        _latestHoldRequest[dealId] == requestId && items.contains(line);

    try {
      final hold = await reserveFn(dealId, quantity: wanted);
      if (!isLatest()) {
        // Superseded by a newer request. Keep this hold as a fallback if it
        // covers more than the line's current hold, so a failure of the
        // newer request rolls back to it instead of to nothing.
        if (items.contains(line) && _isBetterFallback(line, hold)) {
          final previous = line.reservation;
          line.reservation = hold;
          _releaseHold(previous);
        } else {
          _releaseHold(hold);
        }
        return true;
      }
      final previous = line.reservation;
      line.reservation = hold;
      line.isReserving = false;
      items.refresh();
      _releaseHold(previous);
      return true;
    } catch (e) {
      if (!isLatest()) return true;
      LogService.error('reserve deal $dealId x$wanted failed', e);
      line.isReserving = false;
      _rollBack(line, wanted);
      return false;
    }
  }

  bool _isBetterFallback(CartItemModel line, ReservationModel hold) {
    if (hold.quantity > line.quantity) return false;
    final current = line.reservation;
    return current == null ||
        !_clock().isBefore(current.expiresAt) ||
        hold.quantity > current.quantity;
  }

  /// After a failed hold for [wanted] units, puts the line back to what its
  /// last live hold covers.
  void _rollBack(CartItemModel line, int wanted) {
    final hold = line.reservation;
    final covered =
        hold != null && _clock().isBefore(hold.expiresAt) ? hold.quantity : 0;
    if (covered >= wanted) {
      // A reduction failed to re-reserve; the bigger hold still covers it.
      items.refresh();
      return;
    }
    final name = line.deal.name;
    if (covered == 0) {
      items.remove(line);
      _latestHoldRequest.remove(line.deal.id);
      _notices.add("We couldn't hold $name for you: someone may have just "
          'taken the last one. It was removed from your bag.');
    } else {
      line.quantity = covered;
      _notices.add("We couldn't hold another $name for you: someone may "
          'have just taken it. Your bag has $covered.');
    }
    _changed();
  }

  void _releaseHold(ReservationModel? hold) {
    final releaseFn = release;
    if (hold == null || releaseFn == null) return;
    // Fire and forget: if this fails the hold still expires on its own.
    releaseFn(hold.id).catchError(
        (Object e) => LogService.error('release ${hold.id} failed', e));
  }

  num get total => items.fold(0, (sum, i) => sum + i.lineTotal);

  void _changed() {
    items.refresh();
    itemCount.value = items.fold(0, (sum, i) => sum + i.quantity);
  }

  @override
  void onClose() {
    _notices.close();
    super.onClose();
  }
}
