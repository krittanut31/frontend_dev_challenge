import 'package:get/get.dart';

import '../../model/deal_model.dart';
import '../../repository/deal_repo.dart';
import '../../service/analytics_service.dart';
import '../../service/cart_service.dart';
import '../../util/log_service.dart';

class DealDetailsController extends GetxController {
  final DealRepo dealRepo;
  final CartService cartService;
  final AnalyticsService analytics;

  DealDetailsController({
    required this.dealRepo,
    required this.cartService,
    required this.analytics,
  });

  /// The route (`/deal?id=42`) is the source of truth for which deal to show.
  /// In-app taps also pass the [DealModel] as `Get.arguments` so the page can
  /// render immediately; deep links only carry the id, so the deal is fetched.
  late final int? dealId;

  final deal = Rxn<DealModel>();
  final loadFailed = false.obs;

  final _quantityLeft = RxnInt();
  int? get quantityLeft => _quantityLeft.value;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    final idFromRoute = int.tryParse(Get.parameters['id'] ?? '');
    if (args is DealModel && (idFromRoute == null || args.id == idFromRoute)) {
      dealId = args.id;
      _show(args);
    } else {
      dealId = idFromRoute;
      loadDeal();
    }
    analytics.logEvent('deal_details_view', {
      'deal_id': dealId,
      'source': Get.parameters['source'] ?? 'unknown',
    });
    // Whenever the cart changes, re-check this deal's remaining stock so the
    // details screen never shows stale availability.
    ever(cartService.itemCount, (_) => _recheckAvailability());
  }

  Future<void> loadDeal() async {
    final id = dealId;
    if (id == null) {
      LogService.error('deal route without a valid id', Get.parameters);
      loadFailed.value = true;
      return;
    }
    loadFailed.value = false;
    try {
      _show(await dealRepo.fetchById(id));
    } catch (e) {
      LogService.error('load deal $id failed', e);
      loadFailed.value = true;
    }
  }

  void _show(DealModel loaded) {
    deal.value = loaded;
    _quantityLeft.value = loaded.quantityLeft;
  }

  Future<void> _recheckAvailability() async {
    final id = dealId;
    if (id == null) return;
    LogService.log('re-checking availability for deal $id');
    final fresh = await dealRepo.fetchById(id);
    _quantityLeft.value = fresh.quantityLeft;
  }

  void addToCart() {
    final current = deal.value;
    if (current == null) return;
    cartService.add(current);
    Get.snackbar(
      'Added to bag',
      '${current.name} — pick up ${current.pickupWindow.label}',
      snackPosition: SnackPosition.BOTTOM,
      duration: const Duration(seconds: 2),
    );
  }
}
