import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/home_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_workspace_screen.dart';
import 'package:magicai_mobile/screens/native_contacts_screen.dart';
import 'package:magicai_mobile/screens/native_automation_screen.dart';
import 'package:magicai_mobile/screens/native_creative_screen.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;

MobileApi nativeApi(Future<dynamic> Function(String, Map) response) {
  final store = MemorySecureStore()
    ..values.addAll({
      'access_token': 'private-token',
      'instance_hash': 'a' * 64,
    });
  return MobileApi(
    store: store,
    client: MockClient((request) async {
      if (request.url.path.endsWith('/license')) return jsonResponse(license());
      expectSync(request.url.host, 'magicai.example.test');
      expectSync(request.headers['Authorization'], 'Bearer private-token');
      return jsonResponse(
        await response(
          request.url.path.replaceFirst('/api/mobile/v1', '') +
              (request.url.hasQuery ? '?${request.url.query}' : ''),
          request.body.isEmpty ? {} : jsonDecode(request.body) as Map,
        ),
      );
    }),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'documents use the selected API instance and retry a failed load',
    (tester) async {
      var calls = 0;
      final api = nativeApi((path, _) async {
        expect(path, '/documents?page=1&per_page=20');
        if (++calls == 1) throw const ApiFailure('Please retry documents.');
        return {'data': null};
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeModuleRegistry.build({
              'route_type': 'documents',
            }, api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('No saved documents yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native dashboards handle null collections and nonnumeric chart values without build exceptions',
    (tester) async {
      final api = nativeApi(
        (_, _) async => {
          'stats': null,
          'chart': [
            {'value': 'Infinity', 'label': 'Mon'},
            {'value': null, 'label': 'Tue'},
          ],
          'shortcuts': null,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeDashboard(
              module: const {'id': 'web:crm_dashboard'},
              api: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your work, at a glance'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('native route registry maps named screens and future modules use the schema renderer', () {
    final api = nativeApi((_, body) async => {});
    expect(
      NativeModuleRegistry.build({'route_type': 'contacts'}, api: api),
      isA<NativeContactsScreen>(),
    );
    expect(
      NativeModuleRegistry.build({'route_type': 'creative_suite'}, api: api),
      isA<NativeCreativeScreen>(),
    );
    expect(
      NativeModuleRegistry.build({'route_type': 'crm_chat'}, api: api),
      isA<ServerChatScreen>().having(
        (screen) => screen.crm,
        'CRM context',
        true,
      ),
    );
    expect(
      NativeModuleRegistry.build({'route_type': 'dashboard'}, api: api),
      isA<NativeDashboard>(),
    );
    expect(
      NativeModuleRegistry.build({'route_type': 'future_extension'}, api: api),
      isA<NativeWorkspaceScreen>(),
    );
  });

  testWidgets(
    'Explore opens native contacts while keeping the bottom navigation visible',
    (tester) async {
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
      final api = nativeApi(
        (path, body) async => path == '/config'
            ? {
                'schema_version': 1,
                'app': 'magicai',
                'navigation': [
                  {'id': 'home', 'label': 'Home', 'component': 'dashboard'},
                  {
                    'id': 'explore',
                    'label': 'Explore',
                    'component': 'workspace',
                  },
                  {'id': 'account', 'label': 'Account', 'component': 'account'},
                ],
                'modules': [
                  {
                    'id': 'web:crm_contacts',
                    'title': 'Contacts',
                    'description': 'CRM',
                    'category': 'Work',
                    'available': true,
                    'route_type': 'contacts',
                  },
                ],
                'tools': [],
                'credits': {'words': 12, 'images': 3, 'plan': 'Test'},
                'user': {'name': 'Asha'},
              }
            : {
                'data': [
                  {
                    'id': 1,
                    'first_name': 'Asha',
                    'last_name': 'Test',
                    'status': 'active',
                    'initials': 'AT',
                  },
                ],
                'current_page': 1,
                'last_page': 1,
                'total': 1,
              },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: HomeScreen(onThemeChanged: (_) {}, api: api),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Contacts'));
      await tester.pumpAndSettle();
      expect(find.byType(NativeContactsScreen), findsOneWidget);
      expect(find.text('Asha Test'), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(calls, isNot(contains('openWorkspace')));
      expect(calls, isNot(contains('openUrl')));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'server-defined forms validate and submit opaque actions in native UI',
    (tester) async {
      Map? submitted;
      final api = nativeApi((path, body) async {
        if (body['action'] != null) submitted = body;
        return {
          'schema_version': 2,
          'components': [
            {'type': 'heading', 'text': 'New server feature'},
            {
              'type': 'form',
              'title': 'Save record',
              'action': 'opaque-token',
              'fields': [
                {
                  'name': 'name',
                  'label': 'Name',
                  'type': 'text',
                  'required': true,
                },
              ],
            },
          ],
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeSchemaScreen(
              module: const {'id': 'web:new-feature'},
              api: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save record'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Asha');
      await tester.tap(find.text('Save record'));
      await tester.pumpAndSettle();
      expect(submitted?['module_id'], 'web:new-feature');
      expect(submitted?['action'], 'opaque-token');
      expect(submitted?['inputs']['name'], 'Asha');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'CRM assistant displays live model selection and native suggestion chips',
    (tester) async {
      final api = nativeApi(
        (path, body) async => switch (path) {
          '/chat/options?context=crm' => {
            'personas': [
              {'id': 0, 'name': 'CRM assistant'},
            ],
            'models': [
              {'id': 'test-model', 'title': 'Enabled model'},
            ],
          },
          _ => [],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: ServerChatScreen(crm: true, api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Pipeline summary'), findsOneWidget);
      expect(find.text('Overdue tasks'), findsOneWidget);
      expect(find.text('Enabled model'), findsOneWidget);
      expect(find.byTooltip('Voice input'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native creative studio renders server templates and project history',
    (tester) async {
      final api = nativeApi(
        (path, body) async => path == '/native/creative/templates'
            ? [
                {
                  'id': 'campaign',
                  'title': 'Campaign template',
                  'prompt': 'An indigo campaign background',
                  'background': '#131620',
                },
              ]
            : {'data': [], 'current_page': 1, 'last_page': 1},
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: NativeCreativeScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Start with AI Image'), findsOneWidget);
      await tester.tap(find.text('Start with AI Template'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Campaign template'));
      await tester.pumpAndSettle();
      expect(find.text('An indigo campaign background'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native automation requires connected accounts and shows real empty state',
    (tester) async {
      final api = nativeApi(
        (path, body) async => {
          'data': [],
          'accounts': [],
          'current_page': 1,
          'last_page': 1,
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: NativeAutomationScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create automation'), findsOneWidget);
      expect(
        find.textContaining('Connect a supported social account'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'native forms preserve selected values when saving an existing record',
    (tester) async {
      Map<String, String>? submitted;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeSchemaForm(
              definition: const {
                'title': 'Save',
                'fields': [
                  {
                    'name': 'status',
                    'label': 'Status',
                    'type': 'select',
                    'required': true,
                    'value': 'active',
                    'options': [
                      {'value': 'active', 'label': 'Active'},
                      {'value': 'inactive', 'label': 'Inactive'},
                    ],
                  },
                  {
                    'name': 'favorite',
                    'label': 'Favorite',
                    'type': 'checkbox',
                    'value': '1',
                  },
                ],
              },
              busy: false,
              submit: (inputs, attachments) async {
                submitted = inputs;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Active'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(submitted, {'status': 'active', 'favorite': '1'});
      expect(tester.takeException(), isNull);
    },
  );
}
