import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mobile_api.dart';

class WorkflowFile {
  final String name;
  final List<int> bytes;
  final String? mimeType, path;
  const WorkflowFile(this.name, this.bytes, {this.mimeType, this.path});
  Future<http.MultipartFile> multipart(String field) async {
    if (bytes.isEmpty) {
      throw const ApiFailure('The selected file is empty. Choose it again.');
    }
    final type = http.MediaType.parse(
      mimeType ??
          (name.toLowerCase().endsWith('.png')
              ? 'image/png'
              : (RegExp(r'\.jpe?g$', caseSensitive: false).hasMatch(name)
                    ? 'image/jpeg'
                    : (name.toLowerCase().endsWith('.webp')
                          ? 'image/webp'
                          : 'application/octet-stream'))),
    );
    return path == null
        ? http.MultipartFile.fromBytes(
            field,
            bytes,
            filename: name,
            contentType: type,
          )
        : http.MultipartFile.fromPath(
            field,
            path!,
            filename: name,
            contentType: type,
          );
  }
}

class ExtensionWorkflowService {
  final MobileApi api;
  final String moduleId;
  ExtensionWorkflowService(this.api, this.moduleId);

  Future<Map<String, dynamic>> describe() => _call('describe');
  Future<Map<String, dynamic>> history({bool refresh = false}) =>
      _call(refresh ? 'status' : 'history');

  Future<Map<String, dynamic>> generate(
    Map<String, dynamic> inputs,
    Map<String, WorkflowFile> files, {
    required String requestId,
  }) async {
    if (files.isEmpty) {
      return _call('generate', {'inputs': inputs, 'request_id': requestId});
    }
    final request = http.MultipartRequest('POST', api.uri('/native/workflow'))
      ..headers.addAll(await api.headers())
      ..fields.addAll({
        'module_id': moduleId,
        'operation': 'generate',
        'request_id': requestId,
        'inputs': jsonEncode(inputs),
      });
    request.headers.remove('Content-Type');
    try {
      for (final entry in files.entries) {
        if (entry.value.bytes.length > 50 * 1024 * 1024) {
          throw const ApiFailure('Choose a file no larger than 50 MB.');
        }
        request.files.add(await entry.value.multipart('uploads[${entry.key}]'));
      }
      final response = await http.Response.fromStream(
        await api.client.send(request).timeout(const Duration(seconds: 120)),
      ).timeout(const Duration(seconds: 120));
      final data = api.decodeResponse(response);
      if (data is! Map<String, dynamic>) {
        throw const ApiFailure('Invalid workflow response.');
      }
      return data;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'Unable to submit. Check history before retrying this request.',
      );
    }
  }

  Future<Map<String, dynamic>> delete(int id, String requestId) =>
      _call('delete', {'record_id': id, 'request_id': requestId});

  Future<Map<String, dynamic>> export(int projectId, String requestId) =>
      _call('export', {'record_id': projectId, 'request_id': requestId});

  Future<Map<String, dynamic>> _call(
    String operation, [
    Map<String, dynamic> values = const {},
  ]) async {
    final data = await api.request(
      '/native/workflow',
      method: 'POST',
      body: {'module_id': moduleId, 'operation': operation, ...values},
    );
    if (data is! Map<String, dynamic>) {
      throw const ApiFailure('Invalid workflow response.');
    }
    return data;
  }
}

class VisualWidgetSession {
  final Uri url;
  final Uri entry;
  final String nonce;
  final String lease;
  final List<String> commands;
  VisualWidgetSession._(
    this.url,
    this.entry,
    this.nonce,
    this.lease,
    this.commands,
  );

  factory VisualWidgetSession.parse(Map data, Uri origin) {
    final url = Uri.tryParse('${data['url']}');
    final entry = Uri.tryParse('${data['entry_url']}');
    final nonce = '${data['handoff_token']}';
    final lease = '${data['lease_token']}';
    final expiry = DateTime.tryParse('${data['expires_at']}');
    bool trusted(Uri? value) =>
        value != null &&
        value.scheme == 'https' &&
        value.host == origin.host &&
        value.port == 443 &&
        value.userInfo.isEmpty &&
        value.fragment.isEmpty;
    if (!trusted(url) ||
        !trusted(entry) ||
        !RegExp(r'^/(?:magicai-mobile|mobile)/open/[a-zA-Z0-9]{64}$')
            .hasMatch(url!.path) ||
        !entry!.path.startsWith('/dashboard/user/') ||
        !RegExp(r'^[a-zA-Z0-9]{64}$').hasMatch(nonce) ||
        !RegExp(r'^[a-zA-Z0-9]{64}$').hasMatch(lease) ||
        expiry == null ||
        !expiry.isAfter(DateTime.now())) {
      throw const ApiFailure('Unable to verify the visual editor session.');
    }
    final commands = (data['commands'] as List? ?? [])
        .whereType<String>()
        .where(['save', 'export'].contains)
        .toList();
    return VisualWidgetSession._(url, entry, nonce, lease, commands);
  }

  Map<String, dynamic>? readMessage(Object? message) {
    if (message is! String || message.length > 28 * 1024 * 1024) return null;
    try {
      final data = jsonDecode(message);
      if (data is! Map<String, dynamic> ||
          data['version'] != 1 ||
          data['nonce'] != nonce ||
          ![
            'ready',
            'dirty',
            'saved',
            'error',
            'export',
            'download',
          ].contains(data['type']) ||
          data['payload'] is! Map) {
        return null;
      }
      return data;
    } catch (_) {
      return null;
    }
  }
}
