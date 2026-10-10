import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rescu/feature/order/widget/pickup_countdown.dart';

void main() {
  testWidgets('stops ticking once removed from the tree', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PickupCountdown(
          pickupStart: DateTime.now().add(const Duration(minutes: 30)),
        ),
      ),
    ));
    expect(find.textContaining('Opens in'), findsOneWidget);

    // Leave the screen, like navigating back from My orders.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });
}
