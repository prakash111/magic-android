import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/auth/login_screen.dart';
import 'package:magicai_mobile/screens/splash_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/welcome_experience.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'startup_test.dart' show startupApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'first launch shows the native welcome once, Skip continues to real login',
    (tester) async {
      final api = startupApi();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SplashScreen(api: api, onThemeChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WelcomeScreen), findsOneWidget);
      expect(find.text('Create anything, instantly'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getBool(welcomeCompletedKey),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SplashScreen(api: api, onThemeChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(WelcomeScreen), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final light in [false, true]) {
    for (final size in [const Size(320, 568), const Size(740, 360)]) {
      testWidgets(
        'welcome steps fit $size at 130 percent text in ${light ? 'light' : 'dark'} mode',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            MaterialApp(
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: WelcomeScreen(
                destination: () => const Scaffold(body: Text('Destination')),
              ),
            ),
          );
          for (var i = 0; i < 3; i++) {
            await tester.tap(find.text('Next'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          expect(find.text('Get started'), findsOneWidget);
          await tester.tap(find.text('Get started'));
          await tester.pumpAndSettle();
          expect(find.text('Destination'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
