import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:magicai_mobile/screens/home_screen.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/workspace_catalog.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'qa_live_workspace_audit_test.dart' show AuditStore;

class CapturedApiClient extends http.BaseClient {
  final Directory fixtures;
  final paths = <String>[];
  bool interrupt = false, delayConfig = false;
  CapturedApiClient(this.fixtures);
  dynamic fixture(String filename) =>
      jsonDecode(File('${fixtures.path}/$filename.json').readAsStringSync());
  http.StreamedResponse response(Object body, [int status = 200]) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path.replaceFirst('/api/mobile/v1', '');
    paths.add(path);
    if (path == '/license') {
      return response({
        'status': 'success',
        'valid': true,
        'app': 'magicai',
        'features': ['chat', 'seo', 'social_scheduler', 'image_gen'],
        'session_token': 'replay-only-session',
        'session_expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toIso8601String(),
      });
    }
    if (path == '/config') {
      if (delayConfig) await Future<void>.delayed(const Duration(seconds: 1));
      return response(fixture('config'));
    }
    final files = {
      '/auth/profile': 'auth-profile',
      '/credits': 'credits',
      '/chat/options': 'chat-options',
      '/chat/personas': 'chat-personas',
      '/chat/models': 'chat-models',
      '/social-media/posts': 'social-media-posts',
      '/social-media/platforms': 'social-media-platforms',
    };
    if (files.containsKey(path)) return response(fixture(files[path]!));
    if (path == '/chat/conversations') {
      return request.method == 'POST'
          ? response({'id': 77700001}, 201)
          : response(fixture('chat-conversations'));
    }
    if (path.endsWith('/stream') && interrupt) {
      Stream<List<int>> chunks() async* {
        yield utf8.encode('data: {"delta":"Partial reply"}\n\n');
        throw http.ClientException('controlled interrupted SSE');
      }

      return http.StreamedResponse(
        chunks(),
        200,
        headers: {'content-type': 'text/event-stream'},
      );
    }
    if (path == '/native/screen') {
      final body = jsonDecode((request as http.Request).body) as Map;
      return response(
        fixture('screen-${body['module_id'].toString().replaceAll(':', '-')}'),
      );
    }
    return response({
      'message': 'No captured response for this test path.',
    }, 404);
  }
}

Future<void> main() async {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final private = Platform.environment['MAGICAI_QA_PRIVATE'];
  final out = Platform.environment['MAGICAI_QA_OUTPUT'];
  if (private == null || out == null) {
    test(
      'layout audit requires captured private fixtures',
      () {},
      skip: 'Opt-in audit.',
    );
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final preview =
      '${Directory.current.parent.path}/license-builder/app-builder/assets/magicai-preview/assets/fonts';
  for (final entry in {
    'Roboto': '$preview/fallback/Roboto-Regular.ttf',
    'MaterialIcons':
        '${Platform.environment['MAGICAI_QA_FLUTTER_SDK'] ?? '/tmp/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    if (File(entry.value).existsSync()) {
      final bytes = File(entry.value).readAsBytesSync();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  }
  ThemeData auditTheme(bool light) {
    final theme = light ? AppTheme.lightTheme : AppTheme.darkTheme;
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(
        titleTextStyle: theme.appBarTheme.titleTextStyle?.copyWith(
          fontFamily: 'Roboto',
        ),
      ),
    );
  }

  final results = <Map<String, dynamic>>[];
  void save(Map<String, dynamic> row) {
    results.add({
      'evidence_type': 'actual Flutter widgets replaying captured live JSON; not Android or fresh network',
      ...row,
    });
    File('$out/layout-interaction-observations.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
  }

  final catalog =
      jsonDecode(File('$private/config.json').readAsStringSync()) as Map;
  final modules = (catalog['modules'] as List)
      .map((m) => Map<String, dynamic>.from(m as Map))
      .toList();
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> select(WidgetTester tester, String tab) async {
    await tester.tap(
      find
          .descendant(of: find.byType(NavigationBar), matching: find.text(tab))
          .last,
    );
    await settle(tester);
  }

  MobileApi api(CapturedApiClient c) => MobileApi(
    client: c,
    store: AuditStore()
      ..values['access_token'] = 'replay-only-token'
      ..values['instance_hash'] = 'c' * 64,
  );
  Future<void> snapshot(WidgetTester tester, GlobalKey key, String name) async {
    final render = key.currentContext?.findRenderObject();
    if (render is RenderRepaintBoundary) {
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        if (bytes != null) {
          File('$out/$name.png').writeAsBytesSync(bytes.buffer.asUint8List());
        }
        image.dispose();
      });
    }
  }

  for (final setting in [
    ('small-dark', const Size(360, 640), 1.0, false),
    ('normal-dark', const Size(390, 844), 1.0, false),
    ('large-dark', const Size(430, 932), 1.0, false),
    ('font130-dark', const Size(390, 844), 1.3, false),
    ('landscape-font130', const Size(844, 390), 1.3, false),
    ('font130-light', const Size(390, 844), 1.3, true),
    ('keyboard-font130', const Size(390, 844), 1.3, false),
  ]) {
    testWidgets('layout ${setting.$1}', (tester) async {
      tester.view.physicalSize = setting.$2;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = CapturedApiClient(Directory(private));
      final service = api(client);
      final errors = <String>[];
      final old = FlutterError.onError;
      FlutterError.onError = (details) =>
          errors.add(details.exceptionAsString().split('\n').first);
      try {
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: auditTheme(setting.$4),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(setting.$3),
                viewInsets: setting.$1 == 'keyboard-font130'
                    ? const EdgeInsets.only(bottom: 320)
                    : EdgeInsets.zero,
              ),
              child: child!,
            ),
            home: HomeScreen(onThemeChanged: (_) {}, api: service),
          ),
        );
        await settle(tester);
        for (final tab in [
          'Home',
          'Explore',
          'Chatbot',
          'Calendar',
          'Account',
        ]) {
          final before = errors.length;
          await select(tester, tab);
          final smallTargets = <Map<String, dynamic>>[];
          for (final e
              in find
                  .byWidgetPredicate(
                    (w) =>
                        w is ButtonStyleButton ||
                        w is IconButton ||
                        w is ChoiceChip,
                  )
                  .evaluate()) {
            final box = e.renderObject;
            if (box is RenderBox &&
                box.hasSize &&
                box.size.height > 0 &&
                box.size.height < 48) {
              smallTargets.add({
                'widget': e.widget.runtimeType.toString(),
                'height': box.size.height,
              });
            }
          }
          var clipped = 0;
          for (final e in find.byType(RichText).evaluate()) {
            final r = e.renderObject;
            if (r is RenderParagraph && r.didExceedMaxLines) clipped++;
          }
          save({
            'test': 'layout',
            'viewport': setting.$1,
            'tab': tab,
            'active_navigation_index': tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            'simulated_keyboard_inset': setting.$1 == 'keyboard-font130'
                ? 320
                : 0,
            'size': '${setting.$2.width}x${setting.$2.height}',
            'text_scale': setting.$3,
            'light': setting.$4,
            'framework_errors': errors.sublist(before),
            'small_rendered_targets': smallTargets,
            'clipped_paragraphs': clipped,
            'calendar_grid_visible': find
                .byType(CalendarDatePicker)
                .evaluate()
                .isNotEmpty,
          });
        }
      } finally {
        FlutterError.onError = old;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 125));
      }
    });
  }
  testWidgets('search categories and refresh routes', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = CapturedApiClient(Directory(private));
    final service = api(client);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: auditTheme(false),
        home: HomeScreen(onThemeChanged: (_) {}, api: service),
      ),
    );
    await settle(tester);
    for (final tab in ['Home', 'Explore', 'Chatbot', 'Calendar', 'Account']) {
      await select(tester, tab);
      final before = client.paths.length;
      await tester.tap(find.byTooltip('Refresh'));
      await settle(tester);
      save({
        'test': 'header_refresh',
        'tab': tab,
        'refetched_paths': client.paths.sublist(before),
        'actual_child_data_refetched': tab == 'Chatbot'
            ? client.paths.sublist(before).any((p) => p.startsWith('/chat/'))
            : tab == 'Calendar'
            ? client.paths.sublist(before).contains('/social-media/posts')
            : client.paths.sublist(before).contains('/config'),
      });
      final scrollables = find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      );
      final pullBefore = client.paths.length;
      if (scrollables.evaluate().isNotEmpty) {
        await tester.drag(scrollables.first, const Offset(0, 400));
        await tester.pump(const Duration(seconds: 1));
        await settle(tester);
      }
      save({
        'test': 'pull_refresh',
        'tab': tab,
        'refetched_paths': client.paths.sublist(pullBefore),
      });
    }
    await select(tester, 'Explore');
    final search = find.widgetWithText(TextField, 'Search tools...');
    for (final query in ['invoice', 'zzzz-no-workspace-qa-match', '']) {
      await tester.enterText(search, query);
      await settle(tester);
      save({
        'test': 'explore_search',
        'query': query,
        'matching_inventory_count': groupedWorkspaces(
          modules,
          query: query,
        ).values.fold<int>(0, (n, list) => n + list.length),
        'no_match_message_visible': find
            .text('No workspaces match your search.')
            .evaluate()
            .isNotEmpty,
      });
    }
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: auditTheme(false),
        home: Scaffold(
          body: WorkspaceScreen(
            modules: modules,
            refresh: () async {},
            api: service,
          ),
        ),
      ),
    );
    await settle(tester);
    final chips = find.byType(ChoiceChip);
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, 'CRM'),
      180,
      scrollable: find
          .descendant(
            of: find.byWidgetPredicate(
              (w) => w is ListView && w.scrollDirection == Axis.horizontal,
            ),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'CRM'));
    await settle(tester);
    save({
      'test': 'category_chip',
      'category': 'CRM',
      'section_visible': find
          .byKey(const ValueKey('workspace-section-CRM'))
          .evaluate()
          .isNotEmpty,
      'matching_inventory_count': groupedWorkspaces(
        modules,
        category: 'CRM',
      ).values.fold<int>(0, (n, list) => n + list.length),
      'chips_rendered': chips.evaluate().length,
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 125));
  });
  for (final id in [
    'web:ai_presentation',
    'web:ai_image_pro_edit',
    'web:ai_detector_extension',
    'web:ai_plagiarism_extension',
  ]) {
    testWidgets('captured screen $id', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final client = CapturedApiClient(Directory(private));
      final service = api(client);
      final key = GlobalKey();
      final module = modules.firstWhere((m) => m['id'] == id);
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: auditTheme(false),
            home: Scaffold(
              appBar: AppBar(title: Text('${module['title']}')),
              body: NativeSchemaScreen(module: module, api: service),
            ),
          ),
        ),
      );
      await settle(tester);
      final texts = [
        ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
        ...tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((w) => w.data ?? ''),
      ];
      save({
        'test': 'captured_schema',
        'id': id,
        'text_field_count': find.byType(TextFormField).evaluate().length,
        'duplicate_my_presentations': texts
            .where((s) => s == 'My Presentations')
            .length,
        'literal_loading_text': texts
            .where((s) => s.contains('Loading'))
            .toList(),
        'zero_percent_report_before_input': texts.any((s) => s == '0% Match'),
      });
      await snapshot(tester, key, 'captured-${id.replaceAll(':', '-')}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 125));
    });
  }
  testWidgets('interrupted chat reply and retry', (tester) async {
    final client = CapturedApiClient(Directory(private))..interrupt = true;
    final service = api(client);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: auditTheme(false),
        home: Scaffold(body: ServerChatScreen(api: service)),
      ),
    );
    await settle(tester);
    final input = find.widgetWithText(TextField, 'Message your assistant');
    final before = client.paths.length;
    await tester.tap(find.byTooltip('Send message'));
    await settle(tester);
    save({
      'test': 'chat_empty_message',
      'generation_requests': client.paths
          .sublist(before)
          .where((p) => p.endsWith('/stream'))
          .length,
    });
    await tester.enterText(input, 'QA interruption');
    await tester.tap(find.byTooltip('Send message'));
    await settle(tester);
    final partial = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .any((w) => (w.data ?? '').contains('Partial reply'));
    final retry = find.text('Retry');
    final retryWasVisible = retry.evaluate().isNotEmpty;
    final previous = client.paths.where((p) => p.endsWith('/stream')).length;
    if (retry.evaluate().isNotEmpty) {
      await tester.tap(retry.first);
      await settle(tester);
    }
    save({
      'test': 'chat_interrupted_reply',
      'partial_reply_visible': partial,
      'retry_visible_before_tap': retryWasVisible,
      'retry_visible_after_tap': retry.evaluate().isNotEmpty,
      'retry_reissued_generation':
          client.paths.where((p) => p.endsWith('/stream')).length > previous,
    });
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 125));
  });
}
