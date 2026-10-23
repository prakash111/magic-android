import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_parity_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

Map<String, dynamic> agentData() => {
  'data': [],
  'templates': [
    {
      'key': 'crm_capture_lead',
      'label': 'Capture Lead from Message',
      'description': 'Create a CRM contact from a message.',
      'tags': ['crm'],
      'config': {
        'name': 'Capture Lead from Message',
        'trigger_type': 'channel_message',
        'steps': [
          {
            'type': 'ai_call',
            'config': {
              'system_prompt': 'Extract contact details',
              'inject_memory': false,
            },
          },
        ],
      },
    },
    {
      'key': 'daily_digest',
      'label': 'Daily Pipeline Digest',
      'description': 'Send the pipeline digest every morning.',
      'tags': ['crm', 'reports'],
      'config': {
        'name': 'Daily Pipeline Digest',
        'trigger_type': 'schedule',
        'trigger_config': {'cron': '0 9 * * *'},
        'steps': [
          {
            'type': 'generate_report',
            'config': {'date_range': 'today'},
          },
        ],
      },
    },
  ],
  'actions': {
    'AI': [
      {
        'key': 'ai_call',
        'label': 'AI response',
        'config_schema': {
          'type': 'object',
          'properties': {
            'system_prompt': {'type': 'string'},
            'inject_memory': {'type': 'boolean'},
          },
        },
      },
    ],
  },
  'channels': [],
};

Widget parityApp(
  String kind,
  MobileApi api, {
  String? id,
  double scale = 1,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: NativeModuleScreen(
    module: {
      'id': id ?? 'test:$kind',
      'route_type': kind,
      'title': 'Workspace',
    },
    api: api,
  ),
);

Finder input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> press(WidgetTester tester, Finder finder) async {
  tester.binding.focusManager.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test('new workflow route types use JSON native adapters', () {
    final api = nativeApi((_, _) async => {});
    for (final kind in [
      'ai_agents',
      'crm_tasks',
      'agent_posts',
      'fashion_settings',
    ]) {
      expect(
        NativeModuleRegistry.build({
          'id': 'test',
          'route_type': kind,
        }, api: api),
        isA<NativeParityScreen>(),
      );
    }
  });

  testWidgets(
    'Add Agent opens searchable categorized templates and saves the selected backend workflow',
    (tester) async {
      Map? saved;
      final api = nativeApi((path, body) async {
        expect(path, '/native/extension');
        if (body['operation'] == 'save_agent') {
          saved = body;
          return {
            'status': 'success',
            'data': {'id': 12},
          };
        }
        return agentData();
      });
      await tester.pumpWidget(parityApp('ai_agents', api));
      await tester.pumpAndSettle();
      await press(tester, find.text('New Agent'));
      expect(
        find.descendant(
          of: find.byType(AgentTemplateSelector),
          matching: find.text('Add Agent'),
        ),
        findsOneWidget,
      );
      expect(find.text('Start From Scratch'), findsOneWidget);
      await tester.enterText(input('Search templates'), 'daily');
      await tester.pumpAndSettle();
      expect(find.text('Capture Lead from Message'), findsNothing);
      await press(tester, find.text('Daily Pipeline Digest'));
      expect(find.text('Set up agent'), findsOneWidget);
      expect(find.text('0 9 * * *'), findsOneWidget);
      await tester.enterText(input('Agent name'), 'Morning sales report');
      await press(tester, find.text('Save agent'));
      expect(saved?['module_id'], 'test:ai_agents');
      expect(saved?['inputs']['name'], 'Morning sales report');
      expect(saved?['inputs']['steps'][0]['type'], 'generate_report');
      expect(saved?['request_id'], isNotEmpty);
      expect(find.text('Your agents'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'template favorites persist in tenant storage and categories filter without navigation loops',
    (tester) async {
      final api = nativeApi((_, _) async => agentData());
      await tester.pumpWidget(parityApp('ai_agents', api));
      await tester.pumpAndSettle();
      await press(tester, find.text('New Agent'));
      await press(tester, find.byTooltip('Favorite template').first);
      await press(tester, find.text('Favorite'));
      expect(find.text('Capture Lead from Message'), findsOneWidget);
      expect(find.text('Daily Pipeline Digest'), findsNothing);
      expect(
        await api.store.read('agent_template_favorites'),
        contains('crm_capture_lead'),
      );
      await press(tester, find.text('CRM'));
      expect(find.text('Capture Lead from Message'), findsOneWidget);
      expect(find.text('Daily Pipeline Digest'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scratch workflows get editable action fields from the actual JSON schema',
    (tester) async {
      Map? saved;
      final api = nativeApi((_, body) async {
        if (body['operation'] == 'save_agent') {
          saved = body;
          return {
            'data': {'id': 1},
          };
        }
        return agentData();
      });
      await tester.pumpWidget(parityApp('ai_agents', api));
      await tester.pumpAndSettle();
      await press(tester, find.text('New Agent'));
      await press(tester, find.text('Start From Scratch'));
      await tester.enterText(input('Agent name'), 'Customer helper');
      await press(tester, find.text('Add step'));
      await press(tester, find.text('AI response'));
      await press(tester, find.text('1. Ai Call'));
      await tester.enterText(input('System Prompt'), 'Help the customer');
      await press(tester, find.byType(Switch));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      await press(tester, find.text('Save agent'));
      expect(
        saved?['inputs']['steps'][0]['config']['system_prompt'],
        'Help the customer',
      );
      expect(saved?['inputs']['steps'][0]['config']['inject_memory'], isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tasks have filter pills and a separate editor that creates real request fields',
    (tester) async {
      Map? saved;
      final filters = <String>[];
      final api = nativeApi((_, body) async {
        if (body['operation'] == 'save_task') {
          saved = body;
          return {'message': 'Saved'};
        }
        filters.add('${body['status']}');
        return {
          'data': [],
          'metrics': [
            {'label': 'Total Tasks', 'value': 0},
          ],
          'contacts': [],
          'deals': [],
        };
      });
      await tester.pumpWidget(parityApp('crm_tasks', api));
      await tester.pumpAndSettle();
      expect(input('Task title'), findsNothing);
      await press(tester, find.widgetWithText(ChoiceChip, 'Completed'));
      expect(filters.last, 'completed');
      await press(tester, find.text('New task'));
      await tester.enterText(input('Task title'), 'Call client');
      await press(tester, find.text('Save'));
      expect(saved?['inputs']['title'], 'Call client');
      expect(saved?['inputs']['status'], 'pending');
      expect(saved?['inputs']['priority'], 'medium');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Fashion Studio settings use dedicated defaults and never fetch the global profile',
    (tester) async {
      Map? saved;
      final api = nativeApi((path, body) async {
        expect(path, '/native/extension');
        if (body['operation'] == 'save_fashion') saved = body;
        return {
          'settings': {'num_images': 2, 'resolution': '2K', 'ratio': '9:16'},
          'resolutions': ['1K', '2K', '4K'],
          'ratios': ['1:1', '9:16'],
          'max_images': 4,
        };
      });
      await tester.pumpWidget(parityApp('fashion_settings', api));
      await tester.pumpAndSettle();
      expect(find.text('Generation settings'), findsOneWidget);
      expect(find.text('2K'), findsOneWidget);
      await press(tester, find.text('Save settings'));
      expect(saved?['operation'], 'save_fashion');
      expect(saved?['inputs']['ratio'], '9:16');
      expect(find.text('Photoshoot settings saved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final calendar in [false, true]) {
    testWidgets(
      '${calendar ? 'Calendar' : 'Archived posts'} tolerates null lists and uses the correct module and date parameters',
      (tester) async {
        Map? sent;
        final api = nativeApi((_, body) async {
          sent = body;
          return {
            'data': null,
            'calendar': calendar,
            'agents': [],
            'platforms': [],
          };
        });
        await tester.pumpWidget(
          parityApp(
            'agent_posts',
            api,
            id: calendar
                ? 'web:ext_social_media_agent_calendar'
                : 'web:ext_social_media_agent_agents_archived_posts',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.byType(CalendarDatePicker),
          calendar ? findsOneWidget : findsNothing,
        );
        if (calendar) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -400));
          await tester.pumpAndSettle();
        }
        expect(find.text('No posts in this view'), findsOneWidget);
        expect(
          sent?['module_id'],
          contains(calendar ? 'calendar' : 'archived_posts'),
        );
        expect(sent?.containsKey('from'), calendar);
        if (calendar) {
          expect(
            DateTime.parse(sent!['until'])
                .isAfter(DateTime.parse(sent!['from'])),
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'failed requests resolve to a retry state and retry re-fetches data',
    (tester) async {
      var calls = 0;
      final api = nativeApi((_, _) async {
        if (++calls == 1) throw const ApiFailure('You are offline.');
        return {'data': []};
      });
      await tester.pumpWidget(parityApp('agent_posts', api));
      await tester.pumpAndSettle();
      expect(find.text('You are offline.'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await press(tester, find.text('Retry'));
      expect(calls, 2);
      expect(find.text('No posts in this view'), findsOneWidget);
    },
  );

  testWidgets(
    'late search responses cannot replace the current query results',
    (tester) async {
      final old = Completer<Map<String, dynamic>>();
      final api = nativeApi(
        (_, body) async => body['query'] == 'old'
            ? old.future
            : {
                'data': [
                  {
                    'id': 1,
                    'title': body['query'] == 'new'
                        ? 'Newest result'
                        : 'Initial task',
                    'status': 'pending',
                  },
                ],
              },
      );
      await tester.pumpWidget(parityApp('crm_tasks', api));
      await tester.pumpAndSettle();
      await tester.enterText(input('Search'), 'old');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.enterText(input('Search'), 'new');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      old.complete({
        'data': [
          {'id': 2, 'title': 'Stale result'},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('Newest result'), findsOneWidget);
      expect(find.text('Stale result'), findsNothing);
    },
  );

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets(
      'native workspace cards fit $size with 130% text and keyboard inset',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = nativeApi(
          (_, _) async => {
            'data': [
              {
                'id': 1,
                'title': 'Follow up with a very long customer company name',
                'status': 'pending',
                'priority': 'high',
              },
            ],
            'metrics': [
              {'label': 'Done This Week', 'value': 12345},
            ],
            'contacts': [],
            'deals': [],
          },
        );
        await tester.pumpWidget(parityApp('crm_tasks', api, scale: 1.3));
        await tester.pumpAndSettle();
        await press(tester, find.text('New task'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 180);
        await tester.enterText(input('Task title'), 'Keyboard works');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Save'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
      },
    );
  }
}
