import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/search/search_deals_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/repository/deal_repo.dart';

/// Lets each test decide when (and in which order) every search resolves.
class _FakeDealRepo extends Fake implements DealRepo {
  final calls = <String, Completer<List<DealModel>>>{};

  @override
  Future<List<DealModel>> search(String query) {
    final completer = Completer<List<DealModel>>();
    calls[query] = completer;
    return completer.future;
  }
}

DealModel _deal(int id, String name) => DealModel.fromJson({
      'id': id,
      'name': name,
      'description': '',
      'imageUrl': '',
      'originalPrice': 100,
      'price': 50,
      'currencyCode': 'THB',
      'quantityLeft': 1,
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
  late SearchDealsController controller;

  setUp(() {
    Get.testMode = true;
    repo = _FakeDealRepo();
    controller = Get.put(SearchDealsController(dealRepo: repo));
  });

  tearDown(Get.reset);

  testWidgets(
      'a slow response for an older query does not replace newer results',
      (tester) async {
    // Typing with pauses longer than any debounce, so both queries are sent.
    controller.onQueryChanged('s');
    await tester.pump(const Duration(seconds: 1));
    controller.onQueryChanged('sushi');
    await tester.pump(const Duration(seconds: 1));
    expect(repo.calls.keys, ['s', 'sushi']);

    // The backend answers the longer query first, like FakeApiService does.
    repo.calls['sushi']!.complete([_deal(1, 'Sushi Box')]);
    await tester.pump();
    repo.calls['s']!.complete([_deal(1, 'Sushi Box'), _deal(2, 'Salad')]);
    await tester.pump();

    expect(controller.results.map((d) => d.name), ['Sushi Box']);
    expect(controller.isLoading.value, isFalse);
  });

  testWidgets('keeps loading until the latest query has answered',
      (tester) async {
    controller.onQueryChanged('s');
    await tester.pump(const Duration(seconds: 1));
    controller.onQueryChanged('sushi');
    await tester.pump(const Duration(seconds: 1));

    repo.calls['s']!.complete([_deal(2, 'Salad')]);
    await tester.pump();

    expect(controller.isLoading.value, isTrue);
    expect(controller.results, isEmpty);
  });

  testWidgets('clearing the box discards a search that is still in flight',
      (tester) async {
    controller.onQueryChanged('sushi');
    await tester.pump(const Duration(seconds: 1));
    controller.onQueryChanged('');
    await tester.pump(const Duration(seconds: 1));

    repo.calls['sushi']!.complete([_deal(1, 'Sushi Box')]);
    await tester.pump();

    expect(controller.results, isEmpty);
    expect(controller.hasSearched.value, isFalse);
    expect(controller.isLoading.value, isFalse);
  });

  testWidgets('fast typing sends only the final query', (tester) async {
    for (final q in ['s', 'su', 'sus', 'sush', 'sushi']) {
      controller.onQueryChanged(q);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pump(const Duration(seconds: 1));

    expect(repo.calls.keys, ['sushi']);
  });
}
