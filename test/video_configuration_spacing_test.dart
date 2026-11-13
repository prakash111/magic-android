import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/video_tool_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final tool in [
    'video_agent',
    'video_studio',
    'ai_video',
    'auto_edit_videos',
  ]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('$tool has padded full-width controls at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = nativeApi(
          (path, _) async =>
              path == '/video/tools' ? {'engines': []} : {'data': []},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: VideoToolScreen(module: {'id': 'web:$tool'}, api: api),
          ),
        );
        await tester.pumpAndSettle();

        final button = find.widgetWithText(FilledButton, 'Generate Video');
        await tester.ensureVisible(button);
        await tester.pumpAndSettle();
        final buttonRect = tester.getRect(button);
        final contentRect = tester.getRect(
          find.ancestor(of: button, matching: find.byType(Column)).first,
        );
        final iconRect = tester.getRect(
          find.descendant(
            of: button,
            matching: find.byIcon(Icons.auto_awesome_rounded),
          ),
        );
        final labelRect = tester.getRect(find.text('Generate Video'));
        expect(buttonRect.left, closeTo(contentRect.left, .1));
        expect(buttonRect.right, closeTo(contentRect.right, .1));
        expect(iconRect.left - buttonRect.left, greaterThanOrEqualTo(23.9));
        expect(buttonRect.right - labelRect.right, greaterThanOrEqualTo(23.9));
        expect(labelRect.left - iconRect.right, closeTo(8, .1));
        expect(buttonRect.height, greaterThanOrEqualTo(52));
        expect(tester.takeException(), isNull);

        final pickerLabel = find.text('Tap to pick source image');
        if (tool == 'ai_video' || tool == 'video_studio') {
          await tester.ensureVisible(pickerLabel);
          await tester.pumpAndSettle();
          final pickerRect = tester.getRect(
            find
                .ancestor(of: pickerLabel, matching: find.byType(InkWell))
                .first,
          );
          final textRect = tester.getRect(pickerLabel);
          expect(textRect.left - pickerRect.left, greaterThanOrEqualTo(15.9));
          expect(pickerRect.right - textRect.right, greaterThanOrEqualTo(15.9));
          expect(pickerRect.height, greaterThanOrEqualTo(120));
        } else {
          expect(pickerLabel, findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
