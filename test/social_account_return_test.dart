import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

List<Map<String, dynamic>> socialAccounts(bool connected) => [
  {
    'id': connected ? '7' : 'platform_facebook',
    'platform': 'facebook',
    'displayName': 'Facebook',
    'handle': 'ZoomNearby',
    'followers': 100,
    'isConnected': connected,
  },
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureStore.channel, null),
  );

  testWidgets(
    'an account connection opens the one-time browser link and refreshes Platforms when the app resumes',
    (tester) async {
      final browser = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureStore.channel, (call) async {
            browser.add(call);
            return null;
          });
      var connected = false;
      var loads = 0;
      final api = nativeApi((path, body) async {
        if (path == '/social-media/platforms') {
          loads++;
          return socialAccounts(connected);
        }
        expectSync(path, '/web/session');
        expectSync(body['destination'], 'social_connect');
        expectSync(body['platform'], 'facebook');
        return {
          'url': 'https://magicai.example.test/mobile/open/${'t' * 64}',
          'expires_in': 60,
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SocialAccountsScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Connect your first profile'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_link));
      await tester.pumpAndSettle();
      expect(browser.single.method, 'openUrl');
      expect('${browser.single.arguments}', isNot(contains('private-token')));
      expect('${browser.single.arguments}', isNot(contains('/dashboard/')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      connected = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(loads, 2);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Connect your first profile'), findsNothing);
      expect(find.text('ZoomNearby · 100 followers'), findsOneWidget);
    },
  );

  testWidgets(
    'a stale pre-return account request cannot overwrite the refreshed connected account',
    (tester) async {
      final stale = Completer<dynamic>();
      var loads = 0;
      final api = nativeApi((path, body) async {
        expectSync(path, '/social-media/platforms');
        loads++;
        if (loads == 2) return stale.future;
        return socialAccounts(loads >= 3);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SocialAccountsScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();
      final observer = tester.state(
        find.byType(SocialAccountsScreen),
      ) as WidgetsBindingObserver;
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      for (var attempt = 0; attempt < 10 && loads < 2; attempt++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(loads, 2);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(loads, 3);
      expect(find.byIcon(Icons.check), findsOneWidget);
      stale.complete(socialAccounts(false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.text('Connect your first profile'), findsNothing);
    },
  );
  testWidgets(
    'reconnect preserves the selected account id without disconnecting it',
    (tester) async {
      Map? ticket;
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureStore.channel, (_) async => null);
      final api = nativeApi((path, body) async {
        methods.add(path);
        if (path == '/social-media/platforms') return socialAccounts(true);
        ticket = Map.from(body);
        return {
          'url': 'https://magicai.example.test/mobile/open/${'t' * 64}',
          'expires_in': 60,
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SocialAccountsScreen(api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reconnect'));
      await tester.pumpAndSettle();
      expect(ticket!['account_id'], 7);
      expect(ticket!['platform'], 'facebook');
      expect(methods.where((path) => path.contains('/platforms/7')), isEmpty);
    },
  );
}
