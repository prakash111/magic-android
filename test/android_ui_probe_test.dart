import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_ui_probe.dart';

Future<void> settleProbe(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'probe reports layout changes after opening Explore without reopening the screen',
    (tester) async {
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          messages.add(message);
        }
      };
      try {
        await tester.pumpWidget(const AndroidUiProbe());
        await settleProbe(tester);
        expect(messages, contains('UI_PROBE_PASSED: theme=dark layout=list'));
        messages.clear();
        await tester.tap(find.byTooltip('Grid view'));
        await settleProbe(tester);
        expect(find.byType(SliverGrid), findsOneWidget);
        expect(messages, contains('UI_PROBE_PASSED: theme=dark layout=grid'));
        messages.clear();
        await tester.tap(find.byTooltip('List view'));
        await settleProbe(tester);
        expect(find.byType(SliverGrid), findsNothing);
        expect(messages, contains('UI_PROBE_PASSED: theme=dark layout=list'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      } finally {
        debugPrint = previous;
      }
    },
  );

  testWidgets(
    'probe reports an explicit grid choice in light mode and restores it after restart',
    (tester) async {
      final messages = <String>[];
      final previous = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) {
          messages.add(message);
        }
      };
      try {
        await tester.pumpWidget(
          const AndroidUiProbe(initialMode: ThemeMode.light),
        );
        await settleProbe(tester);
        expect(messages, contains('UI_PROBE_PASSED: theme=light layout=list'));
        await tester.tap(find.byTooltip('Grid view'));
        await settleProbe(tester);
        expect(messages, contains('UI_PROBE_PASSED: theme=light layout=grid'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        messages.clear();
        await tester.pumpWidget(
          const AndroidUiProbe(initialMode: ThemeMode.light),
        );
        await settleProbe(tester);
        expect(find.byType(SliverGrid), findsOneWidget);
        expect(messages, contains('UI_PROBE_PASSED: theme=light layout=grid'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      } finally {
        debugPrint = previous;
      }
    },
  );
}
