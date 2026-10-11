import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/home/home_controller.dart';
import 'package:rescu/model/deal_model.dart';
import 'package:rescu/model/paged_response_model.dart';
import 'package:rescu/repository/deal_repo.dart';

const _pageSize = 20;
const _totalPages = 5;

/// Hands out one pending request per `fetchDeals` call, so each test decides
/// when (and in which order) every page resolves.
class _FakeDealRepo extends Fake implements DealRepo {
  final requests = <({int page, Completer<PagedResponseModel<DealModel>> c})>[];

  @override
  Future<PagedResponseModel<DealModel>> fetchDeals({int page = 1}) {
    final c = Completer<PagedResponseModel<DealModel>>();
    requests.add((page: page, c: c));
    return c.future;
  }

  /// Resolves the oldest pending request for [page] with that page's items.
  void respond(int page) => _take(page).complete(PagedResponseModel(
        items: [
          for (var i = 0; i < _pageSize; i++)
            _deal((page - 1) * _pageSize + i + 1)
        ],
        page: page,
        totalPages: _totalPages,
      ));

  void fail(int page) => _take(page).completeError(Exception('500'));

  Completer<PagedResponseModel<DealModel>> _take(int page) {
    final i = requests.indexWhere((r) => r.page == page);
    return requests.removeAt(i).c;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDealRepo repo;
  late HomeController controller;

  List<int> ids() => controller.deals.map((d) => d.id).toList();

  /// Loads pages 1..[pages] the normal way.
  Future<void> loadPages(int pages) async {
    final refresh = controller.refreshDeals();
    repo.respond(1);
    await refresh;
    for (var p = 2; p <= pages; p++) {
      final more = controller.loadMore();
      repo.respond(p);
      await more;
    }
  }

  setUp(() {
    repo = _FakeDealRepo();
    // Constructed directly so onInit's initial load does not run.
    controller = HomeController(dealRepo: repo);
  });

  test('refresh during load-more: the late page is dropped', () async {
    await loadPages(2);

    final more = controller.loadMore(); // page 3 in flight
    final refresh = controller.refreshDeals(); // pull to refresh
    repo.respond(1);
    await refresh;
    repo.respond(3); // arrives after the refresh
    await more;

    expect(ids(), [for (var i = 1; i <= 20; i++) i]);

    // Scrolling on continues from page 2 with no duplicates.
    final next = controller.loadMore();
    expect(repo.requests.single.page, 2);
    repo.respond(2);
    await next;
    expect(ids(), [for (var i = 1; i <= 40; i++) i]);
  });

  test('refresh during load-more: the page that lands first is discarded',
      () async {
    await loadPages(2);

    final more = controller.loadMore();
    final refresh = controller.refreshDeals();
    repo.respond(3); // old page lands before the refresh
    await more;
    repo.respond(1);
    await refresh;

    expect(ids(), [for (var i = 1; i <= 20; i++) i]);
  });

  test('load-more started while a refresh is in flight is dropped', () async {
    await loadPages(2);

    final refresh = controller.refreshDeals();
    final more = controller.loadMore(); // page 3 of the old list
    repo.respond(1);
    await refresh;
    repo.respond(3);
    await more;

    expect(ids(), [for (var i = 1; i <= 20; i++) i]);
  });

  test('a failed refresh keeps the feed and its paging position', () async {
    await loadPages(3);

    final refresh = controller.refreshDeals();
    repo.fail(1);
    await refresh;

    expect(ids(), [for (var i = 1; i <= 60; i++) i]);
    final more = controller.loadMore();
    expect(repo.requests.single.page, 4);
    repo.respond(4);
    await more;
    expect(ids().toSet().length, ids().length);
  });

  test('never holds more deals than the catalog', () async {
    await loadPages(2);
    for (var round = 0; round < 3; round++) {
      final more = controller.loadMore();
      final refresh = controller.refreshDeals();
      repo.respond(1);
      await refresh;
      repo.respond(repo.requests.single.page);
      await more;
    }
    while (controller.hasMore) {
      final more = controller.loadMore();
      repo.respond(repo.requests.single.page);
      await more;
    }

    expect(ids(), [for (var i = 1; i <= _pageSize * _totalPages; i++) i]);
  });
}
