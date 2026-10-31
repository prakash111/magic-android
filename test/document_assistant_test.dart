import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/services/document_assistant.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/document_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_test.dart' show jsonResponse;
import 'model_generation_test.dart' show modelApi, models;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('selection replacement preserves surrounding Unicode and extension appends new paragraphs', () {
    const text = 'Hello 🌟. She write well. The end.';
    final start = text.indexOf('She');
    final selection = DocumentAiSelection(
      text,
      TextSelection(baseOffset: start, extentOffset: start + 15),
    );
    expect(selection.text, 'She write well.');
    expect(
      selection.apply('She writes well.', 'correct'),
      'Hello 🌟. She writes well. The end.',
    );
    expect(
      selection.apply('Another paragraph.', 'extend'),
      'Hello 🌟. She write well.\n\nAnother paragraph.\n\n The end.',
    );
    final whole = DocumentAiSelection(text, null);
    expect(whole.selected, isFalse);
    expect(whole.apply('New content.', 'extend'), '$text\n\nNew content.');
    expect(
      DocumentAiSelection(text, const TextSelection.collapsed(offset: 2)).text,
      text,
    );
  });

  test('AI requests use the system model and only the selected text without saving a document', () async {
    final requests = <Map>[];
    final api = modelApi((request) async {
      if (request.url.path.endsWith('/models')) return jsonResponse(models);
      expect(request.url.path, '/api/mobile/v1/documents/42/assist');
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map;
      requests.add(body);
      expect(body['model'], 'gemini-3-flash-preview');
      expect(body['content'], 'bad text');
      expect(body['context'], 'Before bad text after');
      return jsonResponse({'replacement': 'Better text'});
    });
    final proposal = await DocumentAssistant(api).propose(
      documentId: 42,
      selection: DocumentAiSelection(
        'Before bad text after',
        const TextSelection(baseOffset: 7, extentOffset: 15),
      ),
      action: 'refine',
      instruction: 'Make it clear',
    );
    expect(proposal.suggested, 'Before Better text after');
    expect(proposal.original, 'Before bad text after');
    expect(requests, hasLength(1));
    expect(requests.single['request_id'], isNotEmpty);
  });

  test(
    'empty text and missing instructions fail before any network call',
    () async {
      final api = modelApi(
        (_) async => throw StateError('No requests expected'),
      );
      final assistant = DocumentAssistant(api);
      await expectLater(
        assistant.propose(
          documentId: 42,
          selection: DocumentAiSelection('', null),
          action: 'correct',
        ),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        assistant.propose(
          documentId: 42,
          selection: DocumentAiSelection('Text', null),
          action: 'refine',
        ),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  for (final accept in [false, true]) {
    testWidgets(
      'AI preview ${accept ? 'accepts and saves explicitly' : 'discards without altering the document'}',
      (tester) async {
        DocumentEdit? saved;
        var saves = 0;
        final api = modelApi(
          (request) async => request.url.path.endsWith('/models')
              ? jsonResponse(models)
              : jsonResponse({'replacement': 'She writes well.'}),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => editDocumentText(
                    context,
                    title: 'My document',
                    content: 'She write well.',
                    api: api,
                    documentId: 42,
                    onSave: (edit) async {
                      saved = edit;
                      saves++;
                    },
                  ),
                  child: const Text('Open editor'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open editor'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AI'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('AI Correct'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AI Correct'));
        await tester.pumpAndSettle();
        expect(find.text('Preview changes'), findsOneWidget);
        expect(saves, 0);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('document-content-input')),
              )
              .controller!
              .text,
          'She write well.',
        );
        await tester.ensureVisible(
          find.text(accept ? 'Accept changes' : 'Discard'),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(accept ? 'Accept changes' : 'Discard'));
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('document-content-input')),
              )
              .controller!
              .text,
          accept ? 'She writes well.' : 'She write well.',
        );
        await tester.ensureVisible(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(saved!.content, accept ? 'She writes well.' : 'She write well.');
        expect(find.text('Editing'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('failed saving keeps accepted content in the editor for retry', (
    tester,
  ) async {
    var saves = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editDocumentText(
                context,
                title: 'My document',
                content: 'Text',
                onSave: (_) async {
                  saves++;
                  throw const ApiFailure('Offline. Reconnect and retry.');
                },
              ),
              child: const Text('Open editor'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('document-content-input')),
      'Edited text',
    );
    await tester.ensureVisible(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    expect(find.text('Editing'), findsOneWidget);
    expect(find.text('Offline. Reconnect and retry.'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('document-content-input')),
          )
          .controller!
          .text,
      'Edited text',
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'refine edits the selected passage and provider errors preserve the original',
    (tester) async {
      Map? submitted;
      var fail = true;
      final api = modelApi((request) async {
        if (request.url.path.endsWith('/models')) return jsonResponse(models);
        submitted = jsonDecode(request.body) as Map;
        if (fail) {
          return jsonResponse({'message': 'No credits remaining.'}, 402);
        }
        return jsonResponse({'replacement': 'a clear passage'});
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editDocumentText(
                  context,
                  title: 'A document',
                  content: 'Before bad text after',
                  api: api,
                  documentId: 42,
                ),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('document-content-input')),
      );
      field.controller!.selection = const TextSelection(
        baseOffset: 7,
        extentOffset: 15,
      );
      await tester.tap(find.text('AI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Make changes / Refine'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make changes / Refine'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('document-ai-instruction')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('document-ai-instruction')),
        'Make it clearer',
      );
      await tester.ensureVisible(find.text('Generate preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate preview'));
      await tester.pumpAndSettle();
      expect(find.text('No credits remaining.'), findsOneWidget);
      expect(field.controller!.text, 'Before bad text after');
      expect(submitted!['content'], 'bad text');
      expect(submitted!['instruction'], 'Make it clearer');
      fail = false;
      await tester.ensureVisible(find.text('Generate preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate preview'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Accept changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Accept changes'));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'Before a clear passage after');
      expect(tester.takeException(), isNull);
    },
  );
}
