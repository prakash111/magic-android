import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/extension_workflow_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_visual_editor.dart';
import 'package:magicai_mobile/services/extension_workflow_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;

Map<String, dynamic> visualSession([Map<String, dynamic> changes = const {}]) =>
    {
      'url': 'https://magicai.example.test/magicai-mobile/open/${'t' * 64}',
      'entry_url':
          'https://magicai.example.test/dashboard/user/video-editor/editor/3',
      'handoff_token': 'n' * 64,
      'lease_token': 'l' * 64,
      'expires_at': DateTime.now()
          .add(const Duration(minutes: 20))
          .toIso8601String(),
      'commands': ['save', 'export'],
      ...changes,
    };

MobileApi workflowApi(Future<dynamic> Function(dynamic request) response) =>
    MobileApi(
      store: MemorySecureStore()..values['access_token'] = 'private-bearer',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return jsonResponse(license());
        }
        expect(request.url.host, 'magicai.example.test');
        expect(request.headers['Authorization'], 'Bearer private-bearer');
        return jsonResponse(await response(request));
      }),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    MobileApi.failure.value = null;
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'signing out clears embedded editor cookies as well as the bearer token',
    () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureStore.channel, (call) async {
            calls.add(call.method);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SecureStore.channel, null),
      );
      final api = workflowApi((_) async => {});
      await api.clearSession();
      expect(calls, ['clearWebSession']);
      expect(await api.store.read('access_token'), isNull);
    },
  );

  test('native adapters use authenticated versioned APIs and keep submission IDs on retries', () async {
    final requests = <Map>[];
    final api = workflowApi((request) async {
      final data = jsonDecode(request.body) as Map;
      expect(request.url.path, '/api/mobile/v1/native/workflow');
      requests.add(data);
      return {'data': [], 'message': 'Queued', 'record_id': 4};
    });
    final service = ExtensionWorkflowService(api, 'web:photoshoot');
    await service.describe();
    await service.generate({'prompt': 'Photo'}, {}, requestId: 'same-request');
    await service.generate({'prompt': 'Photo'}, {}, requestId: 'same-request');
    await service.history(refresh: true);
    expect(requests.map((request) => request['operation']), [
      'describe',
      'generate',
      'generate',
      'status',
    ]);
    expect(requests[1]['request_id'], requests[2]['request_id']);
    expect(
      requests.every((request) => request['module_id'] == 'web:photoshoot'),
      isTrue,
    );
  });

  test('multipart workflows carry native files and structured arrays without web scripts', () async {
    final api = workflowApi((request) async {
      expect(
        request.headers['content-type'],
        startsWith('multipart/form-data;'),
      );
      expect(request.body, contains('uploads[product_image]'));
      expect(request.body, contains('product.png'));
      expect(request.body, contains('"templates":["ugc"]'));
      expect(request.body, isNot(contains('private-bearer')));
      return {'data': [], 'message': 'Queued'};
    });
    await ExtensionWorkflowService(api, 'web:templates').generate(
      {
        'templates': ['ugc'],
      },
      {
        'product_image': const WorkflowFile('product.png', [1, 2, 3]),
      },
      requestId: 'submission',
    );
  });

  test('visual sessions and messages reject untrusted origins, expired leases and arbitrary commands', () {
    final origin = Uri.parse('https://magicai.example.test');
    final session = VisualWidgetSession.parse(visualSession(), origin);
    for (final changes in [
      {'url': 'https://evil.example/magicai-mobile/open/${'t' * 64}'},
      {
        'entry_url':
            'https://magicai.example.test@evil.example/dashboard/user/editor',
      },
      {'entry_url': 'http://magicai.example.test/dashboard/user/editor'},
      {'entry_url': 'https://magicai.example.test:444/dashboard/user/editor'},
      {'entry_url': 'https://magicai.example.test/dashboard/admin'},
      {'url': 'https://magicai.example.test/magicai-mobile/open/bad-ticket'},
      {'expires_at': '2001-01-01'},
      {'handoff_token': 'short'},
    ]) {
      expect(
        () => VisualWidgetSession.parse(visualSession(changes), origin),
        throwsA(isA<ApiFailure>()),
      );
    }
    Map<String, dynamic> message(String type) => {
      'version': 1,
      'nonce': session.nonce,
      'type': type,
      'payload': {},
    };
    expect(session.readMessage(jsonEncode(message('dirty')))?['type'], 'dirty');
    expect(
      session.readMessage(
        jsonEncode({...message('saved'), 'nonce': 'spoofed'}),
      ),
      isNull,
    );
    expect(
      session.readMessage(jsonEncode({...message('ready'), 'version': 2})),
      isNull,
    );
    expect(session.readMessage(jsonEncode(message('executeScript'))), isNull);
    expect(session.readMessage('{malformed'), isNull);
    expect(
      session.readMessage(jsonEncode({...message('ready'), 'payload': 'bad'})),
      isNull,
    );
  });

  test(
    'server route keys select native workflows and isolated visual widgets',
    () {
      final api = workflowApi((_) async => {});
      expect(
        NativeModuleRegistry.build({
          'id': 'web:photo',
          'route_type': 'extension_workflow',
        }, api: api),
        isA<ExtensionWorkflowScreen>(),
      );
      expect(
        NativeModuleRegistry.build({
          'id': 'web:mask',
          'route_type': 'visual_tool',
          'visual_kind': 'image_mask',
        }, api: api),
        isA<NativeVisualEditor>(),
      );
    },
  );

  testWidgets(
    'workflow forms validate, preserve select defaults and show actual queued results',
    (tester) async {
      final submits = <Map>[];
      final api = workflowApi((request) async {
        final data = jsonDecode(request.body) as Map;
        if (data['operation'] == 'describe') {
          return {
            'title': 'Custom photoshoot',
            'fields': [
              {
                'name': 'prompt',
                'label': 'Prompt',
                'type': 'text',
                'required': true,
              },
              {
                'name': 'ratio',
                'label': 'Aspect ratio',
                'type': 'select',
                'options': [
                  {'value': '1:1', 'label': 'Square'},
                ],
              },
            ],
            'data': [],
          };
        }
        submits.add(data);
        return {
          'message': 'Queued on server',
          'data': [
            {'id': 5, 'title': 'My photo', 'status': 'processing'},
          ],
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExtensionWorkflowScreen(
              module: const {'id': 'web:custom'},
              api: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(submits, isEmpty);
      await tester.enterText(find.byType(TextFormField), 'A photo');
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(submits.single['inputs'], {'prompt': 'A photo', 'ratio': '1:1'});
      expect(submits.single['request_id'], matches(RegExp(r'^[a-f0-9-]{36}$')));
      expect(find.text('My photo'), findsOneWidget);
      expect(find.text('processing'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 9));
      expect(submits.length, 1);
    },
  );

  testWidgets(
    'visual editors never fall back to a browser on unsupported platforms',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final api = workflowApi((_) async => visualSession());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeVisualEditor(
              api: api,
              moduleId: 'web:video',
              kind: 'video_timeline',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.text('This visual editor is available in the Android app.'),
        findsOneWidget,
      );
      expect(find.byType(AndroidView), findsNothing);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('caption uploads and renders continue polling until completion', (
    tester,
  ) async {
    final operations = <String>[];
    final api = workflowApi((request) async {
      final data = jsonDecode(request.body) as Map;
      operations.add('${data['operation']}');
      if (data['operation'] == 'describe') {
        return {
          'title': 'Captions',
          'fields': [],
          'data': [
            {'id': 7, 'title': 'My captions', 'status': 'uploading'},
          ],
        };
      }
      return {
        'data': [
          {
            'id': 7,
            'title': 'My captions',
            'status': operations.length == 2 ? 'rendering' : 'completed',
          },
        ],
      };
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ExtensionWorkflowScreen(
            module: const {'id': 'web:captions'},
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('uploading'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('rendering'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(find.text('completed'), findsOneWidget);
    await tester.pump(const Duration(seconds: 16));
    expect(operations, ['describe', 'status', 'status']);
    await tester.pumpWidget(const SizedBox());
  });
}
