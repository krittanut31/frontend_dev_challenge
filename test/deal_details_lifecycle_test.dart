import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/routes/routes.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/fake_api_service.dart';

/// Records which deals the details page re-fetches.
class _FakeDealRepo extends DealRepo {
  _FakeDealRepo() : super(api: FakeApiService());

  final fetched = <int>[];

  @override
  Future<DealModel> fetchById(int id) async {
    fetched.add(id);
    return _deal(id);
  }
}

DealModel _deal(int id) => DealModel.fromJson({
      'id': id,
      'name': 'Deal $id',
      'description': '',
      'imageUrl': '',
      'originalPrice': 100,
      'price': 50,
      'currencyCode': 'THB',
      'quantityLeft': 3,
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
  late _FakeDealRepo repo;
  late CartService cart;

  setUp(() {
    Get.testMode = true;
    repo = _FakeDealRepo();
    Get.put(AnalyticsService());
    cart = Get.put(CartService());
    Get.put<DealRepo>(repo);
  });

  tearDown(Get.reset);

  Future<void> openAndClose(WidgetTester tester, int id) async {
    Get.toNamed(Routes.dealRoute(id, source: 'home_feed'),
        arguments: _deal(id));
    await tester.pump(const Duration(seconds: 1));
    Get.back();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('closed deal pages stop reacting to cart changes',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: Routes.home,
      getPages: [
        GetPage(name: Routes.home, page: () => const SizedBox()),
        ...Routes.pages.where((p) => p.name == Routes.deal),
      ],
    ));

    await openAndClose(tester, 1);
    await openAndClose(tester, 2);
    await openAndClose(tester, 3);

    cart.add(_deal(9));
    await tester.pump(const Duration(seconds: 1));

    expect(repo.fetched, isEmpty);
  });

  testWidgets('the open deal page still re-checks its own stock',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: Routes.home,
      getPages: [
        GetPage(name: Routes.home, page: () => const SizedBox()),
        ...Routes.pages.where((p) => p.name == Routes.deal),
      ],
    ));
    await openAndClose(tester, 1);

    Get.toNamed(Routes.dealRoute(2, source: 'home_feed'),
        arguments: _deal(2));
    await tester.pump(const Duration(seconds: 1));
    cart.add(_deal(2));
    await tester.pump(const Duration(seconds: 1));

    expect(repo.fetched, [2]);
  });
}
