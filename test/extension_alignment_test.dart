import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/native_extension_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/native_extension_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

Map<String, dynamic> module(String kind) => {
  'id': 'test:$kind',
  'route_type': kind,
  'title': 'Workspace',
};

Widget app(String kind, MobileApi api, {int? conversationId}) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(
    resizeToAvoidBottomInset: true,
    appBar: AppBar(title: const Text('Workspace')),
    body: NativeExtensionScreen(
      module: module(kind),
      api: api,
      conversationId: conversationId,
    ),
  ),
);

Finder input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Map<String, dynamic> settings() => {
  'telegram': {'configured': false},
  'providers': ['twilio'],
  'whatsapp': {
    'whatsapp_provider': 'twilio',
    'whatsapp_sid': 'AC-existing',
    'whatsapp_phone': '+15550101',
    'whatsapp_environment': 'sandbox',
    'token_configured': true,
  },
};

Map<String, dynamic> deals() => {
  'metrics': [
    {'label': 'Total Deals', 'value': 2},
    {'label': 'Pipeline Value', 'value': 300, 'currency': 'USD'},
    {'label': 'Won Deals', 'value': 1},
    {'label': 'Win Rate', 'value': 50, 'unit': '%'},
  ],
  'currency': 'USD',
  'currencies': ['USD', 'EUR'],
  'stages': [
    {'id': 1, 'name': 'Lead', 'count': 1},
    {'id': 2, 'name': 'Won', 'count': 1},
  ],
  'contacts': [],
  'companies': [],
  'data': [
    {
      'id': 7,
      'title': 'Launch opportunity',
      'value': 300,
      'currency': 'USD',
      'contact': 'Asha',
      'company': 'Acme',
      'close_date': '2026-12-01',
      'stage_id': 1,
    },
  ],
  'current_page': 1,
  'last_page': 1,
};

void main() {
  test('all aligned route types use the native JSON adapter', () {
    final api = nativeApi((_, body) async => {});
    for (final kind in [
      'marketing_settings',
      'marketing_dashboard',
      'marketing_inbox',
      'marketing_campaigns',
      'deal_pipeline',
      'agent_analytics',
      'ugc_studio',
      'ugc_creator',
    ]) {
      expect(
        NativeModuleRegistry.build(module(kind), api: api),
        isA<NativeExtensionScreen>(),
      );
    }
  });

  testWidgets(
    'Telegram settings submit the real access_token field with a concealed input',
    (tester) async {
      Map? submitted;
      final api = nativeApi((path, body) async {
        expect(path, '/native/extension');
        if (body['operation'] != 'load') submitted = Map.from(body);
        return settings();
      });
      await tester.pumpWidget(app('marketing_settings', api));
      await tester.pumpAndSettle();
      final field = input('Access Token *');
      await tester.enterText(field, 'new-telegram-token');
      expect(tester.widget<TextField>(field).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show or hide token').first);
      await tester.pump();
      expect(tester.widget<TextField>(field).obscureText, isFalse);
      await tester.tap(find.text('Save Telegram settings'));
      await tester.pumpAndSettle();
      expect(submitted?['inputs'], {'access_token': 'new-telegram-token'});
      expect(submitted?['operation'], 'save_telegram');
      expect(submitted?['request_id'], isNotEmpty);
    },
  );

  testWidgets(
    'Twilio settings preserve blank tokens and map LIVE to production',
    (tester) async {
      Map? submitted;
      final api = nativeApi((_, body) async {
        if (body['operation'] != 'load') submitted = Map.from(body);
        return settings();
      });
      await tester.pumpWidget(app('marketing_settings', api));
      await tester.pumpAndSettle();
      final environment = find.byWidgetPredicate(
        (w) =>
            w is DropdownButtonFormField<String> &&
            w.decoration.labelText == 'Environment',
      );
      await reveal(tester, environment);
      await tester.tap(environment);
      await tester.pumpAndSettle();
      await tester.tap(find.text('LIVE').last);
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Save WhatsApp settings'));
      await tester.tap(find.text('Save WhatsApp settings'));
      await tester.pumpAndSettle();
      expect(submitted?['operation'], 'save_whatsapp');
      expect(submitted?['inputs']['whatsapp_environment'], 'production');
      expect(submitted?['inputs']['whatsapp_sid'], 'AC-existing');
      expect(submitted?['inputs']['whatsapp_token'], '');
      expect(submitted?['inputs']['whatsapp_provider'], 'twilio');
    },
  );

  testWidgets(
    'Inbox loads a real thread and sends a reply with the selected conversation id',
    (tester) async {
      final calls = <Map>[];
      final api = nativeApi((_, body) async {
        calls.add(Map.from(body));
        if (body['operation'] == 'send_message') {
          return {'message': 'Message sent.'};
        }
        if (body['record_id'] != null) {
          return {
            'data': [
              {
                'id': 8,
                'role': 'user',
                'message': 'Can you help?',
                'created_at': '2026-10-18T10:00:00Z',
              },
            ],
            'current_page': 1,
            'last_page': 1,
          };
        }
        return {
          'data': [
            {
              'id': 4,
              'name': 'Asha',
              'last_message': 'Can you help?',
              'updated_at': '2026-10-18T10:00:00Z',
            },
          ],
        };
      });
      await tester.pumpWidget(app('marketing_inbox', api));
      await tester.pumpAndSettle();
      expect(find.text('Search for chats...'), findsOneWidget);
      await tester.tap(find.text('Asha'));
      await tester.pumpAndSettle();
      expect(find.text('Can you help?').last, findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'Of course');
      await tester.tap(find.byTooltip('Send reply'));
      await tester.pumpAndSettle();
      final sent = calls.singleWhere(
        (body) => body['operation'] == 'send_message',
      );
      expect(sent['record_id'], 4);
      expect(sent['inputs'], {'message': 'Of course'});
    },
  );

  testWidgets('Inbox search uses the API query rather than parsed page text', (
    tester,
  ) async {
    final calls = <Map>[];
    final api = nativeApi((_, body) async {
      calls.add(Map.from(body));
      return {'data': []};
    });
    await tester.pumpWidget(app('marketing_inbox', api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Asha');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(calls.last['query'], 'Asha');
    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('Deals show metric cards and filter by stage with count chips', (
    tester,
  ) async {
    final calls = <Map>[];
    final api = nativeApi((_, body) async {
      calls.add(Map.from(body));
      return deals();
    });
    await tester.pumpWidget(app('deal_pipeline', api));
    await tester.pumpAndSettle();
    expect(find.byType(NativeMetricGrid), findsOneWidget);
    expect(find.text('Pipeline Value'), findsOneWidget);
    final chips = find.byType(ChoiceChip);
    expect(chips, findsNWidgets(3));
    final won = find.byWidgetPredicate(
      (w) => w is ChoiceChip && (w.label as Text).data!.contains('Won'),
    );
    await reveal(tester, won);
    await tester.tap(won);
    await tester.pumpAndSettle();
    expect(calls.last['stage_id'], 2);
    await reveal(tester, find.text('Launch opportunity'));
    expect(find.text('Asha · Acme'), findsOneWidget);
    expect(find.text('Expected close: 2026-12-01'), findsOneWidget);
  });

  testWidgets('Deals move actions submit the exact deal and stage ids', (
    tester,
  ) async {
    Map? submitted;
    final api = nativeApi((_, body) async {
      if (body['operation'] == 'move_deal') {
        submitted = Map.from(body);
        return {'message': 'Deal saved.'};
      }
      return deals();
    });
    await tester.pumpWidget(app('deal_pipeline', api));
    await tester.pumpAndSettle();
    await reveal(tester, find.byType(PopupMenuButton<int>));
    await tester.tap(find.byType(PopupMenuButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Won').last);
    await tester.pumpAndSettle();
    expect(submitted?['record_id'], 7);
    expect(submitted?['inputs'], {'stage_id': 2});
  });

  testWidgets(
    'Marketing overview switches real KPI periods without raw metric dumps',
    (tester) async {
      final api = nativeApi(
        (_, _) async => {
          'metrics': [
            {'label': 'All Campaigns', 'value': 1},
            {'label': 'Scheduled Campaigns', 'value': 0},
            {'label': 'Published Campaigns', 'value': 1},
            {'label': 'Total Contacts', 'value': 3},
          ],
          'periods': {
            'today': [
              {'label': 'All Campaigns', 'value': 1},
            ],
            'last_7_days': [
              {'label': 'All Campaigns', 'value': 7},
            ],
          },
          'data': [],
        },
      );
      await tester.pumpWidget(app('marketing_dashboard', api));
      await tester.pumpAndSettle();
      expect(find.text('Marketing overview'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(find.text('Last 7 Days'));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsOneWidget);
      expect(find.text('1'), findsNothing);
      expect(find.text('No campaigns yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Analytics use named metric cards and measured trends', (
    tester,
  ) async {
    final api = nativeApi(
      (_, body) async => {
        'metrics': [
          {'label': 'Total Ideas Generated', 'value': 12, 'change': 3},
          {'label': 'Posts Published This Month', 'value': 4, 'change': -1},
          {'label': 'Engagement Rate', 'value': 2.5, 'unit': '%'},
        ],
      },
    );
    await tester.pumpWidget(app('agent_analytics', api));
    await tester.pumpAndSettle();
    expect(find.text('Total Ideas Generated'), findsOneWidget);
    expect(find.text('2.5%'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
    expect(find.byIcon(Icons.trending_down), findsOneWidget);
  });

  testWidgets('Studio has creator cards and structured project history', (
    tester,
  ) async {
    final api = nativeApi(
      (_, body) async => {
        'sources': [
          {
            'key': 'ugc-factory',
            'label': 'UGC Factory',
            'description': 'Create a presenter video',
            'module': module('ugc_creator'),
          },
        ],
        'data': [
          {
            'id': 2,
            'title': 'Product launch',
            'source_label': 'UGC Factory',
            'status': 'queued',
            'created_at': '2026-10-18T10:00:00Z',
          },
        ],
      },
    );
    await tester.pumpWidget(app('ugc_studio', api));
    await tester.pumpAndSettle();
    expect(find.text('Create a video project'), findsOneWidget);
    expect(find.text('Project history'), findsOneWidget);
    expect(find.text('Product launch'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
  });

  testWidgets(
    'Studio refreshes pending projects through their native status adapter',
    (tester) async {
      Map? submitted;
      final api = nativeApi((_, body) async {
        if (body['operation'] == 'refresh_project') {
          submitted = Map.from(body);
          return {'message': 'Project refreshed.'};
        }
        return {
          'sources': [],
          'data': [
            {
              'id': 9,
              'source': 'ugc-factory',
              'title': 'Pending project',
              'status': 'processing',
            },
          ],
        };
      });
      await tester.pumpWidget(app('ugc_studio', api));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Refresh status'));
      await tester.tap(find.text('Refresh status'));
      await tester.pumpAndSettle();
      expect(submitted?['record_id'], 9);
      expect(submitted?['source'], 'ugc-factory');
    },
  );

  testWidgets(
    'Campaign composer targets owned audiences and the native scheduler API',
    (tester) async {
      Map? submitted;
      final api = nativeApi((_, body) async {
        if (body['operation'] == 'save_campaign') {
          submitted = Map.from(body);
          return {'message': 'Saved'};
        }
        return {
          'channel': 'telegram',
          'contacts': [
            {'id': 3, 'name': 'Launch audience'},
          ],
          'data': [],
        };
      });
      await tester.pumpWidget(app('marketing_campaigns', api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'Launch');
      await tester.enterText(find.byType(TextField).at(2), 'New collection');
      await reveal(tester, find.text('Launch audience'));
      await tester.tap(find.text('Launch audience'));
      await reveal(tester, find.text('Schedule campaign'));
      await tester.tap(find.text('Schedule campaign'));
      await tester.pumpAndSettle();
      expect(submitted?['inputs']['name'], 'Launch');
      expect(submitted?['inputs']['contacts'], [3]);
      expect(
        DateTime.parse(submitted?['inputs']['scheduled_at']).isUtc,
        isTrue,
      );
    },
  );

  testWidgets('backend errors terminate loading and offer retry', (
    tester,
  ) async {
    final api = nativeApi(
      (_, body) async => throw const ApiFailure('Connection unavailable'),
    );
    await tester.pumpWidget(app('marketing_inbox', api));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Connection unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  test('the adapter rejects malformed response contracts', () async {
    final api = nativeApi((_, body) async => ['unexpected']);
    await expectLater(
      NativeExtensionService(api, 'inbox').call('load'),
      throwsA(isA<ApiFailure>()),
    );
  });

  testWidgets('native workspaces handle a narrow keyboard-reduced viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final responses = {
      'marketing_settings': settings(),
      'marketing_inbox': {'data': []},
      'deal_pipeline': deals(),
      'marketing_campaigns': {
        'channel': 'whatsapp',
        'contacts': [],
        'data': [],
      },
      'agent_analytics': {
        'metrics': [
          {'label': 'Posts Published This Month', 'value': 0},
        ],
      },
      'ugc_studio': {'sources': [], 'data': []},
      'ugc_creator': {
        'fields': [
          {'name': 'title', 'label': 'Title', 'type': 'text'},
        ],
        'data': [],
      },
    };
    for (final entry in responses.entries) {
      await tester.pumpWidget(const SizedBox());
      final api = nativeApi((_, body) async => entry.value);
      await tester.pumpWidget(app(entry.key, api));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: entry.key);
    }
  });
}
