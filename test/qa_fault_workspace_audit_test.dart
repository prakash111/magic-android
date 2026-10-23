import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'qa_live_workspace_audit_test.dart' show AuditStore;

class FaultAuditClient extends http.BaseClient {
  final String mode;
  int attempts = 0;
  FaultAuditClient(this.mode);
  http.StreamedResponse response(Map body, int status) => http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: {'content-type': 'application/json'},
  );
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/license')) {
      return response({
        'status': 'success',
        'valid': true,
        'app': 'magicai',
        'features': ['chat', 'seo', 'image_gen', 'social_scheduler'],
        'session_token': 'controlled-fault-session',
        'session_expires_at': DateTime.now()
            .add(const Duration(hours: 1))
            .toUtc()
            .toIso8601String(),
      }, 200);
    }
    attempts++;
    if (mode == 'timeout') return Completer<http.StreamedResponse>().future;
    if (mode == 'offline') throw const SocketException('QA offline transport');
    if (mode == 'interrupted') {
      return http.StreamedResponse(
        Stream<List<int>>.error(
          http.ClientException('QA interrupted response'),
        ),
        200,
      );
    }
    if (mode == 'slow_response') {
      await Future<void>.delayed(const Duration(seconds: 13));
      return response({'message': 'QA delayed response'}, 503);
    }
    final status = int.parse(mode);
    return response({
      'message': 'QA $status response',
      'code': status == 403 ? 'forbidden' : 'request_failed',
    }, status);
  }
}

void main() {
  final catalogPath = Platform.environment['MAGICAI_QA_CATALOG_FILE'];
  final outputPath = Platform.environment['MAGICAI_QA_OUTPUT'];
  if (catalogPath == null || outputPath == null) {
    test(
      'fault audit requires explicit catalog and output',
      () {},
      skip: 'Opt-in audit matrix.',
    );
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  final catalog = jsonDecode(File(catalogPath).readAsStringSync()) as Map;
  final results = <Map<String, dynamic>>[];
  for (final raw in catalog['modules'] as List) {
    final module = Map<String, dynamic>.from(raw as Map);
    for (final mode in [
      '401',
      '403',
      '404',
      '500',
      'timeout',
      'offline',
      'slow_response',
      'interrupted',
    ]) {
      testWidgets('fault $mode ${module['id']}', (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final client = FaultAuditClient(mode);
        final store = AuditStore()
          ..values['access_token'] = 'controlled-fault-token'
          ..values['instance_hash'] = 'a' * 64;
        final api = MobileApi(client: client, store: store);
        MobileApi.failure.value = null;
        final errors = <String>[];
        final handler = FlutterError.onError;
        FlutterError.onError = (details) =>
            errors.add(details.exceptionAsString().split('\n').first);
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.darkTheme,
              home: NativeModuleScreen(module: module, api: api),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          await tester.pump(const Duration(seconds: 10));
          final spinnerAt11 = find
              .byType(CircularProgressIndicator)
              .evaluate()
              .isNotEmpty;
          final retryAt11 = find.text('Retry').evaluate().isNotEmpty;
          await tester.pump(const Duration(seconds: 40));
          await tester.pump();
          final retryAfter = find.text('Retry').evaluate().isNotEmpty;
          final spinnerAfter = find
              .byType(CircularProgressIndicator)
              .evaluate()
              .isNotEmpty;
          final before = client.attempts;
          if (retryAfter && mode != 'timeout' && mode != 'slow_response') {
            await tester.tap(find.text('Retry').first);
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
          }
          final result = <String, dynamic>{
            'id': module['id'],
            'title': module['display_title'] ?? module['title'],
            'mode': mode,
            'evidence_type': 'controlled transport fault; real Flutter widgets; not live API fault or Android radio test',
            'transport_exercised': client.attempts > 0,
            'spinner_at_11_seconds': spinnerAt11,
            'retry_at_11_seconds': retryAt11,
            'spinner_after_51_seconds': spinnerAfter,
            'retry_after_51_seconds': retryAfter,
            'retry_issued_another_request': client.attempts > before,
            'framework_errors': errors,
            'meets_requested_10_second_state':
                client.attempts > 0 &&
                !spinnerAt11 &&
                retryAt11 &&
                errors.isEmpty,
          };
          results.add(result);
          File('$outputPath/fault-widget-observations.json')
              .writeAsStringSync(jsonEncode(results));
        } finally {
          FlutterError.onError = handler;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 125));
        }
      });
    }
  }
}
