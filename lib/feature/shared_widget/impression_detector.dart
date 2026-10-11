import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../service/impression_tracker.dart';

/// Reports a `deal_impression` once [child] has been at least half visible
/// for one continuous second.
///
/// Never rebuilds on scroll: visibility arrives through [VisibilityDetector]
/// callbacks, which only start or cancel a timer. Callbacks for a deal that
/// was already seen this session return immediately.
class ImpressionDetector extends StatefulWidget {
  final int dealId;
  final String source;
  final int position;
  final Widget child;

  const ImpressionDetector({
    super.key,
    required this.dealId,
    required this.source,
    required this.position,
    required this.child,
  });

  static const minVisibleFraction = 0.5;
  static const minVisibleDuration = Duration(seconds: 1);

  @override
  State<ImpressionDetector> createState() => _ImpressionDetectorState();
}

class _ImpressionDetectorState extends State<ImpressionDetector> {
  final _tracker = Get.find<ImpressionTracker>();
  Timer? _dwellTimer;

  void _onVisibilityChanged(VisibilityInfo info) {
    if (_tracker.hasSeen(widget.dealId)) return;
    if (info.visibleFraction >= ImpressionDetector.minVisibleFraction) {
      _dwellTimer ??= Timer(ImpressionDetector.minVisibleDuration, () {
        _tracker.recordImpression(
          dealId: widget.dealId,
          source: widget.source,
          position: widget.position,
        );
      });
    } else {
      // Dropping below half resets the "continuous" second.
      _dwellTimer?.cancel();
      _dwellTimer = null;
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('impression-${widget.source}-${widget.dealId}'),
      onVisibilityChanged: _onVisibilityChanged,
      child: widget.child,
    );
  }
}
