import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/widgets/document_page.dart';
import 'package:magicai_mobile/widgets/document_actions.dart';

void main() {
  testWidgets(
    'formatted editing preserves the original Markdown and composing text',
    (tester) async {
      const original =
          '## Heading\n\nHello **world** and *friends*.\n\n- First item';
      final controller = DocumentTextController(text: original);
      addTearDown(controller.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );
      final spans = controller.buildTextSpan(
        context: context,
        withComposing: false,
      );
      expect(spans.toPlainText(), original);
      expect(controller.text, original);
      controller.value = controller.value.copyWith(
        composing: const TextRange(start: 3, end: 10),
      );
      expect(
        controller
            .buildTextSpan(context: context, withComposing: true)
            .toPlainText(),
        original,
      );
    },
  );

  testWidgets(
    'formatting toolbar supports undo redo and saves the actual document',
    (tester) async {
      DocumentEdit? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => editDocumentText(
                  context,
                  title: 'Title',
                  content: 'Hello world',
                  onSave: (edit) async {
                    saved = edit;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('document-content-input')),
      );
      field.controller!.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      await tester.pump();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pump();
      expect(field.controller!.text, 'Hello **world**');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(field.controller!.text, 'Hello world');
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(field.controller!.text, 'Hello **world**');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(saved!.content, 'Hello **world**');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'section cards collapse and the outline returns to the document',
    (tester) async {
      final key = GlobalKey<DocumentReaderState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocumentReader(
                key: key,
                text: 'Intro\n\n### Step 1\nA useful explanation.\n\n### Step 2\nAnother explanation.',
              ),
            ),
          ),
        ),
      );
      expect(find.text('A useful explanation.'), findsOneWidget);
      await tester.tap(find.text('Step 1'));
      await tester.pumpAndSettle();
      expect(find.text('A useful explanation.'), findsNothing);
      key.currentState!.showSections();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Step 1').last);
      await tester.pumpAndSettle();
      expect(find.text('A useful explanation.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
