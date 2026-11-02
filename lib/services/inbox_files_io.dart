import 'dart:io';

import 'extension_workflow_service.dart';

Future<Map<String, dynamic>> persistInboxFile(WorkflowFile file) async {
  final directory = await Directory.systemTemp.createTemp('magicai-inbox-');
  final path = '${directory.path}/attachment';
  await File(path).writeAsBytes(file.bytes, flush: true);
  return {'name': file.name, 'mime': file.mimeType, 'path': path};
}

Future<WorkflowFile> restoreInboxFile(Map data) async {
  final path = '${data['path']}';
  return WorkflowFile(
    '${data['name']}',
    await File(path).readAsBytes(),
    mimeType: data['mime'] as String?,
    path: path,
  );
}

Future<void> removeInboxFile(Map data) async {
  final file = File('${data['path']}');
  if (await file.exists()) {
    await file.delete();
    await file.parent.delete();
  }
}
