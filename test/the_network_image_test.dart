import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/shared_widget/the_network_image.dart';

void main() {
  Future<CachedNetworkImage> pumpImage(
    WidgetTester tester, {
    required double boxWidth,
    double? width,
    double? height,
  }) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: boxWidth,
          child: TheNetworkImage(
              url: 'https://example.com/a.jpg', width: width, height: height),
        ),
      ),
    ));
    return tester.widget(find.byType(CachedNetworkImage));
  }

  testWidgets('a full-width card decodes at its drawn width', (tester) async {
    // Like DealCard: width: double.infinity, height: 160.
    final image = await pumpImage(tester,
        boxWidth: 360, width: double.infinity, height: 160);
    expect(image.memCacheWidth, 720);
    expect(image.memCacheHeight, isNull);
  });

  testWidgets('a tall box decodes by height', (tester) async {
    final image =
        await pumpImage(tester, boxWidth: 400, width: 60, height: 120);
    expect(image.memCacheWidth, isNull);
    expect(image.memCacheHeight, 240);
  });
}
