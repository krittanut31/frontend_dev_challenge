import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/model/cart_item_model.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/reservation_model.dart';
import 'package:rescu/service/api_exception.dart';
import 'package:rescu/service/cart_service.dart';

/// A reservations backend whose every request the test resolves by hand.
class _Holds {
  final requests =
      <({int dealId, int quantity, Completer<ReservationModel> c})>[];
  final released = <String>[];
  int _seq = 0;
  DateTime Function() now = DateTime.now;

  Future<ReservationModel> reserve(int dealId, {int quantity = 1}) {
    final c = Completer<ReservationModel>();
    requests.add((dealId: dealId, quantity: quantity, c: c));
    return c.future;
  }

  Future<void> release(String id) async => released.add(id);

  /// Grants the oldest pending request; returns the reservation id.
  String grant() {
    final r = requests.removeAt(0);
    final id = 'res_${++_seq}';
    r.c.complete(ReservationModel(
      id: id,
      dealId: r.dealId,
      quantity: r.quantity,
      expiresAt: now().add(const Duration(minutes: 5)),
    ));
    return id;
  }

  void refuse() => requests.removeAt(0).c.completeError(const ApiException(
      'Could not reserve: someone grabbed the last one. Try again.',
      statusCode: 409));
}

DealModel _deal(int id, {int stock = 5}) => DealModel.fromJson({
      'id': id,
      'name': 'Deal $id',
      'description': '',
      'imageUrl': '',
      'originalPrice': 100,
      'price': 50,
      'currencyCode': 'THB',
      'quantityLeft': stock,
      'storeId': 1,
      'storeName': 'Store',
      'storeAddress': '',
      'lat': 0,
      'lng': 0,
      'rating': null,
      'tags': <String>[],
      'pickupWindow': {
        'start': '2026-01-01T10:00:00.000Z',
        'end': '2026-01-01T12:00:00.000Z',
      },
      'flashSaleEndsAt': null,
    });

void main() {
  late _Holds holds;
  late CartService cart;
  late List<String> notices;
  late DateTime now;

  setUp(() {
    now = DateTime(2026, 1, 2, 12);
    holds = _Holds()..now = () => now;
    cart = CartService(
        clock: () => now, reserve: holds.reserve, release: holds.release);
    notices = [];
    cart.notices.listen(notices.add);
  });

  CartItemModel line(int id) => cart.items.firstWhere((i) => i.deal.id == id);

  group('optimistic add', () {
    test('the line appears at once and the hold arrives later', () async {
      expect(cart.add(_deal(1)), isTrue);
      expect(line(1).quantity, 1);
      expect(line(1).isReserving, isTrue);
      expect(cart.hasPendingHolds, isTrue);

      final id = holds.grant();
      await pumpEventQueue();

      expect(line(1).reservation!.id, id);
      expect(line(1).isReserving, isFalse);
      expect(line(1).isHeldAt(now), isTrue);
    });

    test('a refused hold removes the new line with a plain message', () async {
      cart.add(_deal(1));
      holds.refuse();
      await pumpEventQueue();

      expect(cart.items, isEmpty);
      expect(cart.itemCount.value, 0);
      expect(notices.single, contains("couldn't hold Deal 1"));
      expect(notices.single, isNot(contains('409')));
    });

    test('a refused increase goes back to the held quantity', () async {
      cart.add(_deal(1));
      holds.grant();
      await pumpEventQueue();

      cart.add(_deal(1)); // 2
      holds.refuse();
      await pumpEventQueue();

      expect(line(1).quantity, 1);
      expect(line(1).isHeldAt(now), isTrue);
      expect(notices.single, contains('Your bag has 1'));
    });
  });

  group('adjusting and removing', () {
    test('changing the quantity swaps the hold and releases the old one',
        () async {
      cart.add(_deal(1));
      final first = holds.grant();
      await pumpEventQueue();

      cart.add(_deal(1));
      expect(holds.requests.single.quantity, 2);
      final second = holds.grant();
      await pumpEventQueue();
      expect(line(1).reservation!.id, second);
      expect(holds.released, [first]);

      cart.decrement(1);
      expect(holds.requests.single.quantity, 1);
      holds.grant();
      await pumpEventQueue();
      expect(holds.released, [first, second]);
    });

    test('removing a line releases its hold', () async {
      cart.add(_deal(1));
      final id = holds.grant();
      await pumpEventQueue();

      cart.remove(1);
      await pumpEventQueue();
      expect(holds.released, [id]);
    });

    test('a hold that lands after the line was removed is released', () async {
      cart.add(_deal(1));
      cart.remove(1);
      final id = holds.grant();
      await pumpEventQueue();

      expect(cart.items, isEmpty);
      expect(holds.released, [id]);
    });

    test('quick taps: a late older hold is kept only as a fallback', () async {
      cart.add(_deal(1)); // asks for 1
      cart.add(_deal(1)); // asks for 2
      final one = holds.grant(); // the hold for 1 lands, superseded
      await pumpEventQueue();
      expect(line(1).reservation!.id, one); // kept as fallback
      expect(line(1).isReserving, isTrue);

      holds.refuse(); // the hold for 2 fails
      await pumpEventQueue();
      expect(line(1).quantity, 1); // back to the fallback, not removed
      expect(line(1).reservation!.id, one);
    });
  });
}
