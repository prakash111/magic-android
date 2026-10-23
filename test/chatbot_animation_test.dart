import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/theme/app_colors.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/animated_chatbot_button.dart';
import 'package:magicai_mobile/widgets/magic_bottom_navigation.dart';

import 'android_ui_probe.dart' show probeNavigation;

Finder get aura => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is ChatbotAuraPainter,
);
Finder get robot => find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is ChatbotRobotPainter,
);
ChatbotAuraPainter auraPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(aura).painter! as ChatbotAuraPainter;
ChatbotRobotPainter robotPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(robot).painter! as ChatbotRobotPainter;

Widget navigation({
  bool enabled = true,
  bool reduced = false,
  bool light = false,
  int selected = 1,
  ValueChanged<int>? onSelected,
}) => MaterialApp(
  theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
    child: child!,
  ),
  home: TickerMode(
    enabled: enabled,
    child: Scaffold(
      bottomNavigationBar: MagicBottomNavigation(
        items: probeNavigation,
        selectedIndex: selected,
        onSelected: onSelected ?? (_) {},
      ),
    ),
  ),
);

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
            .platformDispatcher
            .accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
  });

  for (final light in [false, true]) {
    testWidgets(
      'orb animates in ${light ? 'light' : 'dark'} mode and keeps the existing touch geometry',
      (tester) async {
        final selected = <int>[];
        await tester.pumpWidget(
          navigation(light: light, onSelected: selected.add),
        );
        await tester.pump();
        final circle = tester.getRect(
          find.byKey(const ValueKey('chatbot-floating-action')),
        );
        expect(circle.size, const Size(72, 72));
        expect(auraPainter(tester).motion, isTrue);
        final initial = robotPainter(tester).seconds;
        await tester.pump(const Duration(milliseconds: 600));
        expect(robotPainter(tester).seconds, greaterThan(initial));
        expect(auraPainter(tester).seconds, greaterThan(initial));
        expect(
          auraPainter(tester).colors,
          light ? AppColors.light : AppColors.dark,
        );
        expect(
          tester.getRect(find.byKey(const ValueKey('chatbot-floating-action'))),
          circle,
        );
        final tap = await tester.startGesture(
          Offset(circle.center.dx, circle.top + 12),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tap.up();
        await tester.pump();
        expect(selected, [2]);
        expect(auraPainter(tester).burst, lessThan(1));
        await tester.pump(const Duration(milliseconds: 710));
        expect(auraPainter(tester).burst, 1);
        expect(find.text('Chatbot'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        expect(tester.binding.transientCallbackCount, 0);
      },
    );
  }

  testWidgets(
    'selected Chatbot uses the stronger waves without restarting the animation',
    (tester) async {
      await tester.pumpWidget(navigation());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      final before = auraPainter(tester).seconds;
      await tester.pumpWidget(navigation(selected: 2));
      expect(auraPainter(tester).selected, isTrue);
      expect(auraPainter(tester).seconds, greaterThanOrEqualTo(before));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'reduced motion stops the clock and burst while Chatbot still opens',
    (tester) async {
      final selected = <int>[];
      await tester.pumpWidget(navigation());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(auraPainter(tester).seconds, greaterThan(0));
      await tester.pumpWidget(
        navigation(reduced: true, onSelected: selected.add),
      );
      await tester.pumpAndSettle();
      expect(auraPainter(tester).motion, isFalse);
      expect(auraPainter(tester).seconds, 0);
      await tester.tap(find.byKey(const ValueKey('chatbot-floating-action')));
      await tester.pumpAndSettle();
      expect(selected, [2]);
      expect(auraPainter(tester).burst, 1);
      expect(tester.binding.transientCallbackCount, 0);
    },
  );

  testWidgets(
    'platform reduce motion and offstage TickerMode pause and resume the orb',
    (tester) async {
      await tester.pumpWidget(navigation());
      await tester.pump();
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(reduceMotion: true);
      await tester.pumpAndSettle();
      expect(auraPainter(tester).motion, isFalse);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(auraPainter(tester).motion, isTrue);
      await tester.pumpWidget(navigation(enabled: false));
      await tester.pumpAndSettle();
      expect(auraPainter(tester).motion, isFalse);
      await tester.pumpWidget(navigation());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(auraPainter(tester).seconds, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'backgrounding pauses animation and returning to the app resumes it',
    (tester) async {
      await tester.pumpWidget(navigation());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(auraPainter(tester).motion, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(auraPainter(tester).motion, isTrue);
      expect(auraPainter(tester).seconds, greaterThan(0));
      await tester.pumpWidget(const SizedBox());
    },
  );
}
