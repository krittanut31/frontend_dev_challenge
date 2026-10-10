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

  final _query = ''.obs;

  /// Incremented for every search started. A response is applied only if no
  /// newer search has started since, because responses can arrive out of
  /// order (shorter queries take longer on the backend).
  int _latestSearchId = 0;

  @override
  void onInit() {
    super.onInit();
    // Worker is disposed together with the controller.
    debounce(_query, _search, time: _debounceDuration);
  }

  void onQueryChanged(String query) {
    _query.value = query;
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
