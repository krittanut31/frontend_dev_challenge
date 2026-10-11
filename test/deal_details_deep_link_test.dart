import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';
import 'package:rescu/routes/routes.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/cart_service.dart';
import 'package:rescu/service/fake_api_service.dart';

/// Extends the real repo (a GetxService, so `Get.put` can run its lifecycle)
/// and only replaces the call the details page makes.
class _FakeDealRepo extends DealRepo {
  _FakeDealRepo() : super(api: FakeApiService());

  final requested = <int>[];
  late Completer<DealModel> pending;

  @override
  Future<DealModel> fetchById(int id) {
    requested.add(id);
    return pending.future;
  }
}

DealModel _deal(int id, String name) => DealModel.fromJson({
      'id': id,
      'name': name,
      'description': 'Assorted rolls',
      'imageUrl': '',
      'originalPrice': 300,
      'price': 120,
      'currencyCode': 'THB',
      'quantityLeft': 4,
      'storeId': 1,
      'storeName': 'Chao Phraya Sushi',
      'storeAddress': '1 Charoen Krung Rd',
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
  late AnalyticsService analytics;

  setUp(() {
    Get.testMode = true;
    repo = _FakeDealRepo();
    analytics = Get.put(AnalyticsService());
    Get.put(CartService());
    Get.put<DealRepo>(repo);
  });

  tearDown(Get.reset);

  Future<void> pumpApp(WidgetTester tester) async {
    // Created inside the test body so it completes in the test's fake-async
    // zone; one created in setUp would never be flushed by tester.pump().
    repo.pending = Completer();
    await tester.pumpWidget(GetMaterialApp(
      initialRoute: Routes.home,
      getPages: [
        GetPage(name: Routes.home, page: () => const SizedBox()),
        ...Routes.pages.where((p) => p.name == Routes.deal),
      ],
    ));
  }

  testWidgets('a deep link with only an id loads and shows the deal',
      (tester) async {
    await pumpApp(tester);

    // What the deep link handler navigates to: no arguments, id in the URL.
    Get.toNamed('/deal?id=42&source=push');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repo.requested, [42]);

    repo.pending.complete(_deal(42, 'Surprise Sushi Box'));
    await tester.pump();

    expect(find.text('Surprise Sushi Box'), findsOneWidget);
    expect(find.text('Add to bag'), findsOneWidget);
    expect(analytics.events.last.properties,
        {'deal_id': 42, 'source': 'push'});
  });

  testWidgets('a failed load offers a retry that recovers', (tester) async {
    await pumpApp(tester);
    Get.toNamed('/deal?id=42&source=push');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    repo.pending.completeError(Exception('500'));
    await tester.pump();
    expect(find.text('Try again'), findsOneWidget);

    repo.pending = Completer();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    repo.pending.complete(_deal(42, 'Surprise Sushi Box'));
    await tester.pump();

    expect(find.text('Surprise Sushi Box'), findsOneWidget);
  });

  testWidgets('an in-app tap with the deal as argument renders at once',
      (tester) async {
    await pumpApp(tester);
    Get.toNamed(Routes.dealRoute(42, source: 'home_feed'),
        arguments: _deal(42, 'Surprise Sushi Box'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Surprise Sushi Box'), findsOneWidget);
    expect(repo.requested, isEmpty);
  });
}
