import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/native_creative_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_projects_screen.dart';
import 'package:magicai_mobile/services/image_generation_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

const canvas = {
  'version': 1,
  'width': 1920,
  'height': 1080,
  'background': '#131620',
  'layers': [
    {
      'type': 'text',
      'text': 'Saved headline',
      'x': 0.1,
      'y': 0.2,
      'size': 0.09,
      'color': '#FFFFFF',
    },
  ],
};
const imageModels = {
  'data': [
    {
      'id': 'gpt-image-1',
      'title': 'GPT image 1',
      'provider': 'OpenAI',
      'is_default': true,
    },
  ],
};
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('queued image polling waits for completed output and sends the selected model', () async {
    var polls = 0;
    final api = nativeApi((path, body) async {
      if (path == '/tools/mobile-image/run') {
        expect(body, {
          'inputs': {'description': 'A night sky'},
          'model': 'gpt-image-1',
        });
        return {
          'images': [
            {
              'id': 8,
              'status': 'IN_QUEUE',
              'output': '/themes/default/assets/img/loading.svg',
            },
          ],
        };
      }
      expect(path, '/images/8');
      polls++;
      return {
        'data': {'id': 8, 'status': 'COMPLETED', 'output': '/uploads/sky.png'},
      };
    });
    expect(
      await ImageGenerationService(
        api,
        pollInterval: Duration.zero,
      ).generate(prompt: 'A night sky', model: 'gpt-image-1'),
      'https://magicai.example.test/uploads/sky.png',
    );
    expect(polls, 1);
  });
  test('image failures keep useful backend messages and reject insecure or pending outputs', () async {
    final failing = nativeApi(
      (_, body) async => throw const ApiFailure(
        'The image provider has no API credits remaining.',
      ),
    );
    await expectLater(
      ImageGenerationService(failing)
          .generate(prompt: 'A sky', model: 'gpt-image-1'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'reason',
          contains('no API credits'),
        ),
      ),
    );
    var pendingRequests = 0;
    final pending = nativeApi((_, body) async {
      pendingRequests++;
      return {
        'images': [
          {'id': 4, 'status': 'IN_QUEUE'},
        ],
      };
    });
    await expectLater(
      ImageGenerationService(
        pending,
        maximumWait: Duration.zero,
      ).generate(prompt: 'A sky', model: 'gpt-image-1'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'reason',
          contains('Check generation history'),
        ),
      ),
    );
    expect(pendingRequests, 1);
    final insecure = nativeApi(
      (_, body) async => {
        'images': [
          {'output': 'http://unsafe.test/image.png'},
        ],
      },
    );
    await expectLater(
      ImageGenerationService(insecure)
          .generate(prompt: 'A sky', model: 'gpt-image-1'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.message,
          'reason',
          contains('insecure'),
        ),
      ),
    );
  });
  testWidgets(
    'recent designs open native layers, change ratio, save and export without opening the browser',
    (tester) async {
      final calls = <String>[];
      Map? saved;
      Uint8List? exported;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureStore.channel, (call) async {
            calls.add(call.method);
            if (call.method == 'saveImage') {
              exported = call.arguments['bytes'] as Uint8List;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SecureStore.channel, null),
      );
      final api = nativeApi((path, body) async {
        if (path == '/image-models') return imageModels;
        if (path == '/native/creative/templates') return [];
        if (path == '/native/creative/projects/7') {
          saved = body;
          return {
            'data': {'id': 7},
          };
        }
        return {
          'data': [
            {'id': 7, 'name': 'My campaign', 'canvas': canvas},
          ],
          'current_page': 1,
          'last_page': 1,
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(body: NativeCreativeScreen(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.text('My campaign'));
      await tester.tap(find.text('My campaign'));
      await tester.pumpAndSettle();
      expect(find.text('AI image tools'), findsOneWidget);
      await reveal(tester, find.text('Saved headline'));
      expect(find.text('Saved headline'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, 500));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('9:16'));
      await tester.tap(find.text('9:16'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Save project'));
      await tester.tap(find.text('Save project'));
      await tester.pumpAndSettle();
      expect(saved?['payload']['width'], 1080);
      expect(saved?['payload']['height'], 1920);
      expect(saved?['payload']['layers'][0]['text'], 'Saved headline');
      await reveal(tester, find.text('Export PNG'));
      await tester.tap(find.text('Export PNG'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await tester.pumpAndSettle();
      expect(exported, isNotNull);
      expect(calls, contains('saveImage'));
      expect(calls, isNot(contains('openUrl')));
      expect(calls, isNot(contains('openVisualEditor')));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'date schema inputs open native date picker and submit ISO dates',
    (tester) async {
      Map? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ListView(
              children: [
                NativeSchemaForm(
                  definition: const {
                    'title': 'Save deal',
                    'fields': [
                      {
                        'name': 'expected_close_date',
                        'label': 'Expected Close Date',
                        'type': 'date',
                      },
                    ],
                  },
                  busy: false,
                  submit: (inputs, files) async {
                    saved = inputs;
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Choose date'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save deal'));
      await tester.pumpAndSettle();
      expect(
        saved?['expected_close_date'],
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'connected accounts have one header and back button under Explore',
    (tester) async {
      final api = nativeApi((_, body) async => []);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NativeModuleScreen(
                      module: const {
                        'id': 'web:platforms',
                        'title': 'Platforms',
                        'route_type': 'social_accounts',
                      },
                      api: api,
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'projects render metrics and keep creation form separate from project cards',
    (tester) async {
      final api = nativeApi(
        (_, body) async => {
          'metrics': [
            for (final label in [
              'Total Projects',
              'In Progress',
              'Completed',
              'Overdue',
            ])
              {'label': label, 'value': 0},
          ],
          'data': null,
          'contacts': [],
          'companies': [],
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: NativeProjectsScreen(
              module: const {'id': 'web:crm_projects'},
              api: api,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Total Projects'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Project name'), findsNothing);
      await tester.tap(find.text('New Project'));
      await tester.pumpAndSettle();
      expect(find.text('Project name'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
