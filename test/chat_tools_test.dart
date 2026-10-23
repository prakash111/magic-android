import 'package:http/testing.dart';
import 'package:magicai_mobile/services/mobile_api.dart';

import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/native_chat_tools_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/services/api_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'active web login flags take precedence over diagnostic availability',
    () async {
      final api = MobileApi(
        store: MemorySecureStore(),
        client: MockClient(
          (request) async => jsonResponse(
            request.url.path.endsWith('/license')
                ? license()
                : {
                    'google_active': '1',
                    'github_active': 1,
                    'facebook_active': false,
                    'providers': [],
                  },
          ),
        ),
      );
      final providers = await ApiService.getSocialLoginOptions(client: api);
      expect(providers.map((p) => p['id']), ['google', 'github']);
    },
  );
  testWidgets(
    'chat tools open the native library immediately with search and no wrapper links',
    (tester) async {
      final calls = <Map>[];
      final api = nativeApi((path, body) async {
        expectSync(path, '/native/chat-tools');
        calls.add(body);
        return {
          'kind': 'categories',
          'data': [
            {'id': 1, 'name': 'Sales'},
          ],
          'sources': [],
        };
      });
      final screen = NativeModuleRegistry.build({
        'id': 'categories',
        'route_type': 'chat_tools',
      }, api: api);
      expect(screen, isA<NativeChatToolsScreen>());
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: screen),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sales'), findsOneWidget);
      expect(find.text('Create category'), findsOneWidget);
      expect(find.text('Explore your workspace'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Sales');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(calls.last['query'], 'Sales');
    },
  );
  testWidgets(
    'training exposes real source actions and submits the existing training payload',
    (tester) async {
      Map? submitted;
      final api = nativeApi((_, body) async {
        if (body['operation'] == 'train') submitted = body;
        return {
          'kind': 'training',
          'data': [
            {'id': 7, 'title': 'Support bot', 'status': 'trained'},
          ],
          'sources': body['record_id'] == 7
              ? [
                  {
                    'id': 10,
                    'type': 'text',
                    'type_value': 'Help guide',
                    'status': 'waiting',
                  },
                ]
              : [],
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeChatToolsScreen(
              module: const {'id': 'training'},
              api: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manage knowledge'));
      await tester.pumpAndSettle();
      for (final text in [
        'Text snippet',
        'Question & answer',
        'Website URL',
        'PDF / spreadsheet',
        'Help guide',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      await tester.scrollUntilVisible(
        find.text('Train text sources'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Train text sources'));
      await tester.pumpAndSettle();
      expect(submitted?['record_id'], 7);
      expect(submitted?['inputs'], {
        'type': 'text',
        'chatbot_data': [10],
      });
      expect(submitted?['request_id'], isA<String>());
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('training forms fit a small viewport with the keyboard visible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final api = nativeApi(
      (_, _) async => {'kind': 'categories', 'data': [], 'sources': []},
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeChatToolsScreen(
            module: const {'id': 'categories'},
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create category'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    await tester.pumpAndSettle();
    expect(find.text('Save category'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
