import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuditStore extends SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class AuditClient extends http.BaseClient {
  final http.Client delegate;
  final File log;
  final rows = <Map<String, dynamic>>[];
  String screen = '';
  int pending = 0;
  final pendingByScreen = <String, int>{};
  AuditClient(this.delegate, this.log);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final watch = Stopwatch()..start();
    final label = screen;
    pending++;
    pendingByScreen[label] = (pendingByScreen[label] ?? 0) + 1;
    final headers = {
      for (final e in request.headers.entries)
        e.key:
            [
              'authorization',
              'x-mobile-session',
              'x-instance-hash',
            ].contains(e.key.toLowerCase())
            ? '[REDACTED]'
            : e.value,
    };
    dynamic payload;
    if (request is http.Request && request.body.isNotEmpty) {
      try {
        payload = jsonDecode(request.body);
        if (payload is Map && payload.containsKey('instance_hash')) {
          payload['instance_hash'] = '[REDACTED]';
        }
      } catch (_) {
        payload = '[non-JSON body]';
      }
    }
    var recorded = false;
    void record(int? status, [String? error]) {
      if (recorded) return;
      recorded = true;
      final row = <String, dynamic>{
        'screen_id': label,
        'endpoint': request.url.toString(),
        'method': request.method,
        'headers': headers,
        'payload': payload,
        'status': status,
        'elapsed_ms': watch.elapsedMilliseconds,
        'transport_error': error,
        'evidence_type': 'actual Flutter widgets / live HTTPS; host test engine, not Android',
      };
      rows.add(row);
      log.writeAsStringSync('${jsonEncode(row)}\n', mode: FileMode.append);
      pending--;
      pendingByScreen[label] = (pendingByScreen[label] ?? 1) - 1;
    }

    try {
      final response = await delegate.send(request);
      final stream = response.stream.transform<List<int>>(
        StreamTransformer.fromHandlers(
          handleData: (data, sink) => sink.add(data),
          handleError: (Object error, StackTrace trace, sink) {
            record(response.statusCode, error.runtimeType.toString());
            sink.addError(error, trace);
          },
          handleDone: (sink) {
            record(response.statusCode);
            sink.close();
          },
        ),
      );
      return http.StreamedResponse(
        stream,
        response.statusCode,
        headers: response.headers,
        request: request,
      );
    } catch (error) {
      record(null, error.runtimeType.toString());
      rethrow;
    }
  }

  @override
  void close() => delegate.close();
}

Future<void> main() async {
  final sessionPath = Platform.environment['MAGICAI_QA_SESSION_FILE'];
  final outputPath = Platform.environment['MAGICAI_QA_OUTPUT'];
  final catalogPath = Platform.environment['MAGICAI_QA_CATALOG_FILE'];
  if (sessionPath == null || outputPath == null || catalogPath == null) {
    test(
      'live audit requires an explicitly supplied private session',
      () {},
      skip:
          'Opt-in live audit; never use production credentials in routine CI.',
    );
    return;
  }
  final transport = IOClient(HttpClient());
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});
  final auth = jsonDecode(File(sessionPath).readAsStringSync()) as Map;
  final catalog = jsonDecode(File(catalogPath).readAsStringSync()) as Map;
  final output = Directory(outputPath)..createSync(recursive: true);
  final network = AuditClient(
    transport,
    File('${output.path}/widget-network.jsonl'),
  );
  final store = AuditStore()
    ..values['access_token'] = '${auth['token']}'
    ..values['instance_hash'] = '${auth['instance_hash']}';
  final api = MobileApi(client: network, store: store);
  final channelValues = <String, String>{};
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SecureStore.channel, (call) async {
        final args = call.arguments as Map? ?? {};
        if (call.method == 'read') return channelValues['${args['key']}'];
        if (call.method == 'write') {
          channelValues['${args['key']}'] = '${args['value']}';
        }
        if (call.method == 'delete') channelValues.remove('${args['key']}');
        return null;
      });
  await MobileApi.instance.store.write('access_token', '${auth['token']}');
  await MobileApi.instance.store.write(
    'instance_hash',
    '${auth['instance_hash']}',
  );
  final preview =
      '${Directory.current.parent.path}/license-builder/app-builder/assets/magicai-preview/assets/fonts';
  for (final e in {
    'Roboto': '$preview/fallback/Roboto-Regular.ttf',
    'MaterialIcons': '$preview/MaterialIcons-Regular.otf',
  }.entries) {
    if (File(e.value).existsSync()) {
      final bytes = File(e.value).readAsBytesSync();
      await (FontLoader(
        e.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  }
  final modules = (catalog['modules'] as List).cast<Map>();
  final results = <Map<String, dynamic>>[];
  for (final module in modules) {
    testWidgets('live workspace ${module['id']}', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      network.screen = '${module['id']}';
      MobileApi.failure.value = null;
      final start = network.rows.length;
      if (module['route_type'] == 'visual_tool' && !Platform.isAndroid) {
        final response = await tester.runAsync(
          () => api
              .request(
                '/native/visual',
                method: 'POST',
                body: {
                  'module_id': module['id'],
                  'operation': 'describe',
                  'kind': module['visual_kind'],
                },
              )
              .timeout(const Duration(seconds: 10)),
        );
        if (response is Map && response['lease_token'] != null) {
          await tester.runAsync(
            () => api.request(
              '/native/visual',
              method: 'POST',
              body: {
                'module_id': module['id'],
                'operation': 'close',
                'lease_token': response['lease_token'],
              },
            ),
          );
        }
        results.add({
          'id': module['id'],
          'title': module['display_title'] ?? module['title'],
          'route_type': module['route_type'],
          'result': 'Requires Android platform view; host render not exercised',
          'evidence_type': 'Live editor session API only; Android rendering requires a device',
          'framework_errors': [],
          'spinner_at_end': false,
          'placeholder_text': [],
          'requests': network.rows
              .sublist(start)
              .map(
                (r) => {
                  'endpoint': r['endpoint'],
                  'status': r['status'],
                  'elapsed_ms': r['elapsed_ms'],
                },
              )
              .toList(),
        });
        File('${output.path}/workspace-widget-observations.json')
            .writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert(results),
            );
        return;
      }
      final errors = <String>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details.exceptionAsString().split('\n').first);
      };
      final watch = Stopwatch()..start();
      final boundary = GlobalKey();
      try {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: AppTheme.darkTheme,
              home: NativeModuleScreen(
                module: Map<String, dynamic>.from(module),
                api: api,
              ),
            ),
          ),
        );
        while (watch.elapsedMilliseconds < 10000) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump(const Duration(milliseconds: 100));
          final loading = find
              .byType(CircularProgressIndicator)
              .evaluate()
              .isNotEmpty;
          if ((network.pendingByScreen[network.screen] ?? 0) <= 0 &&
              !loading &&
              watch.elapsedMilliseconds >= 500) {
            break;
          }
        }
        await tester.pump(const Duration(milliseconds: 400));
        final texts = tester
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
        final placeholders = texts
            .where(
              (s) => RegExp(
                r'workspace is ready|Explore your workspace|being prepared|not available in the app|available here|Choose a tool',
                caseSensitive: false,
              ).hasMatch(s),
            )
            .toList();
        final spinner = find
            .byType(CircularProgressIndicator)
            .evaluate()
            .isNotEmpty;
        final requests = network.rows.sublist(start);
        final result = <String, dynamic>{
          'id': module['id'],
          'title': module['display_title'] ?? module['title'],
          'category': module['category'],
          'route_type': module['route_type'],
          'evidence_type':
              'live Flutter widget render; not signed Android/device',
          'elapsed_ms': watch.elapsedMilliseconds,
          'spinner_at_end': spinner,
          'ten_second_deadline_exceeded':
              spinner && watch.elapsedMilliseconds >= 10000,
          'placeholder_text': placeholders,
          'framework_errors': errors,
          'retry_visible': texts.any((s) => s.toLowerCase() == 'retry'),
          'text_widgets': texts.length,
          'requests': requests
              .map(
                (r) => {
                  'endpoint': r['endpoint'],
                  'method': r['method'],
                  'status': r['status'],
                  'elapsed_ms': r['elapsed_ms'],
                },
              )
              .toList(),
          'result': errors.isNotEmpty
              ? 'Framework/layout error'
              : placeholders.isNotEmpty
              ? 'Placeholder text'
              : spinner
              ? 'Spinner at deadline'
              : requests.any((r) => r['status'] != 200)
              ? 'API error'
              : 'Rendered; end-to-end task untested',
        };
        results.add(result);
        File('${output.path}/workspace-widget-observations.json')
            .writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert(results),
            );
        if (placeholders.isNotEmpty &&
            [
              'AI Presentation',
              'Influencer Avatar',
              'AI Detector',
              'AI Plagiarism',
            ].contains('${module['title']}')) {
          final render = boundary.currentContext?.findRenderObject();
          if (render is RenderRepaintBoundary) {
            await tester.runAsync(() async {
              final image = await render.toImage(pixelRatio: 1);
              final png = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (png != null) {
                File(
                  '${output.path}/screen-${module['id'].toString().replaceAll(RegExp('[^a-zA-Z0-9]'), '-')}.png',
                ).writeAsBytesSync(png.buffer.asUint8List());
              }
              image.dispose();
            });
          }
        }
        debugPrint(
          'QA_RESULT ${jsonEncode({'id': module['id'], 'result': result['result'], 'ms': result['elapsed_ms']})}',
        );
      } finally {
        FlutterError.onError = oldHandler;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 125));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 1050)),
        );
      }
    }, timeout: const Timeout(Duration(seconds: 50)));
  }
  tearDownAll(() {
    network.close();
    MobileApi.instance.client.close();
  });
}
