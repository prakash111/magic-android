import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/video_tool_screen.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart' show openModule;
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/video_tool_models.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

const module = <String, dynamic>{
  'id': 'web:ai_video_pro',
  'title': 'AI Video Pro',
  'route_slug': 'ai_video_pro',
  'route_type': 'video_pro',
  'available': true,
};
const nestedModels = {
  'sora': {
    'label': 'Sora',
    'isActive': true,
    'subModels': {
      'sora2': {
        'isActive': true,
        'features': {
          'sora-2': {'label': 'Sora 2', 'inputs': []},
          'sora-2-pro': {'label': 'Sora 2 Pro', 'inputs': []},
        },
      },
    },
  },
  'kling': {
    'label': 'Kling',
    'isActive': false,
    'subModels': {
      'kling2': {
        'isActive': true,
        'features': {
          'disabled-model': {'label': 'Disabled Kling'},
        },
      },
    },
  },
};
Map config(dynamic models) => {
  'engines': [
    {'id': 'ai_video_pro', 'models': models},
  ],
};
Widget app(Widget child, {ThemeData? theme, double scale = 1}) => MaterialApp(
  theme: theme ?? AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'parses the nested web model configuration and excludes disabled providers',
    () {
      final models = videoModelOptions(nestedModels);
      expect(models.map((m) => m.id), ['sora-2', 'sora-2-pro']);
      expect(models.map((m) => m.label), ['Sora 2', 'Sora 2 Pro']);
    },
  );
  test('supports legacy lists flat maps and duplicate IDs without dropdown assertions', () {
    expect(videoModelOptions(['one', 'one', 'two']).map((m) => m.id), [
      'one',
      'two',
    ]);
    expect(videoModelOptions({'one': 'Model One'}).single.label, 'Model One');
    expect(
      videoModelOptions([
        {'id': 'one', 'label': 'One'},
        {'id': 'disabled', 'enabled': false},
      ]).map((m) => m.id),
      ['one'],
    );
    expect(videoModelOptions(null), isEmpty);
  });
  for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
    testWidgets(
      'Creative Studio opens Video Pro with the real nested response in ${theme.brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = nativeApi((path, _) async {
          if (path == '/video/tools') return config(nestedModels);
          expect(path, '/video/outputs?tool=ai_video_pro&page=1');
          return {'data': [], 'current_page': '1', 'last_page': '1'};
        });
        await tester.pumpWidget(
          app(
            Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => openModule(context, module, api: api),
                  child: const Text('Open AI Video Pro'),
                ),
              ),
            ),
            theme: theme,
            scale: 1.6,
          ),
        );
        await tester.tap(find.text('Open AI Video Pro'));
        await tester.pumpAndSettle();
        expect(find.byType(VideoToolScreen), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Video Configuration'), findsOneWidget);
        expect(find.text('Sora 2'), findsOneWidget);
        expect(find.text('Disabled Kling'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('configuration failure displays Retry and successfully reloads', (
    tester,
  ) async {
    var loads = 0;
    final api = nativeApi((path, _) async {
      if (path == '/video/tools') {
        if (++loads == 1) {
          throw const ApiFailure('Video configuration unavailable');
        }
        return config(nestedModels);
      }
      return {'data': []};
    });
    await tester.pumpWidget(app(VideoToolScreen(module: module, api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Video configuration unavailable'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Video Configuration'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('history errors do not blank or block the creation form', (
    tester,
  ) async {
    final api = nativeApi((path, _) async {
      if (path == '/video/tools') return config(nestedModels);
      throw const ApiFailure('Video history unavailable');
    });
    await tester.pumpWidget(app(VideoToolScreen(module: module, api: api)));
    await tester.pumpAndSettle();
    expect(find.text('Video Configuration'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.video_library_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Video history unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'empty model configuration is actionable rather than a blank page',
    (tester) async {
      final api = nativeApi((path, _) async => config({}));
      await tester.pumpWidget(app(VideoToolScreen(module: module, api: api)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('No video models are currently available'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'leaving during a pending configuration request does not update disposed state',
    (tester) async {
      final response = Completer<dynamic>();
      final api = nativeApi((path, _) async => response.future);
      await tester.pumpWidget(app(VideoToolScreen(module: module, api: api)));
      await tester.pump();
      await tester.pumpWidget(app(const Scaffold(body: Text('Closed'))));
      response.complete(config(nestedModels));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'generation submits the actual selected model instead of the standard placeholder',
    (tester) async {
      Map? submitted;
      final api = nativeApi((path, body) async {
        if (path == '/video/tools') return config(nestedModels);
        if (path == '/video/generate') {
          submitted = body;
          throw const ApiFailure('Generation not executed in this test');
        }
        return {'data': []};
      });
      await tester.pumpWidget(app(VideoToolScreen(module: module, api: api)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).last,
        'Cinematic mountains',
      );
      await tester.ensureVisible(find.text('Generate Video'));
      await tester.tap(find.text('Generate Video'));
      await tester.pumpAndSettle();
      expect(submitted?['model'], 'sora-2');
      expect(submitted?['tool'], 'ai_video_pro');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'other video tools keep their generic creation form without a model catalog',
    (tester) async {
      final api = nativeApi(
        (path, _) async =>
            path == '/video/tools' ? {'engines': []} : {'data': []},
      );
      await tester.pumpWidget(
        app(
          VideoToolScreen(
            module: const {'id': 'web:ai_influencer', 'title': 'AI Influencer'},
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video Configuration'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  test('normalizes whitespace IDs, malformed entries, defaults and disabled models', () {
    final result = VideoToolConfiguration.fromResponse(
      config([
        null,
        7,
        false,
        {'id': ' sora-2 ', 'label': ' Sora 2 '},
        {'id': 'sora-2', 'label': 'Duplicate'},
        {'id': 'hidden', 'enabled': ' FALSE '},
        {'id': 'offline', 'status': ' DISABLED '},
        {'id': 'sora-2-pro', 'label': null},
      ]),
      tool: 'ai_video_pro',
      previousModel: 'missing',
    );
    expect(result.models.map((m) => m.id), ['sora-2', 'sora-2-pro']);
    expect(result.models.first.label, 'Sora 2');
    expect(result.selectedModel, 'sora-2');
    final preferred = config(nestedModels);
    (preferred['engines'] as List).first['default_model'] = ' sora-2-pro ';
    expect(
      VideoToolConfiguration.fromResponse(
        preferred,
        tool: 'ai_video_pro',
      ).selectedModel,
      'sora-2-pro',
    );
    expect(
      VideoToolConfiguration.fromResponse(
        config(nestedModels),
        tool: 'ai_video_pro',
        previousModel: 'sora-2-pro',
      ).selectedModel,
      'sora-2-pro',
    );
    expect(() => result.models.clear(), throwsUnsupportedError);
  });

  for (final malformed in [
    null,
    [],
    {'engines': null},
    {'engines': {}},
    {
      'engines': [
        null,
        {'id': 'other'},
      ],
    },
  ]) {
    testWidgets(
      'malformed Video Pro settings show retry instead of ErrorWidget: $malformed',
      (tester) async {
        var loads = 0;
        final api = nativeApi((path, _) async {
          if (path == '/video/tools') {
            return ++loads == 1 ? malformed : config(nestedModels);
          }
          return {'data': []};
        });
        await tester.pumpWidget(app(VideoToolScreen(module: module, api: api)));
        await tester.pumpAndSettle();
        expect(find.text('Retry'), findsOneWidget);
        expect(find.byType(ErrorWidget), findsNothing);
        expect(find.text('Video Configuration'), findsNothing);
        await tester.tap(find.text('Retry'));
        await tester.pumpAndSettle();
        expect(find.text('Video Configuration'), findsOneWidget);
        expect(find.text('Sora 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'over-nested model configuration is rejected before widget construction',
    (tester) async {
      dynamic models = {'id': 'sora-2'};
      for (var i = 0; i < 40; i++) {
        models = {'subModels': models};
      }
      final api = nativeApi((_, _) async => config(models));
      await tester.pumpWidget(app(VideoToolScreen(module: module, api: api)));
      await tester.pumpAndSettle();
      expect(
        find.text('Video settings could not be displayed. Please retry.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unknown model inputs and malformed gallery thumbnails cannot blank Create or Gallery',
    (tester) async {
      final api = nativeApi((path, _) async {
        if (path == '/video/tools') {
          return config([
            {
              'id': 'sora-2',
              'label': 'Sora 2',
              'inputs': [
                {'type': 'future-widget', 'value': null},
              ],
            },
          ]);
        }
        return {
          'data': [
            {
              'id': 1,
              'title': 'Saved video',
              'thumbnail_url': {'url': null},
              'status': 'complete',
              'tool_label': 'AI Video Pro with a long translated label',
            },
          ],
        };
      });
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(VideoToolScreen(module: module, api: api), scale: 1.6),
      );
      await tester.pumpAndSettle();
      expect(find.text('Video Configuration'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.video_library_outlined));
      await tester.pumpAndSettle();
      expect(find.text('Saved video'), findsOneWidget);
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final tool in ['ai_video', 'auto_edit_videos', 'video_agent']) {
    testWidgets(
      '$tool keeps its configuration form after Video Pro hardening',
      (tester) async {
        final api = nativeApi(
          (path, _) async => path == '/video/tools'
              ? {
                  'engines': [
                    {'id': tool},
                  ],
                }
              : {'data': []},
        );
        await tester.pumpWidget(
          app(VideoToolScreen(module: {'id': 'web:$tool'}, api: api)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Video Configuration'), findsOneWidget);
        expect(find.text('Target Duration'), findsOneWidget);
        expect(find.text('Aspect Ratio'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
