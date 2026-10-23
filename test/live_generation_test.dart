import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:magicai_mobile/services/ai_model_selection.dart';
import 'package:magicai_mobile/services/document_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_test.dart' show MemorySecureStore;

void main() {
  test(
    'live tools generate save filter edit and delete their own history',
    () async {
      final credentials = jsonDecode(
        File(const String.fromEnvironment('MAGICAI_LIVE_CREDENTIALS'))
            .readAsStringSync(),
      ) as Map;
      final origin = Uri.parse(credentials['origin'] as String);
      expect(origin.scheme, 'https');
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      final client = http.Client();
      final records = <Map<String, dynamic>>[];
      final result = File(const String.fromEnvironment('MAGICAI_LIVE_RESULTS'));
      try {
        SharedPreferences.setMockInitialValues({});
        final api = MobileApi(
          origin: origin,
          client: client,
          store: MemorySecureStore()
            ..values['access_token'] = credentials['access_token'] as String,
        );
        final config = await api.request('/config') as Map;
        AiModelSelection.configure(api, config);
        final selection = AiModelSelection(api);
        final models = await selection.models();
        var model = await selection.resolve(models);
        expect(model, config['ai']['default_model_id']);
        expect(model, isNotNull);
        const requestedModel = String.fromEnvironment('MAGICAI_LIVE_MODEL_ID');
        if (requestedModel.isNotEmpty) {
          await selection.select(requestedModel, models);
          model = await selection.resolve(models);
          expect(model, requestedModel);
        }
        final inputs = {
          'math_question': {
            'question': 'Explain step by step why 2 + 2 = 4, then give a practice problem. This is a Mobile QA Writer test.',
          },
          'cover_letter': {
            'job_title': 'Flutter Developer',
            'company_name': 'Example Software',
            'your_name': 'Mobile QA Writer',
            'your_skills': 'Flutter, Dart, Laravel API integration',
          },
          'personal_bio': {
            'your_name': 'Mobile QA Writer',
            'your_summary': 'A software engineer who builds accessible mobile applications with Flutter and Laravel.',
          },
        };
        const requestedTool = String.fromEnvironment('MAGICAI_LIVE_TOOL');
        for (final entry in inputs.entries.where(
          (entry) => requestedTool.isEmpty || entry.key == requestedTool,
        )) {
          final clock = Stopwatch()..start();
          final prepared = await api.request(
            '/tools/${entry.key}/run',
            method: 'POST',
            body: {'model': model!, 'inputs': entry.value},
          ) as Map;
          final record = <String, dynamic>{
            'slug': entry.key,
            'document_id': prepared['message_id'],
            'model': model,
          };
          records.add(record);
          result.writeAsStringSync(jsonEncode(records));
          final output = await api
              .stream(prepared['stream_endpoint'] as String, legacy: true)
              .join();
          expect(output.trim().length, greaterThan(50));
          final documents = await api.request('/documents') as Map;
          final saved = (documents['data'] as List)
              .whereType<Map>()
              .singleWhere((row) => row['id'] == record['document_id']);
          expect(saved['response'], output);
          expect(saved['model'], model);
          record.addAll({
            'characters': output.length,
            'elapsed_ms': clock.elapsedMilliseconds,
            'saved': true,
          });
          final service = DocumentService(api);
          final history = await service.list(templateId: entry.key);
          expect(history.total, greaterThanOrEqualTo(1));
          expect(
            history.documents.every(
              (document) => document.data['template_id'] == entry.key,
            ),
            isTrue,
          );
          expect(history.documents.first.id, prepared['message_id']);
          expect(
            history.documents.first.promptPreview,
            contains('Mobile QA Writer'),
          );
          final persisted = await service.save(
            id: prepared['message_id'] as int,
            title: 'Mobile QA ${entry.key}',
            content: output,
          );
          expect(persisted.storedLocally, isTrue);
          expect((await service.get(persisted.id)).content, output);
          final edited = await service.save(
            id: persisted.id,
            title: 'Mobile QA edited ${entry.key}',
            content: '$output\n\nVerified document editing.',
            revision: persisted.revision,
            update: true,
          );
          expect(
            (await service.get(edited.id)).content,
            endsWith('Verified document editing.'),
          );
          await service.delete(edited.id);
          await expectLater(
            service.get(edited.id),
            throwsA(
              isA<ApiFailure>().having((error) => error.status, 'status', 404),
            ),
          );
          expect(
            (await service.list(templateId: entry.key)).documents
                .any((document) => document.id == edited.id),
            isFalse,
          );
          record['document_actions_verified'] = true;
          record['template_history_verified'] = true;
          result.writeAsStringSync(jsonEncode(records));
        }
      } finally {
        client.close();
        HttpOverrides.global = overrides;
      }
    },
    skip: !const bool.fromEnvironment('MAGICAI_LIVE_GENERATION'),
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
