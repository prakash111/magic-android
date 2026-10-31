import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:magicai_mobile/widgets/document_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:magicai_mobile/screens/documents_screen.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/services/document_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_test.dart' show jsonResponse;
import 'model_generation_test.dart' show modelApi, models;

const mathTool = <String, dynamic>{
  'id': 'math_question',
  'title': 'Math Question',
  'kind': 'writer',
  'fields': [
    {
      'name': 'question',
      'label': 'Math Question',
      'type': 'textarea',
      'required': true,
    },
  ],
};
Map<String, dynamic> mathRecord() => {
  'id': 42,
  'title': 'Math Question',
  'template_name': 'Math Question',
  'template_id': 'math_question',
  'user_id': 7,
  'type': 'text',
  'editable': true,
  'content': '## Answer\n\nThe answer is **4**.',
  'prompt_preview': 'What is 2 + 2?',
  'created_at': '2026-10-20T09:42:00Z',
  'updated_at': '2026-10-20T09:42:00Z',
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Math Question automatically appears in History and supports edit copy share and deletion',
    (tester) async {
      Map<String, dynamic>? record;
      final calls = <String>[];
      String? copied;
      String? shared;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          shared = (call.arguments as Map)['text'] as String;
          return 'target.app';
        },
      );
      final api = modelApi((request) async {
        final path = request.url.path;
        calls.add('${request.method} $path');
        if (path.endsWith('/models')) return jsonResponse(models);
        if (path.endsWith('/tools/math_question/run')) {
          expect(jsonDecode(request.body)['inputs'], {
            'question': 'What is 2 + 2?',
          });
          return jsonResponse({'message_id': 42});
        }
        if (path.endsWith('/writer/42/stream')) {
          record = mathRecord();
          return http.Response(
            'data: {"delta":"## Answer\\n\\nThe answer is **4**."}\n\ndata: {"done":true}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        if (request.method == 'PUT') {
          final input = jsonDecode(request.body) as Map;
          record = {
            ...record!,
            'title': input['title'],
            'content': input['content'],
            'updated_at': '2026-10-20T09:43:00Z',
          };
          return jsonResponse({'data': record});
        }
        if (request.method == 'DELETE') {
          record = null;
          return jsonResponse({'message': 'Deleted'});
        }
        if (path.endsWith('/42')) return jsonResponse({'data': record});
        if (path.endsWith('/documents')) {
          expect(request.url.queryParameters['template_id'], 'math_question');
          return jsonResponse({
            'data': record == null ? [] : [record],
            'meta': {'last_page': 1, 'total': record == null ? 0 : 1},
          });
        }
        throw StateError('Unexpected request $path');
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: DynamicToolScreen(api: api, tool: mathTool),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('History (0)'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'What is 2 + 2?');
      final generate = find.widgetWithText(FilledButton, 'Generate');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('History (1)'), findsOneWidget);
      await tester.ensureVisible(find.text('View in History'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('View in History'));
      await tester.pumpAndSettle();
      expect(find.text('What is 2 + 2?'), findsOneWidget);
      expect(find.text('Oct 20, 2026 • 09:42 AM'), findsOneWidget);
      await tester.tap(find.text('What is 2 + 2?'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DocumentReader>(find.byType(DocumentReader)).text,
        record!['content'],
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('document-content-input')),
        '## Updated answer\n\nFour is correct.',
      );
      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(calls, contains('PUT /api/mobile/v1/documents/42'));
      if (find.byTooltip('More actions').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, record!['content']);
      expect(find.text('Copied to clipboard'), findsOneWidget);
      if (find.byTooltip('More actions').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shared, record!['content']);
      expect(
        (await DocumentService(api).snapshots()).single.content,
        record!['content'],
      );
      await tester.tap(find.byTooltip('Close document'));
      await tester.pumpAndSettle();
      expect(find.text('Updated answer Four is correct.'), findsOneWidget);
      // The Generate form stays mounted so switching tabs preserves its input.
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextFormField),
        -180,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('generator-form-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('What is 2 + 2?'), findsOneWidget);
      await tester.tap(find.text('History (1)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('What is 2 + 2?'));
      await tester.pumpAndSettle();
      if (find.byTooltip('More actions').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('More actions'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete document'));
      await tester.pumpAndSettle();
      expect(record, isNull);
      expect(find.text('History (0)'), findsOneWidget);
      expect(find.text('No generation history yet'), findsOneWidget);
      expect(await DocumentService(api).snapshots(), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history empty state retries a failed request and uses API total rather than page length',
    (tester) async {
      var count = 0;
      var requests = 0;
      final api = modelApi((request) async {
        expect(request.url.queryParameters['template_id'], 'math_question');
        if (++requests == 1) {
          return jsonResponse({
            'message': 'History is temporarily offline',
          }, 500);
        }
        return jsonResponse({
          'data': [mathRecord()],
          'meta': {'last_page': 3, 'total': 45},
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: DocumentsScreen(
              api: api,
              templateId: 'math_question',
              onCountChanged: (value) => count = value,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('History is temporarily offline'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(count, 45);
      expect(find.text('What is 2 + 2?'), findsOneWidget);
      expect(find.text('Load more'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'history editor handles a small phone large text and keyboard insets',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = modelApi(
        (request) async => jsonResponse(
          request.url.path.endsWith('/42')
              ? {'data': mathRecord()}
              : {
                  'data': [mathRecord()],
                  'meta': {'last_page': 1, 'total': 1},
                },
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: DocumentsScreen(api: api, templateId: 'math_question'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('What is 2 + 2?'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit'));
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('document-content-input')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('document-content-input')),
        'Adjusted answer',
      );
      await tester.scrollUntilVisible(
        find.text('Done'),
        180,
        scrollable: find
            .ancestor(
              of: find.byKey(const ValueKey('document-content-input')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
