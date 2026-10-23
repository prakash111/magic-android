import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/extension_workflow_screen.dart';
import 'package:magicai_mobile/screens/native_creative_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

const studioProbeImageBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAw0lEQVR4nO3QsQlCURTA0Fe5qOCITuIiTqAb/O5yrpgiZSDk3J6vzxX3x/uSX/ePDtB+A3SA9hugA7TfAB2g/bM9cNpvgA7QfgN0gPYboAO034DtgdN+A3SA9hugA7TfAB2g/QZsD5z2G6ADtN8AHaD9BugA7Tdge+C03wAdoP0G6ADtN0AHaL8B2wOn/QboAO03QAdovwE6QPsN2B447TdAB2i/ATpA+w3QAdpvwPbAab8BOkD7DdAB2m+ADtD+3w/4AireQnfqDwbPAAAAAElFTkSuQmCC';

const studioProbeVideoBase64 =
    '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';

/// Inspect the actual image part rather than filenames rewritten by Android's
/// Photo Picker. Keeps the fixture transport strict about payload integrity.
Map<String, bool> studioUploadChecks(
  http.Request request, {
  String field = 'uploads[product_image]',
  String mime = 'image/png',
  String extension = 'png',
  List<int>? expectedBytes,
}) {
  final result = {
    'field': false,
    'filename': false,
    'mime': false,
    'bytes': false,
  };
  final contentType = request.headers['content-type'];
  if (contentType == null) return result;
  String? boundary;
  try {
    final type = http.MediaType.parse(contentType);
    if (type.mimeType != 'multipart/form-data') return result;
    boundary = type.parameters['boundary'];
  } on FormatException {
    return result;
  }
  if (boundary == null || boundary.isEmpty) return result;
  final text = latin1.decode(request.bodyBytes);
  for (final part in text.split('--$boundary')) {
    final separator = part.indexOf('\r\n\r\n');
    if (separator < 0) continue;
    final headers = part.substring(0, separator);
    if (!RegExp(
      'name="${RegExp.escape(field)}"',
      caseSensitive: false,
    ).hasMatch(headers)) {
      continue;
    }
    result['field'] = true;
    final filename = RegExp(
      r'filename="([^"\r\n]+)"',
      caseSensitive: false,
    ).firstMatch(headers)?.group(1);
    result['filename'] =
        filename != null &&
        RegExp(
          r'^[^/\\]+\.' + RegExp.escape(extension) + r'$',
          caseSensitive: false,
        ).hasMatch(filename);
    result['mime'] = RegExp(
      r'(?:^|\r\n)content-type:\s*' + RegExp.escape(mime) + r'\s*(?:\r\n|$)',
      caseSensitive: false,
    ).hasMatch(headers);
    final payload = part.substring(separator + 4);
    if (payload.endsWith('\r\n')) {
      result['bytes'] = listEquals(
        latin1.encode(payload.substring(0, payload.length - 2)),
        expectedBytes ?? base64Decode(studioProbeImageBase64),
      );
    }
    return result;
  }
  return result;
}

class _ProbeStore extends SecureStore {
  final _values = <String, String>{'access_token': 'probe-session-only'};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Exercises the real native picker and production form against a deterministic
/// transport. Live server upload checks are performed separately.
class AndroidStudioProbe extends StatelessWidget {
  final String mode;
  AndroidStudioProbe({super.key, this.mode = 'photoshoot'});
  late final MobileApi api = MobileApi(
    store: _ProbeStore(),
    client: MockClient((request) async {
      Object body;
      if (request.url.path.endsWith('/license')) {
        body = {
          'status': 'success',
          'valid': true,
          'app': 'magicai',
          'features': ['image_gen'],
          'session_token': 'probe-only',
          'session_expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 20))
              .toIso8601String(),
        };
      } else if (request.headers['content-type']?.startsWith('multipart/') ==
          true) {
        final video = mode == 'video';
        final checks = studioUploadChecks(
          request,
          field: mode == 'creative'
              ? 'image'
              : video
              ? 'uploads[video_file]'
              : 'uploads[product_image]',
          mime: video ? 'video/mp4' : 'image/png',
          extension: video ? 'mp4' : 'png',
          expectedBytes: video ? base64Decode(studioProbeVideoBase64) : null,
        );
        if (checks.values.any((valid) => !valid)) {
          debugPrint('STUDIO_PROBE_FAILED: ${jsonEncode(checks)}');
          return http.Response(
            jsonEncode({'message': 'Picker multipart verification failed'}),
            422,
            headers: {'content-type': 'application/json'},
          );
        }
        debugPrint(
          '${mode == 'creative'
              ? 'CREATIVE'
              : video
              ? 'VIDEO'
              : 'STUDIO'}_PROBE_PASSED: native picker, exact cached ${video ? 'MP4' : 'PNG'} bytes, provider filename and ${video ? 'video/mp4' : 'image/png'} multipart (${request.bodyBytes.length} bytes)',
        );
        body = {
          'url': 'https://magicai.example.test/uploads/picker.png',
          'message': 'Native gallery upload verified',
          'data': [
            {
              'id': 1,
              'title': 'Gallery regression passed',
              'status': 'completed',
            },
          ],
        };
      } else if (mode == 'creative') {
        body = request.url.path.endsWith('/templates')
            ? []
            : {'data': [], 'current_page': 1, 'last_page': 1};
      } else {
        body = {
          'title': 'Custom Photoshoot picker regression',
          'can_generate': true,
          'fields': [
            {
              'name': mode == 'video' ? 'video_file' : 'product_image',
              'label': mode == 'video' ? 'Upload video' : 'Product image',
              'type': 'file',
              'accept': mode == 'video' ? 'video/*' : 'image/*',
              'max_bytes': 50 * 1024 * 1024,
              'required': true,
            },
          ],
          'data': [],
        };
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      appBar: AppBar(title: const Text('Native photo attachment')),
      body: mode == 'creative'
          ? NativeCreativeScreen(api: api)
          : ExtensionWorkflowScreen(
              module: {
                'id': mode == 'video'
                    ? 'web:ai_captions'
                    : 'web:ext_ai_photo_studio_custom',
              },
              api: api,
            ),
    ),
  );
}
