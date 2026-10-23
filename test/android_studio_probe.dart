import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/extension_workflow_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

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
        final bytes = request.bodyBytes, text = latin1.decode(bytes);
        final realPng = bytes.asMap().entries.any(
          (entry) =>
              entry.value == 137 &&
              entry.key + 7 < bytes.length &&
              bytes[entry.key + 1] == 80 &&
              bytes[entry.key + 2] == 78 &&
              bytes[entry.key + 3] == 71,
        );
        if (!realPng ||
            !text.contains('uploads[product_image]') ||
            !text.contains('image/png') ||
            !text.contains('magicai-picker-reference.png')) {
          debugPrint('STUDIO_PROBE_FAILED: invalid multipart image');
          return http.Response(
            jsonEncode({'message': 'Picker multipart verification failed'}),
            422,
            headers: {'content-type': 'application/json'},
          );
        }
        debugPrint(
          'STUDIO_PROBE_PASSED: native picker, cached bytes, original filename and image/png multipart (${bytes.length} bytes)',
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
