import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/services/image_attachment_picker.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/screens/extension_workflow_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'extension_workflow_test.dart' show workflowApi;

class NamedPhoto extends XFile {
  final String displayName;
  NamedPhoto(List<int> bytes, this.displayName)
    : super.fromData(Uint8List.fromList(bytes));
  @override
  String get name => displayName;
}

final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAAAw0lEQVR4nO3QsQlCURTA0Fe5qOCITuIiTqAb/O5yrpgiZSDk3J6vzxX3x/uSX/ePDtB+A3SA9hugA7TfAB2g/bM9cNpvgA7QfgN0gPYboAO034DtgdN+A3SA9hugA7TfAB2g/QZsD5z2G6ADtN8AHaD9BugA7Tdge+C03wAdoP0G6ADtN0AHaL8B2wOn/QboAO03QAdovwE6QPsN2B447TdAB2i/ATpA+w3QAdpvwPbAab8BOkD7DdAB2m+ADtD+3w/4AireQnfqDwbPAAAAAElFTkSuQmCC',
);

class GalleryPicker extends ImagePicker {
  XFile? result;
  bool denied = false;
  @override
  Future<XFile?> pickImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true,
  }) async {
    expect(source, ImageSource.gallery);
    expect(requestFullMetadata, false);
    if (denied) throw PlatformException(code: 'photo_access_denied');
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'caches real PNG bytes, original filename and MIME for multipart upload',
    () async {
      final file = await ImageAttachmentPicker.cache(
        NamedPhoto(png, 'real-product.png'),
      );
      addTearDown(() async {
        await File(file.path!).parent.delete(recursive: true);
      });
      expect(file.name, 'real-product.png');
      expect(file.mimeType, 'image/png');
      expect(await File(file.path!).readAsBytes(), png);
      final part = await file.multipart('uploads[product_image]');
      expect(part.field, 'uploads[product_image]');
      expect(part.contentType.toString(), 'image/png');
      expect(part.length, png.length);
      expect(await part.finalize().toBytes(), png);
    },
  );
  test('rejects empty, oversized and unsupported files and handles cancellation and permissions', () async {
    for (final file in [
      XFile.fromData(Uint8List(0), name: 'empty.png'),
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'fake.png'),
    ]) {
      await expectLater(
        ImageAttachmentPicker.cache(file),
        throwsA(isA<ApiFailure>()),
      );
    }
    await expectLater(
      ImageAttachmentPicker.cache(
        XFile.fromData(png, name: 'large.png'),
        maxBytes: 2,
      ),
      throwsA(isA<ApiFailure>()),
    );
    final gallery = GalleryPicker(),
        picker = ImageAttachmentPicker(picker: GalleryPicker());
    expect(
      await picker.pick(moduleId: 'photoshoot', field: 'product_image'),
      isNull,
    );
    gallery.denied = true;
    await expectLater(
      ImageAttachmentPicker(picker: gallery)
          .pick(moduleId: 'photoshoot', field: 'product_image'),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.message,
          'message',
          contains('denied'),
        ),
      ),
    );
  });
  testWidgets(
    'gallery selection renders a removable thumbnail and transmits image bytes, never a filename alone',
    (tester) async {
      final gallery = GalleryPicker()
        ..result = NamedPhoto(png, 'gallery-product.png');
      var uploads = 0;
      final api = workflowApi((request) async {
        if (request.headers['content-type']?.startsWith('multipart/') == true) {
          uploads++;
          expect(request.bodyBytes, containsAllInOrder(png));
          expect(request.body, contains('image/png'));
          expect(request.body, contains('gallery-product.png'));
          expect(request.body, contains('uploads[product_image]'));
          return {'data': [], 'message': 'Upload verified'};
        }
        return {
          'title': 'Custom photoshoot',
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
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ExtensionWorkflowScreen(
              module: const {'id': 'web:custom'},
              api: api,
              imagePicker: ImageAttachmentPicker(picker: gallery),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('Product image')));
      // File system IO completes outside the fake asynchronous clock.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('gallery-product.png'), findsOneWidget);
      await tester.runAsync(() => tester.tap(find.text('Generate')));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(uploads, 1);
      await tester.tap(find.byTooltip('Remove photo'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.runAsync(() => tester.tap(find.text('Generate')));
      await tester.pumpAndSettle();
      expect(find.text('Choose Product image'), findsOneWidget);
      expect(uploads, 1);
    },
  );
}
