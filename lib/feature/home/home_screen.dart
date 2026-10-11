import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';

import '../../app_config.dart';
import '../../routes/routes.dart';
import '../shared_widget/deal_card.dart';
import '../shared_widget/shimmer_deal_card.dart';
import 'home_controller.dart';
import 'widget/flash_deals_section.dart';

class HomeScreen extends GetView<HomeController> {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // No Obx around the Scaffold: each reactive part below observes only what
    // it shows, so scrolling does not rebuild the app bar, list and cards.
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Obx(() => _buildAppBar(context, controller.isScrolled.value)),
      ),
      body: Obx(_buildBody),
      floatingActionButton: Obx(() => controller.showScrollToTop.value
          ? FloatingActionButton.small(
              onPressed: controller.scrollToTop,
              child: const Icon(Icons.arrow_upward),
            )
          : const SizedBox.shrink()),
    );
  }

  AppBar _buildAppBar(BuildContext context, bool isScrolled) {
    return AppBar(
      elevation: isScrolled ? 2 : 0,
      shadowColor: Colors.black26,
      title: const Row(
        children: [
          Icon(Icons.eco, color: AppConfig.primaryGreen),
          SizedBox(width: 8),
          Text('Rescu',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => Get.toNamed(Routes.search),
        ),
        IconButton(
          icon: const Icon(Icons.map_outlined),
          onPressed: () => Get.toNamed(Routes.map),
        ),
        IconButton(
          icon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => Get.toNamed(Routes.orders),
        ),
        IconButton(
          icon: const Icon(Icons.shopping_bag_outlined),
          onPressed: () => Get.toNamed(Routes.cart),
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'deeplink') _showDeepLinkDialog(context);
            if (value == 'analytics') Get.toNamed(Routes.analyticsDebug);
          },
          itemBuilder: (context) => const [
            PopupMenuItem(
                value: 'deeplink', child: Text('Simulate deep link…')),
            PopupMenuItem(value: 'analytics', child: Text('Analytics debug')),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (controller.isLoading.value) {
      return ListView(
        children: const [
          ShimmerDealCard(),
          ShimmerDealCard(),
          ShimmerDealCard(),
        ],
      );
    }
    final deals = controller.visibleDeals;
    final hasFlash = controller.flashDeals.isNotEmpty;
    // Fixed rows before the deals: optional flash rail, then the header.
    final leading = hasFlash ? 2 : 1;
    return SmartRefresher(
      controller: controller.refreshController,
      enablePullDown: true,
      enablePullUp: true,
      onRefresh: controller.refreshDeals,
      onLoading: controller.loadMore,
      // Lazy: only cards on screen (plus cache extent) are built, and
      // cards scrolled far away are disposed with their images.
      child: ListView.builder(
        controller: controller.scrollController,
        itemCount: leading + deals.length + 1,
        itemBuilder: (context, index) {
          if (hasFlash && index == 0) {
            return FlashDealsSection(deals: controller.flashDeals);
          }
          if (index == leading - 1) return _buildHeader();
          if (index == leading + deals.length) {
            return const SizedBox(height: 24);
          }
          final deal = deals[index - leading];
          return DealCard(key: ValueKey(deal.id), deal: deal);
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          const Text('Nearby deals',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Spacer(),
          Obx(() => FilterChip(
                label: const Text('Pickup today'),
                selected: controller.todayOnly.value,
                onSelected: (v) => controller.todayOnly.value = v,
              )),
        ],
      ),
    );
  }

  void _showDeepLinkDialog(BuildContext context) {
    final textController =
        TextEditingController(text: 'rescu://open/deal?id=42&source=push');
    Get.dialog(
      AlertDialog(
        title: const Text('Simulate deep link'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            helperText: 'e.g. rescu://open/deal?id=42&source=push',
          ),
        ),
        actions: [
          TextButton(onPressed: Get.back, child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              final uri = Uri.tryParse(textController.text.trim());
              Get.back();
              if (uri == null) return;
              final route =
                  uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
              Get.toNamed(route);
            },
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}
