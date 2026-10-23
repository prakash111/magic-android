import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/auth/login_screen.dart';
import 'package:magicai_mobile/screens/extension_workflow_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_settings_screen.dart';
import 'package:magicai_mobile/screens/native_workspace_screen.dart';
import 'package:magicai_mobile/screens/splash_screen.dart';
import 'package:magicai_mobile/services/api_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/theme/theme_settings.dart';

import 'mobile_api_test.dart' show MemorySecureStore, jsonResponse, license;
import 'native_screen_test.dart' show nativeApi;

Widget app(Widget widget) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(body: widget),
);
Map<String, dynamic> workspace(
  String kind, {
  List data = const [],
  List modules = const [],
  Map<String, dynamic> extra = const {},
}) => {
  'schema_version': 1,
  'kind': kind,
  'module': {'title': kind},
  'data': data,
  'modules': modules,
  'current_page': 1,
  'last_page': 1,
  ...extra,
};
const module = {
  'id': 'web:test',
  'title': 'Workspace',
  'category': 'Studio',
  'route_type': 'schema',
  'available': true,
};
List<Map<String, dynamic>> metrics() => [
  for (final label in [
    'Total Invoiced',
    'Outstanding Balance',
    'Paid',
    'Overdue',
  ])
    {'label': label, 'value': 0, 'currency': 'USD'},
];

class PendingStartup extends MobileApi {
  final started = Completer<void>();
  @override
  Future<void> bootstrap() => started.future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'login visibility follows admin flags on initial load and resume',
    (tester) async {
      var github = false;
      var optionCalls = 0;
      final api = MobileApi(
        store: MemorySecureStore(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/license')) {
            return jsonResponse(license());
          }
          expectSync(request.headers.containsKey('Authorization'), isFalse);
          optionCalls++;
          expectSync(request.url.path, '/api/mobile/v1/auth/options');
          return jsonResponse({
            'provider_status': [
              {
                'id': 'google',
                'label': 'Google',
                'enabled': !github,
                'configured': true,
                'available': !github,
              },
              {
                'id': 'facebook',
                'label': 'Facebook',
                'enabled': true,
                'configured': false,
                'available': false,
                'message': 'Setup required',
              },
              {
                'id': 'github',
                'label': 'GitHub',
                'enabled': github,
                'configured': true,
                'available': github,
              },
            ],
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: LoginScreen(onThemeChanged: (_) {}, api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Login with Google'), findsOneWidget);
      expect(find.text('Login with Facebook'), findsOneWidget);
      expect(find.text('Login with Github'), findsNothing);
      expect(find.text('Setup required'), findsNothing);
      github = true;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Login with Google'), findsNothing);
      expect(optionCalls, 2);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Login with Github'), findsOneWidget);
    },
  );

  testWidgets(
    'email login shows no social buttons or divider when no provider is usable',
    (tester) async {
      final api = MobileApi(
        store: MemorySecureStore(),
        client: MockClient(
          (request) async => jsonResponse(
            request.url.path.endsWith('/license')
                ? license()
                : {
                    'provider_status': [
                      {
                        'id': 'google',
                        'label': 'Google',
                        'available': false,
                        'enabled': false,
                      },
                    ],
                  },
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: LoginScreen(onThemeChanged: (_) {}, api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Continue with'), findsNothing);
      expect(find.text('or sign in with email'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Setup required'), findsNothing);
    },
  );

  test('diagnostic provider lists follow enabled flags and reject unknown providers', () async {
    final api = MobileApi(
      store: MemorySecureStore(),
      client: MockClient(
        (request) async => jsonResponse(
          request.url.path.endsWith('/license')
              ? license()
              : {
                  'provider_status': [
                    {
                      'id': 'google',
                      'enabled': false,
                      'configured': true,
                      'available': true,
                    },
                    {
                      'id': 'facebook',
                      'enabled': true,
                      'configured': false,
                      'available': true,
                    },
                    {
                      'id': 'unknown',
                      'enabled': true,
                      'configured': true,
                      'available': true,
                    },
                  ],
                },
        ),
      ),
    );
    expect(
      (await ApiService.getSocialLoginOptions(client: api)).map((p) => p['id']),
      ['facebook'],
    );
  });

  testWidgets('splash uses friendly progress and safe retry messages', (
    tester,
  ) async {
    final api = PendingStartup();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: SplashScreen(onThemeChanged: (_) {}, api: api),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    expect(find.text('Preparing your workspace…'), findsOneWidget);
    expect(find.textContaining('Verifying license'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.started.completeError(
      const ApiFailure('Internal token handshake detail'),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Internal token'), findsNothing);
    expect(
      find.textContaining('Unable to load your workspace'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'invoices show four KPI cards and an illustrated empty state without raw column links',
    (tester) async {
      final api = nativeApi(
        (path, body) async => workspace(
          'invoices',
          extra: {
            'metrics': metrics(),
            'currency': 'USD',
            'currencies': ['USD'],
          },
        ),
      );
      await tester.pumpWidget(
        app(NativeWorkspaceScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      for (final label in [
        'Total Invoiced',
        'Outstanding Balance',
        'Paid',
        'Overdue',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.text('No invoices yet'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_outlined), findsWidgets);
      expect(find.text(r'$0.00'), findsNWidgets(4));
      for (final text in [
        '0',
        r'$ 0',
        'Date',
        'Due Date',
        'Total',
        'Status',
        'Some tools in this workspace are not available in the app yet. Available controls appear below.',
      ]) {
        expect(find.text(text), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'invoice records have integrated status totals and detail sheets',
    (tester) async {
      final api = nativeApi(
        (path, body) async => workspace(
          'invoices',
          data: [
            {
              'id': 1,
              'number': 'INV-00001',
              'customer': 'Acme',
              'total': 125,
              'balance': 25,
              'currency': 'USD',
              'status': 'sent',
              'issue_date': '2027-01-01',
              'due_date': '2027-01-10',
            },
          ],
          extra: {
            'metrics': metrics(),
            'currency': 'USD',
            'currencies': ['USD'],
          },
        ),
      );
      await tester.pumpWidget(
        app(NativeWorkspaceScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('INV-00001'));
      await tester.tap(find.text('INV-00001'));
      await tester.pumpAndSettle();
      expect(find.text(r'Balance due: $25.00'), findsOneWidget);
      expect(find.text(r'Total: $125.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'company creation opens separately and saves a real native record',
    (tester) async {
      var saved = false;
      Map? submitted;
      final api = nativeApi((path, body) async {
        if (path == '/native/records') {
          submitted = body;
          saved = true;
          return {'message': 'Saved'};
        }
        return workspace(
          'companies',
          data: saved
              ? [
                  {
                    'id': 1,
                    'name': 'Acme',
                    'industry': 'Software',
                    'address': 'Studio street',
                    'city': 'Kathmandu',
                  },
                ]
              : [],
        );
      });
      await tester.pumpWidget(
        app(NativeWorkspaceScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('New company'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Company name'),
        'Acme',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Industry'),
        'Software',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Save company').hitTestable(),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save company'));
      await tester.pumpAndSettle();
      expect(submitted!['kind'], 'company');
      expect(submitted!['inputs']['name'], 'Acme');
      expect(submitted!['request_id'], isNotEmpty);
      expect(find.text('Acme'), findsOneWidget);
      expect(find.text('Software'), findsOneWidget);
      expect(find.text('Studio street, Kathmandu'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.textContaining('Contacts:'), findsNothing);
      expect(find.textContaining('Actions:'), findsNothing);
    },
  );

  testWidgets(
    'campaign audience and delete action stay within a full-width card',
    (tester) async {
      var deleted = false;
      Map? submitted;
      final api = nativeApi((path, body) async {
        if (path == '/native/records') {
          submitted = body;
          deleted = true;
          return {};
        }
        return workspace(
          'campaigns',
          data: deleted
              ? []
              : [
                  {
                    'id': 8,
                    'name': 'Product launch',
                    'target_audience': 'Small business owners',
                  },
                ],
        );
      });
      await tester.pumpWidget(
        app(NativeWorkspaceScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Small business owners'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      final action = find.byTooltip('Delete campaign');
      expect(
        find.ancestor(of: action, matching: find.byType(Card)),
        findsOneWidget,
      );
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(submitted!['operation'], 'delete');
      expect(submitted!['record_id'], 8);
      expect(find.text('No campaigns yet'), findsOneWidget);
    },
  );

  testWidgets(
    'BlogPilot calendar displays an interactive agenda and sends UTC day filters',
    (tester) async {
      Map? query;
      final queries = <Map>[];
      final api = nativeApi((path, body) async {
        query = body;
        queries.add(body);
        return workspace(
          'blog',
          data: [
            {
              'id': 1,
              'title': 'Planned article',
              'agent': 'Editorial agent',
              'status': 'scheduled',
              'scheduled_at': '2027-01-02T09:00:00Z',
            },
          ],
          extra: {'calendar': true, 'show_agents': false, 'agents': []},
        );
      });
      await tester.pumpWidget(
        app(NativeWorkspaceScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.ensureVisible(find.text('Planned article'));
      expect(find.text('Editorial agent'), findsOneWidget);
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      calendar.onDateChanged(DateTime(2027, 1, 2));
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Show all dates'), findsOneWidget);
      expect(
        query,
        contains('from'),
        reason:
            'queries=$queries errors=${find.textContaining('Unable').evaluate().map((e) => (e.widget as Text).data).toList()}',
      );
      expect(DateTime.parse(query!['from']).isUtc, isTrue);
      expect(
        DateTime.parse(query!['until'])
            .difference(DateTime.parse(query!['from']))
            .inHours,
        24,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unconnected BlogPilot calendars show a polished agenda placeholder',
    (tester) async {
      final api = nativeApi(
        (path, body) async => workspace(
          'blog',
          extra: {'calendar': true, 'show_agents': false, 'agents': []},
        ),
      );
      await tester.pumpWidget(
        app(NativeWorkspaceScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('A clear calendar, a fresh start'));
      expect(find.byType(WorkspaceEmptyState), findsOneWidget);
      expect(find.text('Agents'), findsNothing);
      expect(find.byType(CalendarDatePicker), findsOneWidget);
    },
  );

  testWidgets(
    'unknown modules never render raw HTML metadata or loading labels',
    (tester) async {
      final api = nativeApi(
        (path, body) async => path == '/native/screen'
            ? {
                'schema_version': 2,
                'components': [
                  {
                    'type': 'form',
                    'action': 'valid-server-action',
                    'title': 'Save item',
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
              }
            : workspace(
                'overview',
                data: [
                  {
                    'title': 'Loading models...',
                    'Date': 0,
                    'Product': 'Debug',
                    'Prompt': 'Raw',
                  },
                ],
              ),
      );
      await tester.pumpWidget(
        app(NativeModuleRegistry.build(module, api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Loading models...'), findsNothing);
      expect(find.text('Debug'), findsNothing);
      expect(find.text('Raw'), findsNothing);
      expect(find.textContaining('Some tools in this workspace'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings open the central native account view without the web action error',
    (tester) async {
      final calls = <String>[];
      final api = nativeApi((path, body) async {
        calls.add(path);
        return path == '/auth/profile'
            ? {'name': 'Prakash', 'email': 'test@example.com'}
            : workspace('settings');
      });
      ThemeMode? changed;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ThemeSettings(
            mode: ThemeMode.dark,
            onChanged: (mode) => changed = mode,
            child: Scaffold(
              body: NativeWorkspaceScreen(module: module, api: api),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NativeSettingsScreen), findsOneWidget);
      expect(find.text('test@example.com'), findsOneWidget);
      expect(find.textContaining('outside the selected module'), findsNothing);
      expect(calls, ['/native/workspace', '/auth/profile']);
      await tester.ensureVisible(find.text('Dark'));
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light').last);
      await tester.pumpAndSettle();
      expect(changed, ThemeMode.light);
    },
  );

  for (final kind in [
    'invoices',
    'companies',
    'campaigns',
    'blog',
    'photoshoot',
    'overview',
  ]) {
    testWidgets('$kind keeps its layout within a small keyboard viewport', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final api = nativeApi(
        (path, body) async => path == '/native/screen'
            ? {'schema_version': 2, 'components': []}
            : workspace(
                kind,
                extra: {
                  'metrics': metrics(),
                  'currency': 'USD',
                  'currencies': ['USD'],
                  'calendar': kind == 'blog',
                  'show_agents': false,
                },
              ),
      );
      await tester.pumpWidget(
        app(NativeWorkspaceScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('workspace failures have finite loading and native retry', (
    tester,
  ) async {
    final pending = Completer<dynamic>();
    final api = nativeApi((path, body) async => pending.future);
    await tester.pumpWidget(
      app(NativeWorkspaceScreen(module: module, api: api)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete(workspace('overview'));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'image workflows use real native ratio chips style selectors and prompt inputs',
    (tester) async {
      Map? submitted;
      final api = nativeApi((path, body) async {
        if (body['operation'] == 'generate') {
          submitted = body;
          return {'data': [], 'message': 'Submitted'};
        }
        return {
          'title': 'Realtime image',
          'data': [],
          'fields': [
            {
              'name': 'prompt',
              'label': 'Describe your image',
              'type': 'text',
              'required': true,
            },
            {
              'name': 'model',
              'label': 'AI model',
              'type': 'select',
              'read_only': true,
              'options': [
                {'value': 'flux', 'label': 'FLUX.1 Schnell'},
              ],
            },
            {
              'name': 'style',
              'label': 'Image style',
              'type': 'select',
              'options': [
                {'value': 'none', 'label': 'Natural'},
                {'value': 'cinematic', 'label': 'Cinematic'},
              ],
            },
            {
              'name': 'ratio',
              'label': 'Aspect ratio',
              'type': 'select',
              'options': [
                for (final value in ['1:1', '9:16', '16:9'])
                  {'value': value, 'label': value},
              ],
            },
          ],
        };
      });
      await tester.pumpWidget(
        app(ExtensionWorkflowScreen(module: module, api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ChoiceChip, '9:16'), findsOneWidget);
      expect(find.text('Loading models...'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Describe your image'),
        'A cinematic product image',
      );
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, '9:16'));
      await tester.tap(find.widgetWithText(ChoiceChip, '9:16'));
      await tester.ensureVisible(find.text('Generate'));
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(submitted!['inputs']['ratio'], '9:16');
      expect(submitted!['inputs']['prompt'], 'A cinematic product image');
      expect(submitted!['inputs']['model'], 'flux');
      expect(tester.takeException(), isNull);
    },
  );
}
