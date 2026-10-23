import 'package:http/http.dart' as http;

import 'mobile_api.dart';
import 'extension_workflow_service.dart';
import 'social_post_service.dart';

class ChatToolsService {
  final MobileApi api;
  final String moduleId;
  const ChatToolsService(this.api, this.moduleId);

  Future<Map<String, dynamic>> execute(
    String operation, {
    int? id,
    int? sourceId,
    String query = '',
    Map<String, dynamic> inputs = const {},
    WorkflowFile? file,
    String? requestId,
  }) async {
    final body = <String, dynamic>{
      'module_id': moduleId,
      'operation': operation,
      'record_id': ?id,
      'source_id': ?sourceId,
      'query': query,
      'inputs': inputs,
      if (operation != 'list')
        'request_id': requestId ?? SocialPostService.requestId(),
    };
    dynamic result;
    if (file == null) {
      result = await api.request(
        '/native/chat-tools',
        method: 'POST',
        body: body,
      );
    } else {
      if (file.bytes.length > 10 * 1024 * 1024) {
        throw const ApiFailure('Choose a file smaller than 10 MB.');
      }
      final request = http.MultipartRequest(
        'POST',
        api.uri('/native/chat-tools'),
      )..headers.addAll(await api.headers());
      request.headers.remove('Content-Type');
      for (final entry in body.entries) {
        if (entry.value != null && entry.key != 'inputs') {
          request.fields[entry.key] = '${entry.value}';
        }
      }
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes, filename: file.name),
      );
      result = api.decodeResponse(
        await http.Response.fromStream(
          await api.client.send(request).timeout(const Duration(seconds: 120)),
        ),
      );
    }
    if (result is! Map ||
        result['data'] is! List ||
        result['sources'] is! List) {
      throw const ApiFailure('Unable to load this chat tool.');
    }
    return Map<String, dynamic>.from(result);
  }
}
