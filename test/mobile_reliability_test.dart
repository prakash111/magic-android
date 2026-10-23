import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/home_screen.dart';
import 'package:magicai_mobile/screens/native_creative_screen.dart';
import 'package:magicai_mobile/screens/native_visual_editor.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/services/extension_workflow_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/workspace_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'extension_workflow_test.dart' show visualSession;
import 'mobile_api_test.dart' show MemorySecureStore, jsonResponse, license;
import 'native_screen_test.dart' show nativeApi;

Widget app(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(body: child),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUp(() => MobileApi.failure.value = null);
  test('legacy and customer handoffs retain trusted origin checks', () {
    final api = MobileApi(store: MemorySecureStore());
    final service = WorkspaceService(api: api);
    for (final prefix in ['mobile', 'magicai-mobile']) {
      for (final route in ['open', 'sign-in']) {
        expect(
          service
              .trustedUrl(
                'https://magicai.example.test/$prefix/$route/${'t' * 64}',
              )
              .host,
          api.origin.host,
        );
      }
      expect(
        VisualWidgetSession.parse(
          visualSession({
            'url': 'https://magicai.example.test/$prefix/open/${'t' * 64}',
          }),
          api.origin,
        ).lease,
        'l' * 64,
      );
    }
    for (final value in [
      'https://evil.example/mobile/open/${'t' * 64}',
      'http://magicai.example.test/mobile/open/${'t' * 64}',
      'https://magicai.example.test:444/mobile/open/${'t' * 64}',
      'https://evil@magicai.example.test/mobile/open/${'t' * 64}',
      'https://magicai.example.test/mobile-other/open/${'t' * 64}',
    ]) {
      expect(() => service.trustedUrl(value), throwsA(isA<ApiFailure>()));
      expect(
        () => VisualWidgetSession.parse(
          visualSession({'url': value}),
          api.origin,
        ),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
  for (final load in [
    ('/credits', 'GET', <String, dynamic>{}),
    ('/native/screen', 'POST', <String, dynamic>{'module_id': 'web:crm'}),
    ('/native/workspace', 'POST', <String, dynamic>{'module_id': 'web:crm'}),
    ('/native/chat-tools', 'POST', <String, dynamic>{'operation': 'list'}),
    ('/native/extension', 'POST', <String, dynamic>{'operation': 'load'}),
    ('/native/workflow', 'POST', <String, dynamic>{'operation': 'describe'}),
  ]) {
    testWidgets('${load.$1} stops waiting within ten seconds', (tester) async {
      final pending = Completer<http.Response>();
      final api = MobileApi(
        store: MemorySecureStore()..values['access_token'] = 'private-token',
        client: MockClient(
          (r) async => r.url.path.endsWith('/license')
              ? jsonResponse(license())
              : pending.future,
        ),
      );
      Object? failure;
      final result = api
          .request(load.$1, method: load.$2, body: load.$3)
          .then<void>(
            (_) {},
            onError: (Object e) {
              failure = e;
            },
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      expect(failure, isA<ApiFailure>());
      pending.complete(jsonResponse({}));
      await tester.pump();
      await result;
    });
  }
  testWidgets(
    'generation retains its longer deadline and is never retried automatically',
    (tester) async {
      final pending = Completer<http.Response>();
      var submissions = 0;
      final api = MobileApi(
        store: MemorySecureStore()..values['access_token'] = 'private-token',
        client: MockClient((r) async {
          if (r.url.path.endsWith('/license')) return jsonResponse(license());
          ++submissions;
          return pending.future;
        }),
      );
      Object? failure;
      var completed = false;
      final result = api
          .request('/tools/mobile-image/run', method: 'POST')
          .then<void>(
            (_) {
              completed = true;
            },
            onError: (Object e) {
              failure = e;
            },
          );
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      expect(completed, isFalse);
      expect(failure, isNull);
      expect(submissions, 1);
      pending.complete(jsonResponse({'images': []}));
      await tester.pump();
      await result;
      expect(completed, isTrue);
    },
  );
  testWidgets('visual failures show Retry without a competing spinner', (
    tester,
  ) async {
    var requests = 0;
    final api = nativeApi((_, _) async {
      ++requests;
      throw const ApiFailure('Unable to verify the visual editor session.');
    });
    await tester.pumpWidget(
      app(
        NativeVisualEditor(
          api: api,
          moduleId: 'web:editor',
          kind: 'image_mask',
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(requests, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets('late visual sessions are closed after the loading deadline', (
    tester,
  ) async {
    final pending = Completer<Map<String, dynamic>>();
    var closes = 0;
    final api = nativeApi((_, body) async {
      if (body['operation'] == 'close') {
        ++closes;
        return {};
      }
      return pending.future;
    });
    await tester.pumpWidget(
      app(
        NativeVisualEditor(
          api: api,
          moduleId: 'web:editor',
          kind: 'image_mask',
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(visualSession());
    await tester.pump();
    await tester.pump();
    expect(closes, 1);
    expect(find.byType(AndroidView), findsNothing);
  });
  testWidgets('Creative Suite errors can be retried to real history', (
    tester,
  ) async {
    var failing = true;
    final api = nativeApi((path, _) async {
      if (failing) throw const ApiFailure('Connection unavailable');
      if (path == '/native/creative/templates') return [];
      return {'data': [], 'current_page': 1, 'last_page': 1};
    });
    await tester.pumpWidget(app(NativeCreativeScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    failing = false;
    await tester.ensureVisible(find.text('Retry'));
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Connection unavailable'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'header refresh reloads Chat and Calendar while retaining the prompt',
    (tester) async {
      final calls = <String>[];
      final api = nativeApi((path, _) async {
        calls.add(path);
        if (path == '/config') {
          return {
            'app': 'magicai',
            'schema_version': 1,
            'navigation': [
              {'id': 'home', 'label': 'Home', 'component': 'dashboard'},
              {'id': 'chat', 'label': 'Chat', 'component': 'chat'},
              {'id': 'calendar', 'label': 'Calendar', 'component': 'social'},
            ],
            'tools': [],
            'modules': [],
            'user': {},
            'credits': {},
          };
        }
        if (path == '/chat/options') {
          return {
            'personas': [
              {'id': 1, 'name': 'Assistant'},
            ],
            'models': [
              {'id': 'test', 'name': 'Test model'},
            ],
          };
        }
        if (path == '/chat/conversations' ||
            path == '/social-media/platforms') {
          return [];
        }
        if (path.startsWith('/social-media/posts?')) {
          return {'data': [], 'current_page': 1, 'last_page': 1};
        }
        throw StateError('Unexpected API path');
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: HomeScreen(api: api, onThemeChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Keep this unsent prompt',
      );
      calls.clear();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(
        calls,
        containsAll(['/config', '/chat/options', '/chat/conversations']),
      );
      expect(find.text('Keep this unsent prompt'), findsOneWidget);
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      calls.clear();
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(calls, contains('/social-media/platforms'));
      expect(
        calls.where((p) => p.startsWith('/social-media/posts?')),
        hasLength(1),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('image provider errors retain the real server message', (
    tester,
  ) async {
    final api = nativeApi((path, _) async {
      if (path == '/native/creative/templates') return [];
      if (path == '/image-models') {
        return {
          'data': [
            {'id': 'gpt-image-1', 'title': 'GPT image 1', 'is_default': true},
          ],
        };
      }
      if (path == '/tools/mobile-image/run') {
        return {
          'status': 'error',
          'message': 'Image provider quota is exhausted',
        };
      }
      return {'data': [], 'current_page': 1, 'last_page': 1};
    });
    await tester.pumpWidget(app(NativeCreativeScreen(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'A blue poster');
    await tester.ensureVisible(find.text('Generate reference'));
    await tester.tap(find.text('Generate reference'));
    await tester.pumpAndSettle();
    expect(find.text('Image provider quota is exhausted'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
  testWidgets('Account supports pull to refresh', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      app(
        AccountHub(
          user: const {},
          credits: const {},
          logout: () {},
          toggleTheme: () {},
          refresh: () async {
            ++refreshes;
          },
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, 450));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });
  testWidgets(
    'Explore category targets remain at least 48dp with larger text',
    (tester) async {
      await tester.pumpWidget(
        app(
          MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: WorkspaceScreen(
              modules: const [
                {'id': 'crm', 'title': 'CRM', 'category': 'CRM'},
              ],
              refresh: () async {},
            ),
          ),
        ),
      );
      expect(
        tester.getSize(find.byType(ChoiceChip).first).height,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
    },
  );
  test('filled buttons and light input hints meet text contrast', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
    }

    for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
      expect(
        contrast(theme.colorScheme.primary, theme.colorScheme.onPrimary),
        greaterThanOrEqualTo(4.5),
      );
    }
    expect(
      contrast(
        AppTheme.lightTheme.inputDecorationTheme.hintStyle!.color!,
        AppTheme.lightTheme.inputDecorationTheme.fillColor!,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });
}
