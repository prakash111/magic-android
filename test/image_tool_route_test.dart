import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

const imageTool = {
  'id': 'mobile-image',
  'title': 'AI Image',
  'kind': 'image',
  'endpoint': '/tools/mobile-image/run',
  'history_template_id': 'ai_image_generator',
  'route_slug': 'ai_image_generator',
  'fields': [
    {
      'name': 'description',
      'label': 'Describe your image',
      'type': 'textarea',
      'required': true,
    },
  ],
};
const imageModule = {
  'id': 'web:ai_image_generator',
  'title': 'AI Image',
  'route_slug': 'ai_image_generator',
  'route_type': 'writer_tool',
};
const imageModels = {
  'data': [
    {'id': 'gpt-image-1', 'title': 'GPT image 1', 'is_default': true},
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final oldCatalog in [false, true]) {
    testWidgets(
      'image loader uses config and resolves image aliases (old=$oldCatalog)',
      (tester) async {
        final paths = <String>[];
        Map? submitted;
        final tool = {...imageTool};
        if (oldCatalog) tool.remove('route_slug');
        final api = nativeApi((path, body) async {
          if (path.startsWith('/documents?')) {
            return {
              'data': [],
              'meta': {'total': 0, 'last_page': 1},
            };
          }
          paths.add(path);
          if (path == '/config') {
            return {
              'tools': [tool],
            };
          }
          if (path == '/image-models') return imageModels;
          if (path == '/tools/mobile-image/run') {
            submitted = body;
            throw const ApiFailure('QA provider error');
          }
          fail('Unexpected image endpoint: $path');
        });
        await tester.pumpWidget(
          MaterialApp(home: NativeModuleRegistry.build(imageModule, api: api)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DynamicToolScreen), findsOneWidget);
        expect(paths, ['/config', '/image-models']);
        expect(paths, isNot(contains('/dashboard')));
        await tester.enterText(
          find.byType(TextFormField).last,
          'A blue test square',
        );
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Generate'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.pumpAndSettle();
        expect(submitted, {
          'inputs': {'description': 'A blue test square'},
          'model': 'gpt-image-1',
        });
        expect(find.text('QA provider error'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'bound image metadata opens the image form directly for installed apps',
    (tester) async {
      final paths = <String>[];
      final api = nativeApi((path, _) async {
        if (path.startsWith('/documents?')) {
          return {
            'data': [],
            'meta': {'total': 0, 'last_page': 1},
          };
        }
        paths.add(path);
        expect(path, '/image-models');
        return imageModels;
      });
      await tester.pumpWidget(
        MaterialApp(
          home: NativeModuleRegistry.build({
            ...imageModule,
            'tool': imageTool,
          }, api: api),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DynamicToolScreen), findsOneWidget);
      expect(paths, ['/image-models']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('image metadata timeout stops loading and retry uses config', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<Map<String, dynamic>>();
    final api = nativeApi((path, _) async {
      if (path == '/config') {
        if (++calls == 1) return pending.future;
        return {
          'tools': [imageTool],
        };
      }
      if (path.startsWith('/documents?')) {
        return {
          'data': [],
          'meta': {'total': 0, 'last_page': 1},
        };
      }
      expect(path, '/image-models');
      return imageModels;
    });
    await tester.pumpWidget(
      MaterialApp(home: NativeModuleRegistry.build(imageModule, api: api)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('Please retry.'), findsOneWidget);
    pending.complete({
      'tools': [imageTool],
    });
    await tester.pump();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.byType(DynamicToolScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
