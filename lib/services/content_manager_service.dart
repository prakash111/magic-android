import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'extension_workflow_service.dart';
import 'image_attachment_picker.dart';
import 'mobile_api.dart';

class ContentManagerAsset {
  final String id, title, url, type, mimeType;
  final String? thumbnailUrl;
  final int? size;
  final double? duration;
  final DateTime? createdAt;
  const ContentManagerAsset({
    required this.id,
    required this.title,
    required this.url,
    required this.type,
    this.mimeType = '',
    this.thumbnailUrl,
    this.size,
    this.duration,
    this.createdAt,
  });
  factory ContentManagerAsset.fromJson(Map data) {
    final url = '${data['url'] ?? ''}';
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        !['image', 'video', 'other'].contains(data['type'])) {
      throw const ApiFailure(
        'The server returned invalid media. Please refresh.',
      );
    }
    final thumbnail = Uri.tryParse('${data['thumbnail_url'] ?? ''}');
    return ContentManagerAsset(
      id: '${data['id'] ?? ''}',
      title: '${data['title'] ?? 'Media'}',
      url: url,
      type: '${data['type']}',
      mimeType: '${data['mime_type'] ?? ''}',
      thumbnailUrl:
          thumbnail?.scheme == 'https' &&
              thumbnail!.host.isNotEmpty &&
              thumbnail.userInfo.isEmpty
          ? thumbnail.toString()
          : null,
      size: num.tryParse('${data['size']}')?.toInt(),
      duration: num.tryParse('${data['duration']}')?.toDouble(),
      createdAt: DateTime.tryParse('${data['created_at']}'),
    );
  }
}

class ContentManagerPage {
  final List<ContentManagerAsset> items;
  final int page, lastPage, total, maxUploadBytes;
  const ContentManagerPage(
    this.items, {
    required this.page,
    required this.lastPage,
    required this.total,
    this.maxUploadBytes = 25 * 1024 * 1024,
  });
}

class ContentManagerService {
  final MobileApi api;
  ContentManagerService(this.api);
  Future<ContentManagerPage> list({
    String type = 'images',
    String sort = 'newest',
    String search = '',
    int page = 1,
  }) async {
    try {
      final query = Uri(
        queryParameters: {
          'type': type,
          'sort': sort,
          'search': search,
          'page': '$page',
          'per_page': '24',
        },
      ).query;
      final response = await api
          .request('/content-manager?$query')
          .timeout(const Duration(seconds: 10));
      if (response is! Map ||
          response['data'] is! List ||
          response['meta'] is! Map) {
        throw const ApiFailure(
          'Unable to read your media library. Please retry.',
        );
      }
      final meta = response['meta'] as Map;
      return ContentManagerPage(
        (response['data'] as List)
            .whereType<Map>()
            .map(ContentManagerAsset.fromJson)
            .toList(),
        page: num.tryParse('${meta['current_page']}')?.toInt() ?? page,
        lastPage: num.tryParse('${meta['last_page']}')?.toInt() ?? page,
        total: num.tryParse('${meta['total']}')?.toInt() ?? 0,
        maxUploadBytes:
            num.tryParse('${meta['max_upload_bytes']}')?.toInt() ??
            25 * 1024 * 1024,
      );
    } on TimeoutException {
      throw const ApiFailure(
        'The media library took too long to respond. Please retry.',
      );
    }
  }

  Future<WorkflowFile?> pick(String kind, int maxBytes) async {
    if (kind != 'file') {
      return ImageAttachmentPicker().pick(
        moduleId: 'content_manager',
        field: 'file',
        video: kind == 'video',
        maxBytes: maxBytes,
      );
    }
    try {
      final result = await SecureStore.invokeMapMethod<String, dynamic>(
        'pickFile',
        {'accept': '*/*'},
      );
      if (result == null) return null;
      final bytes = (result['bytes'] as List).cast<int>();
      if (bytes.isEmpty || bytes.length > maxBytes) {
        throw const ApiFailure(
          'The selected file is empty or exceeds the upload size limit.',
        );
      }
      return WorkflowFile(
        '${result['name'] ?? 'file'}'
            .split(RegExp(r'[/\\]'))
            .last
            .replaceAll(RegExp(r'[\r\n"\x00-\x1f]'), '_'),
        bytes,
      );
    } on PlatformException {
      throw const ApiFailure(
        'The file picker could not open this file. Please try again.',
      );
    }
  }

  Future<ContentManagerAsset> upload(
    WorkflowFile file, {
    void Function(double)? onProgress,
  }) async {
    final request =
        _ProgressUpload(api.uri('/content-manager/upload'), onProgress)
          ..headers.addAll(await api.headers())
          ..files.add(await file.multipart('file'));
    request.headers.remove('Content-Type');
    try {
      final response = await http.Response.fromStream(
        await api.client.send(request).timeout(const Duration(seconds: 120)),
      ).timeout(const Duration(seconds: 120));
      final data = api.decodeResponse(response);
      if (data is! Map || data['data'] is! Map) {
        throw const ApiFailure('The upload did not complete. Please retry.');
      }
      return ContentManagerAsset.fromJson(data['data'] as Map);
    } on TimeoutException {
      throw const ApiFailure(
        'The upload timed out. Check your connection and retry.',
      );
    }
  }
}

class _ProgressUpload extends http.MultipartRequest {
  final void Function(double)? onProgress;
  _ProgressUpload(Uri url, this.onProgress) : super('POST', url);
  @override
  http.ByteStream finalize() {
    final stream = super.finalize();
    final total = contentLength;
    var sent = 0;
    return http.ByteStream(
      stream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleData: (bytes, sink) {
            sent += bytes.length;
            if (total > 0) onProgress?.call((sent / total).clamp(0.0, 1.0));
            sink.add(bytes);
          },
        ),
      ),
    );
  }
}
