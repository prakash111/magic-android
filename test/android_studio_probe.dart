import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/extension_workflow_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

const studioProbeImageBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAw0lEQVR4nO3QsQlCURTA0Fe5qOCITuIiTqAb/O5yrpgiZSDk3J6vzxX3x/uSX/ePDtB+A3SA9hugA7TfAB2g/bM9cNpvgA7QfgN0gPYboAO034DtgdN+A3SA9hugA7TfAB2g/QZsD5z2G6ADtN8AHaD9BugA7Tdge+C03wAdoP0G6ADtN0AHaL8B2wOn/QboAO03QAdovwE6QPsN2B447TdAB2i/ATpA+w3QAdpvwPbAab8BOkD7DdAB2m+ADtD+3w/4AireQnfqDwbPAAAAAElFTkSuQmCC';

/// Inspect the actual image part rather than filenames rewritten by Android's
/// Photo Picker. Keeps the fixture transport strict about payload integrity.
Map<String, bool> studioUploadChecks(http.Request request) {
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
      r'name="uploads\[product_image\]"',
      caseSensitive: false,
    ).hasMatch(headers))
      continue;
    result['field'] = true;
    final filename = RegExp(
      r'filename="([^"\r\n]+)"',
      caseSensitive: false,
    ).firstMatch(headers)?.group(1);
    result['filename'] =
        filename != null &&
        RegExp(r'^[^/\\]+\.png$', caseSensitive: false).hasMatch(filename);
    result['mime'] = RegExp(
      r'(?:^|\r\n)content-type:\s*image/png\s*(?:\r\n|$)',
      caseSensitive: false,
    ).hasMatch(headers);
    final payload = part.substring(separator + 4);
    if (payload.endsWith('\r\n')) {
      result['bytes'] = listEquals(
        latin1.encode(payload.substring(0, payload.length - 2)),
        base64Decode(studioProbeImageBase64),
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
  AndroidStudioProbe({super.key});
  final MobileApi api = MobileApi(
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
        final checks = studioUploadChecks(request);
        if (checks.values.any((valid) => !valid)) {
          debugPrint('STUDIO_PROBE_FAILED: ${jsonEncode(checks)}');
          return http.Response(
            jsonEncode({'message': 'Picker multipart verification failed'}),
            422,
            headers: {'content-type': 'application/json'},
          );
        }
        debugPrint(
          'STUDIO_PROBE_PASSED: native picker, exact cached PNG bytes, provider filename and image/png multipart (${request.bodyBytes.length} bytes)',
        );
        body = {
          'message': 'Native gallery upload verified',
          'data': [
            {
              'id': 1,
              'title': 'Gallery regression passed',
              'status': 'completed',
            },
          ],
        };
      } else {
        body = {
          'title': 'Custom Photoshoot picker regression',
          'can_generate': true,
          'fields': [
            {
              'name': 'product_image',
              'label': 'Product image',
              'type': 'file',
              'accept': 'image/*',
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
      body: ExtensionWorkflowScreen(
        module: const {'id': 'web:ext_ai_photo_studio_custom'},
        api: api,
      ),
    ),
  );
}
