import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mobile_api.dart';
import 'social_post_service.dart';

class NativeExtensionService {
  final MobileApi api;
  final String moduleId;
  NativeExtensionService(this.api, this.moduleId);

  Future<Map<String, dynamic>> call(
    String operation, {
    Map<String, dynamic> values = const {},
    Map<String, dynamic> inputs = const {},
    Map<String, dynamic> files = const {},
    String? requestId,
  }) async {
    final payload = <String, dynamic>{
      'module_id': moduleId,
      'operation': operation,
      ...values,
      if (operation != 'load')
        'request_id': requestId ?? SocialPostService.requestId(),
      if (inputs.isNotEmpty) 'inputs': inputs,
    };
    dynamic data;
    if (files.isEmpty) {
      data = await api
          .request('/native/extension', method: 'POST', body: payload)
          .timeout(
            Duration(seconds: operation == 'load' ? 25 : 120),
            onTimeout: () => throw const ApiFailure(
              'This request is taking too long. Refresh before retrying.',
            ),
          );
    } else {
      final request = http.MultipartRequest(
        'POST',
        api.uri('/native/extension'),
      )..headers.addAll(await api.headers());
      request.headers.remove('Content-Type');
      for (final entry in payload.entries) {
        request.fields[entry.key] = entry.value is Map
            ? jsonEncode(entry.value)
            : '${entry.value}';
      }
      for (final entry in files.entries) {
        final bytes = base64Decode('${entry.value['bytes']}');
        if (bytes.length > 10 * 1024 * 1024) {
          throw const ApiFailure('Choose an image no larger than 10 MB.');
        }
        request.files.add(
          http.MultipartFile.fromBytes(
            'uploads[${entry.key}]',
            bytes,
            filename: '${entry.value['name']}',
          ),
        );
      }
      final response = await http.Response.fromStream(
        await api.client.send(request).timeout(const Duration(seconds: 120)),
      ).timeout(const Duration(seconds: 120));
      data = api.decodeResponse(response);
    }
    if (data is! Map) {
      throw const ApiFailure('Unable to read this workspace. Please retry.');
    }
    return Map<String, dynamic>.from(data);
  }
}
