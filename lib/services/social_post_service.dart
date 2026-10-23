import 'dart:math';

import 'package:http/http.dart' as http;

import 'mobile_api.dart';
import 'image_attachment_picker.dart';

class SocialPostPage {
  final List<Map<String, dynamic>> posts;
  final int page, lastPage;
  const SocialPostPage(this.posts, this.page, this.lastPage);
}

class SocialPostService {
  final MobileApi api;
  SocialPostService(this.api);

  static String requestId() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final text = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
  }

  Future<List<Map<String, dynamic>>> accounts() async {
    final data = await api.request('/social-media/platforms');
    if (data is! List) {
      throw const ApiFailure(
        'Unable to read connected accounts. Please retry.',
      );
    }
    return data
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList();
  }

  Future<SocialPostPage> posts({
    String status = 'all',
    int page = 1,
    DateTime? day,
  }) async {
    final query = <String, String>{
      'status': status,
      'page': '$page',
      'per_page': '30',
    };
    if (day != null && status != 'draft') {
      query['from'] = DateTime(
        day.year,
        day.month,
        day.day,
      ).toUtc().toIso8601String();
      query['until'] = DateTime(
        day.year,
        day.month,
        day.day + 1,
      ).toUtc().toIso8601String();
    }
    final data = await api.request(
      '/social-media/posts?${Uri(queryParameters: query).query}',
    );
    if (data is List) {
      return SocialPostPage(
        data
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
        1,
        1,
      );
    }
    if (data is! Map ||
        data['data'] is! List ||
        data['current_page'] is! int ||
        data['last_page'] is! int) {
      throw const ApiFailure('Unable to read posts. Please retry.');
    }
    return SocialPostPage(
      (data['data'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
      data['current_page'] as int,
      data['last_page'] as int,
    );
  }

  Future<void> save(Map<String, dynamic> payload) async {
    await api.request('/social-media/posts', method: 'POST', body: payload);
  }

  Future<String> caption(String content, String platform) async {
    final data = await api.request(
      '/social-media/caption',
      method: 'POST',
      body: {'content': content, 'platform': platform, 'tone': 'Engaging'},
    );
    if (data is! Map ||
        data['result'] is! String ||
        (data['result'] as String).trim().isEmpty) {
      throw const ApiFailure(
        'The caption could not be generated. Please retry.',
      );
    }
    return data['result'] as String;
  }

  Future<void> delete(String id) async {
    if (!RegExp(r'^\d+$').hasMatch(id)) throw const ApiFailure('Invalid post.');
    await api.request('/social-media/posts/$id', method: 'DELETE');
  }

  Future<String> upload(List<int> bytes, String name, String mediaType) async {
    if (mediaType == 'image') return api.uploadImage(bytes, name);
    final mime = ImageAttachmentPicker.videoMimeType(bytes);
    if (mediaType != 'video' ||
        mime == null ||
        bytes.isEmpty ||
        bytes.length > 50 * 1024 * 1024) {
      throw const ApiFailure('Choose a video no larger than 50 MB.');
    }
    final request =
        http.MultipartRequest('POST', api.uri('/social-media/attachments'))
          ..headers.addAll(await api.headers())
          ..files.add(
            http.MultipartFile.fromBytes(
              'video',
              bytes,
              filename: name,
              contentType: http.MediaType.parse(mime),
            ),
          );
    request.headers.remove('Content-Type');
    try {
      final response = await http.Response.fromStream(
        await api.client.send(request).timeout(const Duration(seconds: 120)),
      ).timeout(const Duration(seconds: 120));
      final data = api.decodeResponse(response);
      if (data is! Map || data['url'] is! String) {
        throw const ApiFailure('The video upload did not complete.');
      }
      return data['url'] as String;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure(
        'Unable to upload this video. Check your connection and retry.',
      );
    }
  }
}
