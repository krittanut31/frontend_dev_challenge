import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:rescu/feature/shared_widget/impression_detector.dart';
import 'package:rescu/service/analytics_service.dart';
import 'package:rescu/service/impression_tracker.dart';
import 'package:visibility_detector/visibility_detector.dart';

void main() {
  late AnalyticsService analytics;
  late ImpressionTracker tracker;
  late List<List<Map<String, dynamic>>> batches;

  setUp(() {
    Get.testMode = true;
    batches = [];
    analytics = Get.put(AnalyticsService());
    tracker = Get.put(ImpressionTracker(
      analytics: analytics,
      sendBatch: (events) async => batches.add(events),
    ));
    // Report visibility synchronously, as the package recommends in tests.
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  tearDown(() async {
    await Get.delete<ImpressionTracker>(force: true);
    Get.reset();
  });

  List<int> batchedIds(int i) =>
      batches[i].map((e) => e['properties']['deal_id'] as int).toList();

  group('batching and de-duplication', () {
    testWidgets('sends a batch as soon as 10 events are waiting',
        (tester) async {
      for (var id = 1; id <= 9; id++) {
        tracker.recordImpression(dealId: id, source: 'home_feed', position: id);
      }
      await tester.pump();
      expect(batches, isEmpty);

      tracker.recordImpression(dealId: 10, source: 'home_feed', position: 10);
      await tester.pump();

      expect(batches.length, 1);
      expect(batchedIds(0), [for (var i = 1; i <= 10; i++) i]);
      expect(batches[0].first['name'], 'deal_impression');
      expect(batches[0].first['properties'],
          {'deal_id': 1, 'source': 'home_feed', 'position': 1});
    });

    testWidgets('sends what is waiting 15 s after the first unsent event',
        (tester) async {
      tracker.recordImpression(dealId: 1, source: 'search', position: 0);
      await tester.pump(const Duration(seconds: 10));
      tracker.recordImpression(dealId: 2, source: 'search', position: 1);
      await tester.pump(const Duration(seconds: 4));
      expect(batches, isEmpty);

      await tester.pump(const Duration(seconds: 1)); // 15 s after the first
      expect(batches.length, 1);
      expect(batchedIds(0), [1, 2]);

      // The next event starts a fresh 15 s window.
      tracker.recordImpression(dealId: 3, source: 'search', position: 2);
      await tester.pump(const Duration(seconds: 14));
      expect(batches.length, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(batchedIds(1), [3]);
    });

    testWidgets('logs each deal at most once per session, across sources',
        (tester) async {
      tracker.recordImpression(dealId: 7, source: 'flash_rail', position: 0);
      tracker.recordImpression(dealId: 7, source: 'home_feed', position: 3);
      tracker.recordImpression(dealId: 7, source: 'search', position: 0);
      await tester.pump(const Duration(seconds: 15));

      expect(batches.single.length, 1);
      expect(batches.single.single['properties']['source'], 'flash_rail');
      expect(
          analytics.events.where((e) => e.name == 'deal_impression').length, 1);
    });

    testWidgets('a failed batch is kept and retried', (tester) async {
      await Get.delete<ImpressionTracker>(force: true);
      var failNext = true;
      tracker = Get.put(ImpressionTracker(
        analytics: analytics,
        sendBatch: (events) async {
          if (failNext) {
            failNext = false;
            throw Exception('503');
          }
          batches.add(events);
        },
      ));
      tracker.recordImpression(dealId: 1, source: 'search', position: 0);
      await tester.pump(const Duration(seconds: 15)); // fails
      expect(batches, isEmpty);

      await tester.pump(const Duration(seconds: 15)); // retried
      expect(batchedIds(0), [1]);
    });
  });

  group('visibility rule', () {
    /// A tall list where card [i] is 300 px high; the test view is 600 px.
    Future<void> pumpList(WidgetTester tester, ScrollController scroll) =>
        tester.pumpWidget(MaterialApp(
          home: ListView.builder(
            controller: scroll,
            itemCount: 20,
            itemBuilder: (_, i) => ImpressionDetector(
              dealId: 100 + i,
              source: 'home_feed',
              position: i,
              child: const SizedBox(height: 300),
            ),
          ),
        ));

    List<int> impressions() => analytics.events
        .where((e) => e.name == 'deal_impression')
        .map((e) => e.properties['deal_id'] as int)
        .toList();

    testWidgets('counts cards visible for a full second', (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      await pumpList(tester, scroll);

      await tester.pump(const Duration(milliseconds: 900));
      expect(impressions(), isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(impressions(), [100, 101]);
      await tracker.flush(); // the pending batch
    });

    testWidgets('a card scrolled away before 1 s is not counted',
        (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      await pumpList(tester, scroll);

      await tester.pump(const Duration(milliseconds: 500));
      scroll.jumpTo(3000); // cards 10 and 11 now
      await tester.pump(); // the frame that applies the scroll
      await tester.pump(const Duration(milliseconds: 800));
      expect(impressions(), isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      expect(impressions(), [110, 111]);
      await tracker.flush(); // the pending batch
    });

    testWidgets('under half visible is not counted', (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final scroll = ScrollController();
      await pumpList(tester, scroll);

      // Before card 0's second is up, scroll 180 px: card 0 drops to 40%
      // (120 of 300 px), card 1 stays full, card 2 comes in at 60%.
      await tester.pump(const Duration(milliseconds: 500));
      scroll.jumpTo(180);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));

      expect(impressions(), [101, 102]);
      await tracker.flush(); // the pending batch
    });
  });
}
