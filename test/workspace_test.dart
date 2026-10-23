import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/screens/auth/login_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/workspace_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

class WorkspaceMemoryStore extends SecureStore {
  final values = <String, String>{
    'instance_hash':
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  };
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

http.Response workspaceLicense() => http.Response(
  jsonEncode({
    'status': 'success',
    'valid': true,
    'app': 'magicai',
    'features': ['chat', 'social_scheduler', 'image_gen'],
    'session_token': 'verified-license-session',
    'session_expires_at': DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 5))
        .toIso8601String(),
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureStore.channel, null),
  );

  test('workspace links remain on the licensed HTTPS origin', () {
    final service = WorkspaceService(
      api: MobileApi(store: WorkspaceMemoryStore()),
    );
    for (final url in [
      'http://magicai.example.test/magicai-mobile/open/test',
      'https://evil.example/magicai-mobile/open/test',
      'https://magicai.example.test@evil.example/magicai-mobile/open/test',
      'https://magicai.example.test:444/magicai-mobile/open/test',
      'https://magicai.example.test/dashboard/admin',
    ]) {
      expect(() => service.trustedUrl(url), throwsA(isA<ApiFailure>()));
    }
    expect(
      service
          .trustedUrl('https://magicai.example.test/magicai-mobile/open/test')
          .host,
      'magicai.example.test',
    );
  });

  test('workspace opening uses one-time links and keeps API tokens out of native browser URLs', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureStore.channel, (call) async {
          calls.add(call);
          return null;
        });
    final store = WorkspaceMemoryStore()
      ..values['access_token'] = 'private-access-token';
    final api = MobileApi(
      store: store,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return workspaceLicense();
        }
        expect(request.url.path, '/api/mobile/v1/web/session');
        expect(request.headers['Authorization'], 'Bearer private-access-token');
        expect(
          jsonDecode(request.body)['module_id'],
          'web:ext_social_media_automation',
        );
        return http.Response(
          jsonEncode({
            'url': 'https://magicai.example.test/magicai-mobile/open/one-time',
            'handoff_token': 'opaque-handoff',
          }),
          201,
        );
      }),
    );
    await WorkspaceService(api: api).open(
      destination: 'module',
      moduleId: 'web:ext_social_media_automation',
      title: 'Automations',
    );
    expect(calls.single.method, 'openUrl');
    expect(
      calls.single.arguments['url'],
      isNot(contains('private-access-token')),
    );
  });

  test('browser sign-in requires a returned code and device proof', () async {
    var polls = 0;
    var returnChecks = 0;
    final browserCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SecureStore.channel, (call) async {
          if (call.method == 'createLoginProof') {
            return {
              'verifier': 'device-private-verifier',
              'challenge': 'public-challenge',
            };
          }
          if (call.method == 'consumeAuthReturn') {
            returnChecks++;
            if (returnChecks == 1) {
              return null;
            }
            return {
              'flow': returnChecks == 2 ? 'another-flow' : 'pending-flow',
              'code': 'approved-authorization-code',
            };
          }
          browserCalls.add(call);
          return null;
        });
    final store = WorkspaceMemoryStore();
    final api = MobileApi(
      store: store,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return workspaceLicense();
        }
        expect(request.headers.containsKey('Authorization'), isFalse);
        final body = jsonDecode(request.body) as Map;
        if (request.url.path.endsWith('/auth/browser')) {
          expect(body['code_challenge'], 'public-challenge');
          expect(body['provider'], 'google');
          return http.Response(
            jsonEncode({
              'flow': 'pending-flow',
              'url': 'https://magicai.example.test/magicai-mobile/sign-in/pending-flow',
            }),
            201,
          );
        }
        expect(returnChecks, greaterThanOrEqualTo(3));
        expect(body['code_verifier'], 'device-private-verifier');
        expect(body['code'], 'approved-authorization-code');
        polls++;
        if (polls == 1) {
          return http.Response(jsonEncode({'status': 'pending'}), 202);
        }
        return http.Response(
          jsonEncode({
            'access_token': 'approved-access-token',
            'expires_at': DateTime.now()
                .add(const Duration(days: 1))
                .toIso8601String(),
            'user': {'id': 1},
          }),
          200,
        );
      }),
    );
    await BrowserLoginFlow(
      api: api,
      pollInterval: Duration.zero,
    ).login(provider: 'google');
    expect(polls, 2);
    expect(store.values['access_token'], 'approved-access-token');
    expect(
      browserCalls.single.arguments['url'],
      isNot(contains('device-private-verifier')),
    );
  });

  testWidgets('social buttons follow enabled admin providers', (tester) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: SocialLoginButtons(
            providers: const [
              {'id': 'google', 'label': 'Google', 'available': true},
              {
                'id': 'facebook',
                'label': 'Facebook',
                'available': false,
                'message': 'Setup required',
              },
              {
                'id': 'github',
                'label': 'GitHub',
                'available': false,
                'message': 'Disabled by administrator',
              },
            ],
            onSelected: (value) => chosen = value,
          ),
        ),
      ),
    );
    expect(find.text('Login with Google'), findsOneWidget);
    expect(find.text('Login with Facebook'), findsNothing);
    expect(find.text('Login with Github'), findsNothing);
    expect(find.text('Setup required'), findsNothing);
    expect(find.text('Disabled by administrator'), findsNothing);
    await tester.tap(find.text('Login with Google'));
    expect(chosen, 'google');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'extension workspaces are searchable and distinguish locked tools',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: WorkspaceScreen(
              modules: [
                {
                  'id': 'web:auto_dm',
                  'title': 'Comment & DM automation',
                  'description': 'Social tools',
                  'category': 'Social & marketing',
                  'available': true,
                },
                {
                  'id': 'web:video',
                  'title': 'Video studio',
                  'description': 'Create video',
                  'category': 'Creative studio',
                  'available': false,
                },
              ],
              refresh: () async {},
            ),
          ),
        ),
      );
      expect(find.text('Comment & DM automation'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.textContaining('Upgrade to unlock'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.textContaining('Upgrade to unlock'), findsOneWidget);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 1000));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'automation');
      await tester.pump();
      expect(find.text('Comment & DM automation'), findsOneWidget);
      expect(find.text('Video studio'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'dashboard presents live balances and enabled tools without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: StudioDashboard(
              user: const {'name': 'Asha'},
              credits: const {'plan': 'Creator', 'words': 1234, 'images': 42},
              modules: const [],
              tools: const [],
              refresh: () async {},
            ),
          ),
        ),
      );
      expect(find.text('1234'), findsOneWidget);
      final imageBalance = find
          .ancestor(of: find.text('images left'), matching: find.byType(Column))
          .first;
      expect(find.text('images left'), findsOneWidget);
      expect(
        find.descendant(of: imageBalance, matching: find.text('42')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
