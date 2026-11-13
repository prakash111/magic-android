import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/services/chat_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

const webPrompts = [
  {
    'name': '📊 Pipeline summary',
    'prompt': 'Give me a summary of my sales pipeline by stage.',
  },
  {
    'name': '⏰ Overdue tasks',
    'prompt': 'Which of my tasks are overdue? List them by priority.',
  },
  {
    'name': '🏆 Top deals',
    'prompt': 'What are my top 5 deals by value and what stage are they in?',
  },
  {
    'name': '👤 Add a contact',
    'prompt': 'Create a new contact named Jane Smith at Acme Inc.',
  },
  {
    'name': '🧾 Draft an invoice',
    'prompt': 'Create a draft invoice for my most recent deal.',
  },
  {
    'name': '📁 Project health',
    'prompt': 'Which projects are at risk of missing their due date?',
  },
  {
    'name': '💰 Outstanding balance',
    'prompt': 'How much is currently outstanding across all invoices?',
  },
  {
    'name': '📑 Pitch deck',
    'prompt': 'Generate a modern pitch deck for my largest open deal.',
  },
];
Map<String, Object> options(List<Map<String, String>> prompts) => {
  'personas': [
    {'id': 0, 'name': 'CRM Assistant'},
  ],
  'models': [
    {'id': 'gpt-4o', 'title': 'GPT-4o'},
  ],
  'example_prompts': prompts,
};
Widget screen(
  MobileApi api, {
  int refresh = 0,
  double scale = 1,
  ThemeData? theme,
}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: ServerChatScreen(api: api, crm: true, refreshVersion: refresh),
  ),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('options retain every configured name and full prompt', () async {
    final api = nativeApi((path, _) async {
      expect(path, '/chat/options?context=crm');
      return options(webPrompts);
    });
    expect(
      (await ChatService(api, context: 'crm').options())['example_prompts'],
      webPrompts,
    );
  });
  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets(
      'all eight options fit ${theme.brightness.name} CRM at 1.6 text scale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = nativeApi(
          (path, _) async => path.startsWith('/chat/options')
              ? options(webPrompts)
              : {'data': []},
        );
        await tester.pumpWidget(screen(api, scale: 1.6, theme: theme));
        await tester.pumpAndSettle();
        for (final p in webPrompts) {
          expect(find.text(p['name']!), findsOneWidget);
        }
        expect(find.text('Recent contacts'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'shortcut fills full prompt without sending or creating a record',
    (tester) async {
      var sends = 0;
      final api = nativeApi((path, body) async {
        if (body.isNotEmpty) sends++;
        return path.startsWith('/chat/options')
            ? options(webPrompts)
            : {'data': []};
      });
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('crm-example-prompt-0')));
      await tester.pumpAndSettle();
      final composer = tester
          .widgetList<TextField>(find.byType(TextField))
          .last;
      expect(composer.controller!.text, webPrompts.first['prompt']);
      expect(composer.focusNode!.hasFocus, isTrue);
      expect(sends, 0);
    },
  );
  testWidgets(
    'refresh reflects added removed and empty administrator suggestions',
    (tester) async {
      var configured = webPrompts;
      final api = nativeApi(
        (path, _) async => path.startsWith('/chat/options')
            ? options(configured)
            : {'data': []},
      );
      await tester.pumpWidget(screen(api));
      await tester.pumpAndSettle();
      configured = [
        {
          'name': 'Configured customer follow-up',
          'prompt': 'Show customers requiring a follow-up.',
        },
      ];
      await tester.pumpWidget(screen(api, refresh: 1));
      await tester.pumpAndSettle();
      expect(find.text(configured.first['name']!), findsOneWidget);
      expect(find.text(webPrompts.first['name']!), findsNothing);
      configured = [];
      await tester.pumpWidget(screen(api, refresh: 2));
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNothing);
    },
  );
  testWidgets(
    'long custom options scroll without overflow at large text scale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prompts = List.generate(
        20,
        (i) => {
          'name': 'Projektstatus und ausstehende Kundenaufgaben $i',
          'prompt': 'Zeige die vollständige Projektübersicht $i.',
        },
      );
      final api = nativeApi(
        (path, _) async =>
            path.startsWith('/chat/options') ? options(prompts) : {'data': []},
      );
      await tester.pumpWidget(screen(api, scale: 1.6));
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNWidgets(20));
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
