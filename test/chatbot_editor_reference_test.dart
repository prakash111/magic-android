import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_connections_screen.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'reference chatbot tabs preserve edits and submit MagicAI field names',
    (tester) async {
      Map? saved;
      final api = nativeApi((path, body) async {
        if (body['operation'] == 'save_bot') {
          saved = body['inputs'] as Map;
          return {'message': 'Chatbot saved.'};
        }
        return {
          'values': {
            'title': 'Support',
            'welcome_message': 'Welcome',
            'bubble_message': 'Ask us',
            'instructions': 'Help customers',
            'language': 'auto',
            'active': true,
            'logo': '',
            'color': '#6366F1',
            'trusted_domains': <String>[],
          },
          'schema': {'type': 'object', 'properties': <String, dynamic>{}},
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          home: NativeChatbotEditor(
            api: api,
            moduleId: 'chatbot',
            chatbotId: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      for (final tab in ['Basics', 'Look', 'Behavior', 'More']) {
        expect(find.text(tab), findsOneWidget);
      }
      await tester.enterText(find.byType(TextFormField).first, 'New support');
      expect(find.text('Unsaved changes'), findsOneWidget);
      await tester.tap(find.text('Look'));
      await tester.pumpAndSettle();
      expect(find.text('New support'), findsOneWidget);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Websites that can use this chatbot'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(saved?['title'], 'New support');
      expect(saved?['active'], true);
      expect(saved?['instructions'], 'Help customers');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Reset restores saved field values after editing', (
    tester,
  ) async {
    final api = nativeApi(
      (_, _) async => {
        'values': {
          'title': 'Support',
          'welcome_message': 'Welcome',
          'bubble_message': 'Ask us',
        },
        'schema': {'properties': <String, dynamic>{}},
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NativeChatbotEditor(api: api, moduleId: 'chatbot', chatbotId: 1),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Changed');
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(find.text('Support'), findsOneWidget);
    expect(find.text('Changed'), findsNothing);
    expect(find.text('All changes saved'), findsOneWidget);
  });
}
