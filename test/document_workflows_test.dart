import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/documents_screen.dart';
import 'package:magicai_mobile/services/document_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/chat_response.dart';
import 'package:magicai_mobile/widgets/generated_output_card.dart';
import 'package:magicai_mobile/widgets/magic_bottom_navigation.dart';

import 'mobile_api_test.dart' show jsonResponse;
import 'model_generation_test.dart' show modelApi;

Map<String, dynamic> document({String? title}) => {
  'id': 42,
  'title': title,
  'template_name': 'Math Question',
  'type': 'text',
  'editable': true,
  'content': '# Answer\n\n**42**\n\n- Complete response',
  'user_id': 7,
  'created_at': '2026-10-20T03:07:28Z',
  'updated_at': '2026-10-20T03:07:28Z',
};

void main() {
  test('titles and dates never render raw nulls or ISO timestamps', () {
    expect(MobileDocument(document(title: 'null')).title, 'Math Question');
    expect(const MobileDocument({'title': 'null'}).title, 'Untitled Document');
    expect(
      documentTimestamp(
        DateTime(2026, 10, 20, 3),
        now: DateTime(2026, 10, 20, 5),
      ),
      '2 hours ago',
    );
    expect(
      documentTimestamp(DateTime(2026, 10, 20), now: DateTime(2026, 10, 25)),
      'Oct 20, 2026',
    );
  });

  test('database saves update the same id, cache encrypted-store snapshots and remove them on delete/logout', () async {
    var saved = 0;
    var deleted = 0;
    final api = modelApi((request) async {
      if (request.method == 'POST') {
        expect(jsonDecode(request.body)['document_id'], 42);
        saved++;
        return jsonResponse({'data': document(title: 'Saved')});
      }
      if (request.method == 'DELETE') {
        deleted++;
        return jsonResponse({'message': 'Deleted'});
      }
      throw StateError('Unexpected request');
    });
    final service = DocumentService(api);
    expect(
      (await service.save(
        id: 42,
        title: 'Saved',
        content: 'Answer',
      )).storedLocally,
      isTrue,
    );
    expect((await service.snapshots()).single.title, 'Saved');
    await service.delete(42);
    expect(await service.snapshots(), isEmpty);
    await service.save(id: 42, title: 'Saved', content: 'Answer');
    await api.clearSession();
    expect(await service.snapshots(), isEmpty);
    expect(saved, 2);
    expect(deleted, 1);
  });

  testWidgets(
    'generated output uses Markdown and Save Edit Copy Delete with confirmation',
    (tester) async {
      Map? saved;
      String? copied;
      var cleared = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      final api = modelApi((request) async {
        saved = jsonDecode(request.body) as Map;
        return jsonResponse({
          'data': document(title: saved!['title'] as String)
            ..['content'] = saved!['content'],
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneratedOutputCard(
                api: api,
                documentId: 42,
                title: 'Math Question',
                content: document()['content'] as String,
                generating: false,
                onClear: () => cleared = true,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(MarkdownBody), findsOneWidget);
      for (final label in ['Save', 'Edit', 'Copy', 'Delete']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('document-content-input')),
        '# Edited answer',
      );
      await tester.ensureVisible(find.text('Apply changes'));
      await tester.tap(find.text('Apply changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, '# Edited answer');
      expect(find.text('Copied to clipboard'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!['content'], '# Edited answer');
      expect(saved!['document_id'], 42);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Clear generated output?'), findsOneWidget);
      expect(cleared, isFalse);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cleared, isFalse);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear output'));
      await tester.pumpAndSettle();
      expect(cleared, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'document list and detail support Share Edit Delete without null titles',
    (tester) async {
      var row = document(title: 'null');
      var deleted = false;
      String? shared;
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          shared = (call.arguments as Map)['text'] as String;
          return 'target.app';
        },
      );
      final api = modelApi((request) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'PUT') {
          row = {...row, ...jsonDecode(request.body) as Map};
          return jsonResponse({'data': row});
        }
        if (request.method == 'DELETE') {
          deleted = true;
          return jsonResponse({'message': 'Deleted'});
        }
        if (request.url.path.endsWith('/42')) {
          return jsonResponse({'data': row});
        }
        return jsonResponse({
          'data': deleted ? [] : [row],
          'meta': {'last_page': 1},
        });
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: DocumentsScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Math Question'), findsOneWidget);
      expect(find.text('null'), findsNothing);
      expect(find.text('2026-10-20T03:07:28Z'), findsNothing);
      expect(find.byTooltip('Options for Math Question'), findsOneWidget);
      await tester.tap(find.text('Math Question'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shared, row['content']);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('document-title-input')),
        'Edited question',
      );
      await tester.enterText(
        find.byKey(const ValueKey('document-content-input')),
        'Updated answer',
      );
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Edited question'), findsOneWidget);
      expect(calls, contains('PUT /api/mobile/v1/documents/42'));
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete document'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
      expect(find.text('No saved documents yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'assistant bubbles copy complete text and document modals cover the floating Chatbot',
    (tester) async {
      var navTaps = 0;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      final api = modelApi(
        (request) async => jsonResponse(
          request.url.path.endsWith('/42')
              ? {'data': document()}
              : {
                  'data': [document()],
                  'meta': {'last_page': 1},
                },
        ),
      );
      const text =
          '# Complete assistant response\n\n**Bold** and bullets:\n- one\n- two';
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: const ChatResponse(text: text)),
        ),
      );
      await tester.tap(find.byTooltip('Copy response'));
      await tester.pumpAndSettle();
      expect(copied, text);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: DocumentsScreen(api: api),
            bottomNavigationBar: MagicBottomNavigation(
              items: const [
                {'id': 'home', 'label': 'Home', 'component': 'dashboard'},
                {'id': 'explore', 'label': 'Explore', 'component': 'workspace'},
                {'id': 'chat', 'label': 'Chatbot', 'component': 'chat'},
                {'id': 'calendar', 'label': 'Calendar', 'component': 'social'},
                {'id': 'account', 'label': 'Account', 'component': 'account'},
              ],
              selectedIndex: 4,
              onSelected: (_) => navTaps++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final chatPosition = tester.getCenter(find.byTooltip('Open Chatbot'));
      await tester.tap(find.text('Math Question'));
      await tester.pumpAndSettle();
      await tester.tapAt(chatPosition);
      await tester.pumpAndSettle();
      expect(navTaps, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
