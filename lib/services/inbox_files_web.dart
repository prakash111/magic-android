import 'dart:convert';

import 'extension_workflow_service.dart';
import 'mobile_api.dart';

Future<Map<String, dynamic>> persistInboxFile(WorkflowFile file) async {
  if (file.bytes.length > 4 * 1024 * 1024) {
    throw const ApiFailure('Large browser attachments require a connection.');
  }
  return {
    'name': file.name,
    'mime': file.mimeType,
    'bytes': base64Encode(file.bytes),
  };
}

Future<WorkflowFile> restoreInboxFile(Map data) async => WorkflowFile(
  '${data['name']}',
  base64Decode('${data['bytes']}'),
  mimeType: data['mime'] as String?,
);
Future<void> removeInboxFile(Map data) async {}
