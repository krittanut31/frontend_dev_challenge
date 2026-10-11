import 'dart:async';

import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../util/log_service.dart';

class SearchDealsController extends GetxController {
  final DealRepo dealRepo;

  SearchDealsController({required this.dealRepo});

  static const _debounceDuration = Duration(milliseconds: 300);

  final results = <DealModel>[].obs;
  final isLoading = false.obs;
  final hasSearched = false.obs;

  /// Own timer rather than GetX's `debounce` worker: disposing that worker
  /// does not cancel a pending call, so a search could still fire after
  /// the screen is closed.
  Timer? _debounceTimer;

  /// Incremented for every search started. A response is applied only if no
  /// newer search has started since, because responses can arrive out of
  /// order (shorter queries take longer on the backend).
  int _latestSearchId = 0;

  void onQueryChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () => _search(query));
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    super.onClose();
  }

  Future<void> _search(String query) async {
    final searchId = ++_latestSearchId;
    if (query.trim().isEmpty) {
      results.clear();
      hasSearched.value = false;
      isLoading.value = false;
      return;
    }
    isLoading.value = true;
    hasSearched.value = true;
    try {
      final found = await dealRepo.search(query);
      if (searchId != _latestSearchId) return;
      results.assignAll(found);
    } catch (e) {
      if (searchId != _latestSearchId) return;
      LogService.error('search failed', e);
    }
    isLoading.value = false;
  }
}
