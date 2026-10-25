import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:magicai_mobile/main.dart';
import 'package:magicai_mobile/screens/auth/login_screen.dart';
import 'package:magicai_mobile/screens/home_screen.dart';
import 'package:magicai_mobile/screens/splash_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/startup_service.dart';

import 'mobile_api_test.dart' show MemorySecureStore, jsonResponse, license;

class BlockedStartup extends MobileApi {
  final pending = Completer<void>();
  @override
  Future<void> bootstrap() => pending.future;
}

MobileApi startupApi({
  MemorySecureStore? store,
  int profileStatus = 200,
  Completer<void>? profilePending,
  bool validLicense = true,
}) {
  return MobileApi(
    store: store ?? MemorySecureStore(),
    client: MockClient((request) async {
      if (request.url.path.endsWith('/license')) {
        return jsonResponse(license({'valid': validLicense}));
      }
      if (request.url.path.endsWith('/auth/profile') ||
          request.url.path.endsWith('/auth/refresh')) {
        if (profilePending != null) await profilePending.future;
        return jsonResponse({
          'message': 'Unauthenticated.',
          'id': 1,
        }, profileStatus);
      }
      if (request.url.path.endsWith('/auth/options')) {
        return jsonResponse({'providers': []});
      }
      if (request.url.path.endsWith('/config')) {
        return jsonResponse({
          'app': 'magicai',
          'schema_version': 1,
          'navigation': [
            {
              'id': 'home',
              'component': 'dashboard',
              'label': 'Home',
              'icon': 'home',
            },
          ],
          'tools': [],
          'modules': [],
          'user': {},
          'credits': {},
        });
      }
      throw StateError('Unexpected startup request: ${request.url.path}');
    }),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'has_seen_mobile_intro_v1': true});
    MobileApi.failure.value = null;
  });
  tearDown(() {
    MobileApi.failure.value = null;
  });

  testWidgets('a clean installation reaches login with the same API client', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(onThemeChanged: (_) {}, api: startupApi()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a saved session reaches the dashboard without blocking on credits',
    (tester) async {
      final store = MemorySecureStore()..values['access_token'] = 'saved-token';
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(
            onThemeChanged: (_) {},
            api: startupApi(store: store),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final refresh in [false, true]) {
    testWidgets(
      'an expired ${refresh ? 'refresh' : 'profile'} token returns to login without a global lockout',
      (tester) async {
        final store = MemorySecureStore()
          ..values['access_token'] = 'expired-token';
        if (refresh) store.values['access_expires_at'] = '2020-01-01T00:00:00Z';
        await tester.pumpWidget(
          MaterialApp(
            home: SplashScreen(
              onThemeChanged: (_) {},
              api: startupApi(store: store, profileStatus: 401),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(store.values.containsKey('access_token'), isFalse);
        expect(MobileApi.failure.value, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a slow profile cannot keep a signed-in user on splash indefinitely',
    (tester) async {
      final pending = Completer<void>();
      final store = MemorySecureStore()..values['access_token'] = 'saved-token';
      final api = startupApi(
        store: store,
        profilePending: pending,
        profileStatus: 401,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SplashScreen(onThemeChanged: (_) {}, api: api),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 13));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      // A late response belongs to startup and must not replace a later session.
      pending.complete();
      await tester.pumpAndSettle();
      expect(MobileApi.failure.value, isNull);
      expect(store.values['access_token'], 'saved-token');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('unresponsive startup shows Retry and never bypasses licensing', (
    tester,
  ) async {
    final api = BlockedStartup();
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(onThemeChanged: (_) {}, api: api),
      ),
    );
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(find.byType(LoginScreen), findsNothing);
    api.pending.completeError(const ApiFailure('License Invalid / Expired'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Android secure storage calls time out if the channel never answers',
    (tester) async {
      final pending = Completer<Object?>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SecureStore.channel,
        (_) => pending.future,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SecureStore.channel,
          null,
        ),
      );
      for (final operation in [
        () => SecureStore().read('access_token'),
        () => SecureStore().write('access_token', 'token'),
        () => SecureStore().delete('access_token'),
      ]) {
        var timedOut = false;
        operation().then<void>(
          (_) {},
          onError: (Object error) {
            timedOut = error is TimeoutException;
          },
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 6));
        expect(timedOut, isTrue);
      }
      pending.complete(null);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'blocked preference loading cannot prevent the first frame or login',
    (tester) async {
      final theme = Completer<String>();
      await tester.pumpWidget(
        MagicAIMobileApp(
          initialTheme: 'dark',
          api: startupApi(),
          loadTheme: () => theme.future,
        ),
      );
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(
        tester
            .widget<MaterialApp>(find.byType(MaterialApp))
            .themeAnimationDuration,
        Duration.zero,
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      theme.complete('light');
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(LoginScreen))).brightness,
        Brightness.dark,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'session and license error overlays preserve the navigator for recovery',
    (tester) async {
      final api = startupApi();
      await tester.pumpWidget(
        MagicAIMobileApp(
          initialTheme: 'dark',
          api: api,
          loadTheme: () async => 'dark',
        ),
      );
      await tester.pumpAndSettle();
      final navigator = tester.state(find.byType(Navigator).first);
      MobileApi.failure.value = const ApiFailure(
        'Session expired.',
        status: 401,
      );
      await tester.pumpAndSettle();
      expect(find.text('Session expired'), findsOneWidget);
      expect(
        tester.state(find.byType(Navigator, skipOffstage: false).first),
        same(navigator),
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(MobileApi.failure.value, isNull);
      MobileApi.failure.value = const ApiFailure(
        'License Invalid / Expired',
        code: 'license_invalid',
      );
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsNothing);
      expect(
        tester.state(find.byType(Navigator, skipOffstage: false).first),
        same(navigator),
      );
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(MobileApi.failure.value, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  test('an invalid license prevents session restoration', () async {
    await expectLater(
      StartupService(api: startupApi(validLicense: false)).restoreSession(),
      throwsA(isA<ApiFailure>()),
    );
  });
}
