import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/widgets/magic_motion.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await MagicMotionSettings.instance.setLevel(MagicMotionLevel.subtle);
  });

  test('motion level is saved and restored from local preferences', () async {
    await MagicMotionSettings.instance.setLevel(MagicMotionLevel.max);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('magic_motion_level'), 'max');

    SharedPreferences.setMockInitialValues({'magic_motion_level': 'off'});
    await MagicMotionSettings.instance.load();

    expect(MagicMotionSettings.instance.level, MagicMotionLevel.off);
  });

  testWidgets('taps remain functional without decorative click effects', (
    tester,
  ) async {
    await MagicMotionSettings.instance.setLevel(MagicMotionLevel.max);
    var tapCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: false),
          child: MagicInteractionLayer(child: child!),
        ),
        home: Scaffold(
          body: Center(
            child: MagicPressFeedback(
              child: Material(
                child: InkWell(
                  onTap: () => tapCount++,
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tap me'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final tapTarget = tester.getCenter(find.text('Tap me'));
    final gesture = await tester.startGesture(tapTarget);
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 32));

    expect(tapCount, 1);
    expect(find.byKey(const ValueKey('magic-tap-burst-painter')), findsNothing);
    expect(
      find.byKey(const ValueKey('magic-press-feedback-transform')),
      findsNothing,
    );

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: MagicInteractionLayer(child: child!),
        ),
        home: Scaffold(
          body: Center(
            child: MagicPressFeedback(
              child: Material(
                child: InkWell(
                  onTap: () => tapCount++,
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Tap me'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Tap me'));
    await tester.pump();
    expect(tapCount, 2);
  });

  testWidgets('detail routes keep the custom spring transition usable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          pageTransitionsTheme: const PageTransitionsTheme(
            builders: {
              TargetPlatform.android: MagicPageTransitionsBuilder(),
              TargetPlatform.iOS: MagicPageTransitionsBuilder(),
            },
          ),
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Detail page')),
                ),
              ),
              child: const Text('Open detail'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('Detail page'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
