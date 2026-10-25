import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/auth/auth_links.dart';
import 'package:magicai_mobile/screens/auth/auth_verification_dialog.dart';
import 'package:magicai_mobile/screens/auth/login_screen.dart';
import 'package:magicai_mobile/screens/auth/register_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/auth_motion.dart';
import 'package:magicai_mobile/widgets/prompt_creation_intro.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_test.dart' show MemorySecureStore, jsonResponse, license;

MobileApi authApi([Future<http.Response> Function(http.Request)? handle]) =>
    MobileApi(
      store: MemorySecureStore(),
      origin: Uri.parse('https://magicai.example.test'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return jsonResponse(license());
        }
        if (request.url.path.endsWith('/auth/options')) {
          return jsonResponse({'providers': []});
        }
        if (handle != null) return handle(request);
        throw StateError('Unexpected auth request: ${request.url.path}');
      }),
    );

Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void expectNoFlutterError(WidgetTester tester) {
  final error = tester.takeException();
  if (error is FlutterError) {
    for (final render in tester.allRenderObjects.whereType<RenderFlex>()) {
      if (render.toStringShort().contains('OVERFLOWING')) {
        debugPrint(render.toStringDeep());
      }
    }
  }
  expect(error, isNull);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MobileApi.failure.value = null;
  });

  testWidgets(
    'prompt types then morphs into the drawn sparkle logo and assembled brand',
    (tester) async {
      Future<void> frame(double seconds) => tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: PromptCreationIntro(
                  animation: AlwaysStoppedAnimation(seconds / 5.4),
                ),
              ),
            ),
          ),
        ),
      );
      await frame(1.2);
      expect(find.textContaining('Create som'), findsOneWidget);
      final pill = tester.getSize(
        find.byKey(const ValueKey('prompt-morph-tile')),
      );
      expect(pill.width, 296);
      expect(pill.height, 58);
      await frame(3.7);
      final logo = tester.getSize(
        find.byKey(const ValueKey('prompt-morph-tile')),
      );
      expect(logo, const Size(114, 114));
      expect(find.textContaining('Create som'), findsNothing);
      await frame(5.4);
      expect(
        find.text('SEO Suite • Generative AI • Social Suite'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter is MagicSparklePainter &&
              (widget.painter as MagicSparklePainter).progress == 1,
        ),
        findsOneWidget,
      );
      expectNoFlutterError(tester);
    },
  );

  testWidgets('native ambient motion stops cleanly when the view is disposed', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: AuthScene(child: Center(child: AuthMark())),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);
    expectNoFlutterError(tester);
  });

  for (final light in [false, true]) {
    for (final size in [const Size(320, 568), const Size(740, 360)]) {
      testWidgets(
        'auth forms fit $size at 130 percent text in ${light ? 'light' : 'dark'} mode',
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
              home: LoginScreen(api: authApi(), onThemeChanged: (_) {}),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(TextFormField), findsNWidgets(2));
          await tapVisible(tester, find.text('Create an account'));
          expect(find.byType(RegisterScreen), findsOneWidget);
          expect(find.text('0%'), findsOneWidget);
          await tapVisible(tester, find.text('Create Account'));
          expect(find.text('Use at least 8 characters.'), findsOneWidget);
          expect(
            find.text('Please accept the terms and privacy policy.'),
            findsOneWidget,
          );
          expectNoFlutterError(tester);
          tester.view.viewInsets = FakeViewPadding(bottom: size.height / 2);
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Create Account'));
          await tester.pumpAndSettle();
          expectNoFlutterError(tester);
          tester.view.resetViewInsets();
        },
      );
    }
  }

  testWidgets(
    'registration progress and strength reflect input, validation failures never show success',
    (tester) async {
      Map? submitted;
      final api = authApi((request) async {
        expect(request.url.path, '/api/mobile/v1/auth/register');
        submitted = jsonDecode(request.body) as Map;
        return jsonResponse({
          'message': 'This email is already registered.',
        }, 422);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: RegisterScreen(api: api, onThemeChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      for (final item in {
        'First Name': 'Test',
        'Last Name': 'Writer',
        'Email address': 'writer@example.test',
        'Password': 'Secure123!',
        'Confirm password': 'Secure123!',
      }.entries) {
        final field = find.widgetWithText(TextFormField, item.key);
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        await tester.enterText(field, item.value);
        await tester.pumpAndSettle();
      }
      expect(find.text('Strong'), findsOneWidget);
      await tapVisible(tester, find.byType(Checkbox));
      expect(find.text('100%'), findsOneWidget);
      await tapVisible(tester, find.text('Create Account'));
      expect(submitted!['password_confirmation'], 'Secure123!');
      expect(submitted!['surname'], 'Writer');
      expect(find.text('This email is already registered.'), findsOneWidget);
      expect(find.byType(AuthSuccess), findsNothing);
      expectNoFlutterError(tester);
    },
  );

  testWidgets(
    'success animation appears only after the real authentication request succeeds',
    (tester) async {
      final response = Completer<http.Response>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SecureStore.channel,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SecureStore.channel,
          null,
        ),
      );
      final api = authApi((request) async {
        expect(request.url.path, '/api/mobile/v1/auth/login');
        return response.future;
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: LoginScreen(api: api, onThemeChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'person@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.ensureVisible(find.text('Sign In'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign In'));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(AuthSuccess), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      response.complete(
        jsonResponse({
          'access_token': 'test-access-token',
          'expires_at': '2099-01-01T00:00:00Z',
          'user': {'id': 7, 'name': 'Test', 'email': 'person@example.test'},
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AuthSuccess), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(await api.store.read('access_token'), 'test-access-token');
      expectNoFlutterError(tester);
    },
  );

  testWidgets(
    'six-digit authenticator accepts paste and incomplete codes cannot leave the dialog',
    (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const AuthVerificationDialog(),
                  );
                },
                child: const Text('Verify sign-in'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Verify sign-in'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Enter all six digits.'), findsOneWidget);
      expect(result, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('auth-code-0')),
        '123456',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verify'));
      await tester.pumpAndSettle();
      expect(result, '123456');
      expectNoFlutterError(tester);
    },
  );

  testWidgets(
    'auth links use only the configured installation and the system browser',
    (tester) async {
      String? opened;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SecureStore.channel,
        (call) async {
          if (call.method == 'openUrl') {
            opened = (call.arguments as Map)['url'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SecureStore.channel,
          null,
        ),
      );
      final api = authApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => openAuthPage(context, api, '/forgot-password'),
                child: const Text('Reset password'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reset password'));
      await tester.pumpAndSettle();
      expect(opened, 'https://magicai.example.test/forgot-password');
    },
  );
}
