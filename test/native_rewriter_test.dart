import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'ReWriter uses one native header, web fields and language defaults',
    (tester) async {
      final api = nativeApi((path, body) async {
        if (path == '/models') {
          return [
            {'id': 'test-model', 'title': 'Test model'},
          ];
        }
        return {'data': []};
      });
      final module = <String, dynamic>{
        'id': 'web:ai_rewriter',
        'title': 'AI ReWriter',
        'route_type': 'writer_tool',
        'tool': {
          'id': 'ai_rewriter',
          'title': 'AI ReWriter',
          'kind': 'writer',
          'endpoint': '/tools/ai_rewriter/run',
          'fields': [
            {
              'name': 'content_rewrite',
              'label': 'Your content',
              'type': 'textarea',
              'required': true,
            },
            {
              'name': 'rewrite_mode',
              'label': 'Mode',
              'type': 'select',
              'options': ['Professional', 'Casual'],
              'default': 'Casual',
              'required': true,
            },
            {
              'name': 'language',
              'label': 'Output Language',
              'type': 'select',
              'options': ['en-US', 'de-DE'],
              'option_labels': {'en-US': 'English', 'de-DE': 'German'},
              'default': 'de-DE',
              'required': true,
            },
          ],
        },
      };
      await tester.pumpWidget(
        MaterialApp(
          home: NativeModuleScreen(module: module, api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Your content'), findsOneWidget);
      final dropdowns = tester.widgetList<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>),
      );
      expect(
        dropdowns.map((field) => field.initialValue),
        containsAll(['Casual', 'de-DE']),
      );
      expect(find.text('German'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
