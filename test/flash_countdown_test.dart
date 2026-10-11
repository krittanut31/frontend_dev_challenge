import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/deal_card.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/routes/routes.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/fake_api_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/clock_service.dart';
import 'package:rescu/service/flash_sale_expiry_service.dart';
import 'package:rescu/util/countdown_format.dart';

DealModel _flashDeal(int id, DateTime endsAt) => DealModel.fromJson({
      'id': id,
      'name': 'Flash deal $id',
      'description': '',
      'imageUrl': '',
      'originalPrice': 100,
      'price': 50,
      'currencyCode': 'THB',
      'quantityLeft': 5,
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
      'flashSaleEndsAt': endsAt.toUtc().toIso8601String(),
    });

void main() {
  group('formatCountdown', () {
    test('mm:ss under an hour', () {
      expect(formatCountdown(const Duration(minutes: 9, seconds: 5)), '09:05');
    });
    test('hh:mm:ss from one hour', () {
      expect(formatCountdown(const Duration(hours: 1, seconds: 1)), '01:00:01');
    });
    test('rounds partial seconds up, so 00:00 means the time is up', () {
      expect(formatCountdown(const Duration(milliseconds: 400)), '00:01');
      expect(
          formatCountdown(
              const Duration(minutes: 59, seconds: 59, milliseconds: 1)),
          '01:00:00');
      expect(formatCountdown(Duration.zero), '00:00');
      expect(formatCountdown(const Duration(seconds: -3)), '00:00');
    });
  });

  group('live countdown', () {
    final start = DateTime(2026, 1, 2, 12);
    late DateTime fakeNow;
    late ClockService clock;
    late CartService cart;

    setUp(() {
      Get.testMode = true;
      fakeNow = start;
      clock = Get.put(ClockService(clock: () => fakeNow));
      cart = Get.put(CartService(clock: () => fakeNow));
      Get.put(FlashSaleExpiryService(clock: clock, cart: cart));
    });

    tearDown(() async {
      debugOnRebuildDirtyWidget = null;
      await Get.delete<FlashSaleExpiryService>(force: true);
      await Get.delete<ClockService>(force: true);
      Get.reset();
    });

    /// Moves the fake clock and the test's timers forward together.
    Future<void> advance(WidgetTester tester, Duration by) async {
      fakeNow = fakeNow.add(by);
      clock.tick();
      await tester.pump(by);
    }

    testWidgets('each tick rebuilds only the countdown texts, not the cards',
        (tester) async {
      final deals = [
        for (var i = 0; i < 120; i++)
          _flashDeal(i, start.add(Duration(minutes: 10 + i)))
      ];
      await tester.pumpWidget(GetMaterialApp(
        home: Scaffold(
          body: ListView.builder(
            itemCount: deals.length,
            itemBuilder: (_, i) => DealCard(deal: deals[i]),
          ),
        ),
      ));
      final visibleCards = find.byType(DealCard).evaluate().length;
      expect(find.text('10:00'), findsOneWidget);

      // Let start-up work (route focus) settle before counting.
      await tester.pump();

      final rebuilt = <String, int>{};
      debugOnRebuildDirtyWidget = (element, _) {
        final type = element.widget.runtimeType.toString();
        rebuilt[type] = (rebuilt[type] ?? 0) + 1;
      };
      for (var s = 0; s < 5; s++) {
        await advance(tester, const Duration(seconds: 1));
      }

      expect(find.text('09:55'), findsOneWidget);
      // One Obx and its Text per visible countdown per tick...
      expect(rebuilt['Obx'], visibleCards * 5);
      expect(rebuilt['Text'], visibleCards * 5);
      // ...and nothing that makes up a card or the list. (The only other
      // rebuilds are the image placeholders' shimmer, which animates every
      // frame regardless of the countdown.)
      for (final type in [
        'DealCard',
        'FlashExpiryBuilder',
        '_FlashBadge',
        'Card',
        'InkWell',
        'Column',
        'Stack',
        'ListView'
      ]) {
        expect(rebuilt[type], isNull, reason: type);
      }
      expect(
          rebuilt.keys.toSet().difference({'Obx', 'Text', 'AnimatedBuilder'}),
          isEmpty);
    });

    testWidgets('at zero the card turns Expired and cannot be opened',
        (tester) async {
      final deal = _flashDeal(1, start.add(const Duration(seconds: 3)));
      await tester.pumpWidget(GetMaterialApp(
        home: Scaffold(body: DealCard(deal: deal)),
      ));
      expect(find.textContaining('FLASH SALE'), findsOneWidget);

      await advance(tester, const Duration(seconds: 3));

      expect(find.text('EXPIRED'), findsOneWidget);
      expect(find.textContaining('FLASH SALE'), findsNothing);
      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.onTap, isNull);
    });

    testWidgets('an ended deal is removed from the bag with a notice',
        (tester) async {
      await tester.pumpWidget(const GetMaterialApp(home: SizedBox()));
      final ending = _flashDeal(1, start.add(const Duration(seconds: 2)));
      final later = _flashDeal(2, start.add(const Duration(hours: 1)));
      expect(cart.add(ending), isTrue);
      expect(cart.add(later), isTrue);

      await advance(tester, const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 500));

      expect(cart.items.map((i) => i.deal.id), [2]);
      expect(find.text('Removed from your bag'), findsOneWidget);
      expect(find.textContaining('Flash deal 1'), findsOneWidget);

      // And it cannot be added back.
      expect(cart.add(ending), isFalse);
      expect(cart.items.map((i) => i.deal.id), [2]);
      // Let the snackbar run its course before the test ends.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });

    testWidgets('the details page shows the countdown, then disables Add',
        (tester) async {
      Get.put(AnalyticsService());
      Get.put<DealRepo>(DealRepo(api: FakeApiService()));
      final deal = _flashDeal(1, start.add(const Duration(minutes: 1)));
      await tester.pumpWidget(GetMaterialApp(
        initialRoute: Routes.home,
        getPages: [
          GetPage(name: Routes.home, page: () => const SizedBox()),
          ...Routes.pages.where((p) => p.name == Routes.deal),
        ],
      ));
      Get.toNamed(Routes.dealRoute(1), arguments: deal);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('01:00'), findsOneWidget);
      expect(find.text('Add to bag'), findsOneWidget);

      await advance(tester, const Duration(minutes: 1));

      expect(
          find.text('Flash sale ended'), findsNWidgets(2)); // banner + button
      final button = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Flash sale ended').last,
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
      expect(button.onPressed, isNull);
    });
  });
}
