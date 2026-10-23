import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'android_studio_probe.dart';

Future<http.Request> imageRequest({
  String filename = '1000000020.png',
  String field = 'uploads[product_image]',
  String mime = 'image/png',
  List<int>? bytes,
}) async {
  final upload =
      http.MultipartRequest(
          'POST',
          Uri.https('magicai.example.test', '/native/workflow'),
        )
        ..fields['inputs'] = jsonEncode({'prompt': 'Product photo'})
        ..files.add(
          http.MultipartFile.fromBytes(
            field,
            bytes ?? base64Decode(studioProbeImageBase64),
            filename: filename,
            contentType: http.MediaType.parse(mime),
          ),
        );
  final body = await upload.finalize().toBytes();
  return http.Request('POST', upload.url)
    ..headers.addAll(upload.headers)
    ..bodyBytes = body;
}

void main() {
  test(
    'accepts Android Photo Picker numeric filenames with exact PNG bytes',
    () async {
      for (final filename in [
        '1000000020.png',
        'magicai-picker-reference.png',
      ]) {
        expect(
          studioUploadChecks(await imageRequest(filename: filename)).values,
          everyElement(isTrue),
        );
      }
    },
  );

  test(
    'rejects mismatched bytes even when they begin with a PNG signature',
    () async {
      final changed = base64Decode(studioProbeImageBase64)..[50] ^= 1;
      expect(
        studioUploadChecks(await imageRequest(bytes: changed))['bytes'],
        isFalse,
      );
      expect(
        studioUploadChecks(await imageRequest(bytes: []))['bytes'],
        isFalse,
      );
    },
  );

  test(
    'rejects incorrect multipart field, MIME and unsafe filenames',
    () async {
      expect(
        studioUploadChecks(
          await imageRequest(field: 'uploads[image]'),
        )['field'],
        isFalse,
      );
      expect(
        studioUploadChecks(
          await imageRequest(mime: 'application/octet-stream'),
        )['mime'],
        isFalse,
      );
      expect(
        studioUploadChecks(
          await imageRequest(filename: '../image.png'),
        )['filename'],
        isFalse,
      );
      expect(
        studioUploadChecks(
          http.Request('POST', Uri.https('magicai.example.test', '/')),
        )['bytes'],
        isFalse,
      );
    },
  );
}
