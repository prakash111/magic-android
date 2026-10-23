import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/services/ai_model_selection.dart';
import 'package:magicai_mobile/services/api_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/ai_model_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;

const models = <Map<String, dynamic>>[
  {'id': 'gpt-4', 'title': 'GPT-4', 'provider': 'OpenAI', 'engine': 'openai'},
  {
    'id': 'gemini-3-flash-preview',
    'title': 'Gemini Flash',
    'provider': 'Google Gemini',
    'engine': 'gemini',
    'is_default': true,
    'is_system_default': true,
    'capabilities': ['Text', 'Chat'],
  },
];

MobileApi modelApi(Future<http.Response> Function(http.Request) handle) =>
    MobileApi(
      origin: Uri.parse('https://magicai.example.test'),
      store: MemorySecureStore()
        ..values.addAll({
          'access_token': 'private-token',
          'instance_hash': 'a' * 64,
        }),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return jsonResponse(license());
        }
        expect(request.headers['Authorization'], 'Bearer private-token');
        return handle(request);
      }),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('fresh admin default wins over stale config and selections persist across service instances', () async {
    final api = modelApi((_) async => jsonResponse(models));
    AiModelSelection.configure(api, {
      'user': {'id': 7},
      'ai': {'default_model_id': 'gpt-4'},
    });
    final service = AiModelSelection(api);
    expect(
      await service.resolve(await service.models()),
      'gemini-3-flash-preview',
    );
    await service.select('gpt-4', models);
    expect(
      (await SharedPreferences.getInstance()).getString('selected_ai_model_id'),
      'gpt-4',
    );
    expect(await AiModelSelection(api).resolve(models), 'gpt-4');
    expect(await service.resolve([models[1]]), 'gemini-3-flash-preview');
    AiModelSelection.configure(api, {
      'user': {'id': 8},
    });
    expect(await service.resolve(models), 'gemini-3-flash-preview');
    expect(
      () => service.select('inactive-model', models),
      throwsA(isA<ApiFailure>()),
    );
    expect(await service.resolve([]), isNull);
  });

  test(
    'shared generator and chat helpers reuse the persisted model selection',
    () async {
      final requests = <Map>[];
      final api = modelApi((request) async {
        final path = request.url.path;
        if (path.endsWith('/models')) return jsonResponse(models);
        if (path.endsWith('/chat/options')) {
          return jsonResponse({
            'models': models,
            'personas': [
              {'id': 0, 'name': 'Assistant'},
            ],
          });
        }
        if (path.endsWith('/tools/personal_bio/run')) {
          requests.add(jsonDecode(request.body) as Map);
          return jsonResponse({'message_id': 42});
        }
        if (path.endsWith('/chat/conversations')) {
          return jsonResponse({'id': 7});
        }
        if (path.endsWith('/stream')) {
          requests.add(jsonDecode(request.body) as Map);
          return http.Response(
            'data: {"delta":"Saved model answer"}\n\ndata: {"done":true}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }
        throw StateError('Unexpected request $path');
      });
      await AiModelSelection(api).select('gpt-4', models);
      expect(
        await ApiService.generateTemplateContent(
          client: api,
          templateId: 'personal_bio',
          inputs: {'your_name': 'Test', 'your_summary': 'Engineer'},
        ),
        'Saved model answer',
      );
      expect(requests.first['model'], 'gpt-4');
      expect(
        await ApiService.sendChatMessage(
          client: api,
          message: 'Hello',
          systemPrompt: '',
        ),
        'Saved model answer',
      );
      expect(requests.last['model'], 'gpt-4');
    },
  );

  testWidgets(
    'model sheet pins defaults, filters instantly and returns the selected real id',
    (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AiModelSelector(
              models: models,
              selected: 'gpt-4',
              onSelected: (value) => picked = value,
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('System defaults')).dy,
        lessThan(tester.getTopLeft(find.text('OpenAI').first).dy),
      );
      await tester.enterText(find.byType(TextField), 'gemini');
      await tester.pump();
      expect(find.text('GPT-4'), findsOneWidget);
      expect(find.text('Gemini Flash'), findsOneWidget);
      await tester.tap(find.text('Gemini Flash'));
      await tester.pumpAndSettle();
      expect(picked, 'gemini-3-flash-preview');
      expect(tester.takeException(), isNull);
    },
  );

  for (final slug in ['cover_letter', 'personal_bio']) {
    testWidgets(
      '$slug maps exact web field names and sends the resolved model to generation',
      (tester) async {
        Map? payload;
        final input = slug == 'cover_letter'
            ? {
                'job_title': 'Developer',
                'company_name': 'Example Ltd',
                'your_name': 'Test Writer',
                'your_skills': 'Flutter',
              }
            : {'your_name': 'Test Writer', 'your_summary': 'An engineer'};
        final api = modelApi((request) async {
          final path = request.url.path;
          if (path.endsWith('/documents')) {
            return jsonResponse({
              'data': [],
              'meta': {'last_page': 1, 'total': 0},
            });
          }
          if (path.endsWith('/models')) return jsonResponse(models);
          if (path.endsWith('/tools/$slug/run')) {
            payload = jsonDecode(request.body) as Map;
            return jsonResponse({'message_id': 42});
          }
          if (path.endsWith('/writer/42/stream')) {
            return http.Response(
              'data: {"delta":"# Generated document"}\n\ndata: {"done":true}\n\n',
              200,
              headers: {'content-type': 'text/event-stream'},
            );
          }
          throw StateError('Unexpected request $path');
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: DynamicToolScreen(
              api: api,
              tool: {
                'id': slug,
                'title': slug,
                'kind': 'writer',
                'fields': [
                  for (final name in input.keys)
                    {'name': name, 'label': name, 'required': true},
                ],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Gemini Flash'), findsOneWidget);
        final fields = find.byType(TextFormField);
        var index = 0;
        for (final value in input.values) {
          await tester.enterText(fields.at(index++), value);
        }
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, 'Generate'),
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Generate'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pumpAndSettle();
        expect(payload, {'inputs': input, 'model': 'gemini-3-flash-preview'});
        expect(find.byType(MarkdownBody), findsOneWidget);
        expect(
          tester.widget<MarkdownBody>(find.byType(MarkdownBody)).data,
          '# Generated document',
        );
        expect(find.byTooltip('Copy response'), findsOneWidget);
        expect(find.text('Generation failed. Please retry.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('stream validation errors preserve the backend explanation', () async {
    final api = modelApi((request) async {
      expect(request.headers['Accept'], startsWith('application/json'));
      return jsonResponse({
        'message': 'No credits remaining. Upgrade your plan.',
      }, 402);
    });
    await expectLater(
      api.stream('/writer/42/stream').toList(),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.message,
          'message',
          contains('No credits remaining'),
        ),
      ),
    );
  });

  testWidgets(
    'model selector remains usable with keyboard and large text on a small phone',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: Scaffold(
            body: AiModelSelector(
              models: models,
              selected: 'gpt-4',
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('ai-model-selector')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no matching model');
      await tester.pump();
      expect(find.text('No matching models'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Markdown responses use readable theme text and invoke native copy and sharing',
    (tester) async {
      const response = '# Heading\n\n**Important**\n\n- First\n- Second';
      String? clipboard;
      Map? shared;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/share'),
        (call) async {
          shared = call.arguments as Map;
          return 'com.example.target';
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(child: ChatResponse(text: response)),
          ),
        ),
      );
      final markdown = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(markdown.styleSheet!.p!.height, 1.5);
      expect(markdown.styleSheet!.p!.color, const Color(0xFF0F172A));
      await tester.tap(find.byTooltip('Copy response'));
      await tester.pumpAndSettle();
      expect(clipboard, response);
      expect(find.text('Copied to clipboard'), findsOneWidget);
      await tester.tap(find.byTooltip('Share response'));
      await tester.pumpAndSettle();
      expect(shared?['text'], response);
      expect(tester.takeException(), isNull);
    },
  );
}
