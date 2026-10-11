import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../util/log_service.dart';
import 'analytics_service.dart';

/// Records `deal_impression` events and delivers them to the backend in
/// batches.
///
/// - At most one impression per deal per app session, across all screens.
/// - A batch is sent when [batchSize] events are waiting, or [maxWait] after
///   the first unsent event, whichever comes first.
/// - Pending events are also flushed when the app goes to the background, so
///   they are not lost if the OS kills it there.
class ImpressionTracker extends GetxService with WidgetsBindingObserver {
  ImpressionTracker({
    required this.analytics,
    required this.sendBatch,
    this.batchSize = 10,
    this.maxWait = const Duration(seconds: 15),
  });

  final AnalyticsService analytics;

  /// Delivers one batch, e.g. `FakeApiService.sendAnalyticsBatch`.
  final Future<void> Function(List<Map<String, dynamic>> events) sendBatch;
  final int batchSize;
  final Duration maxWait;

  final _seenDealIds = <int>{};
  final _pending = <Map<String, dynamic>>[];
  Timer? _maxWaitTimer;
  bool _sending = false;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    // The package reports visibility every 500 ms by default, which is too
    // coarse for a 1-second rule: a card could be counted although it left
    // the screen up to half a second before the timer fired. 200 ms bounds
    // that error while keeping callbacks batched.
    VisibilityDetectorController.instance.updateInterval =
        const Duration(milliseconds: 200);
  }

  /// Whether [dealId] already produced an impression this session.
  bool hasSeen(int dealId) => _seenDealIds.contains(dealId);

  /// Called once a card has been at least half visible for a full second.
  void recordImpression({
    required int dealId,
    required String source,
    required int position,
  }) {
    if (!_seenDealIds.add(dealId)) return;
    final event = analytics.logEvent('deal_impression', {
      'deal_id': dealId,
      'source': source,
      'position': position,
    });
    _pending.add(event.toJson());
    if (_pending.length >= batchSize) {
      flush();
    } else {
      _maxWaitTimer ??= Timer(maxWait, flush);
    }
  }

  /// Sends everything pending now. On failure the events go back to the
  /// front of the queue and the wait timer restarts.
  Future<void> flush() async {
    _maxWaitTimer?.cancel();
    _maxWaitTimer = null;
    if (_pending.isEmpty || _sending) return;
    final batch = List.of(_pending);
    _pending.clear();
    _sending = true;
    try {
      await sendBatch(batch);
    } catch (e) {
      LogService.error('analytics batch failed, will retry', e);
      _pending.insertAll(0, batch);
      _maxWaitTimer ??= Timer(maxWait, flush);
    } finally {
      _sending = false;
    }
    // Events that arrived while sending may already fill a batch.
    if (_pending.length >= batchSize) flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) flush();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _maxWaitTimer?.cancel();
    super.onClose();
  }
}
