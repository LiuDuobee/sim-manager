import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sim_manager/main.dart';
import 'package:sim_manager/pages/home_page.dart';

/// Frame-timing check for the touch animations: globe drag + fling, card
/// flip springs, card stack pull-out, check-in stamp. Run in profile mode:
///   flutter drive --profile --driver=test_driver/perf_driver.dart \
///     --target=integration_test/perf_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('touch animations frame timing', (tester) async {
    await tester.pumpWidget(const SimVaultApp(home: HomePage()));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await binding.watchPerformance(() async {
      // Globe: drag and let it glide.
      final globe = find.byKey(const Key('atlas-globe'));
      for (var i = 0; i < 3; i++) {
        await tester.timedDrag(
            globe, const Offset(-220, 40), const Duration(milliseconds: 250));
        for (var f = 0; f < 60; f++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      // Cards: flip springs.
      final flip = find.byKey(const Key('flip-sim-cn-cmcc'));
      // The home page is a lazy list: scroll until the card is built.
      final pos =
          tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      for (var i = 0; i < 20 && flip.evaluate().isEmpty; i++) {
        pos.jumpTo(pos.pixels + 400);
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(flip);
      for (var f = 0; f < 20; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      for (var i = 0; i < 3; i++) {
        await tester.tap(flip, warnIfMissed: false);
        for (var f = 0; f < 50; f++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.tap(find.byKey(const Key('unflip-sim-cn-cmcc')),
            warnIfMissed: false);
        for (var f = 0; f < 50; f++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      // Check-in stamp.
      final checkIn = find.byKey(const Key('checkin-sim-cn-cmcc'));
      if (checkIn.evaluate().isNotEmpty) {
        await tester.tap(checkIn, warnIfMissed: false);
        for (var f = 0; f < 100; f++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      // Scroll the page.
      final scroll = find.byType(Scrollable).first;
      await tester.fling(scroll, const Offset(0, -800), 2000);
      for (var f = 0; f < 90; f++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }, reportKey: 'touch_animations');
  });
}
