import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:magicai_mobile/screens/native_creative_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/services/image_attachment_picker.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/social_post_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extension_workflow_test.dart' show workflowApi;
import 'studio_attachment_test.dart' show GalleryPicker, NamedPhoto, png;

class VideoGallery extends ImagePicker {
  XFile? video;
  @override
  Future<XFile?> pickVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async => video;
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('gallery videos use actual cached bytes and MIME; cancellation and invalid media cannot upload', () async {
    final bytes = Uint8List.fromList([
      0,
      0,
      0,
      24,
      ...ascii.encode('ftypmp42'),
      ...List.filled(64, 0),
    ]);
    final gallery = VideoGallery()..video = NamedPhoto(bytes, 'recording.mp4');
    final file = await ImageAttachmentPicker(picker: gallery)
        .pick(moduleId: 'captions', field: 'video_file', video: true);
    expect(file!.mimeType, 'video/mp4');
    expect(await File(file.path!).readAsBytes(), bytes);
    final part = await file.multipart('uploads[video_file]');
    expect(part.contentType.toString(), 'video/mp4');
    expect(await part.finalize().toBytes(), bytes);
    await File(file.path!).parent.delete(recursive: true);
    await expectLater(
      ImageAttachmentPicker.cache(NamedPhoto(png, 'fake.mp4'), video: true),
      throwsA(isA<ApiFailure>()),
    );
    gallery.video = null;
    expect(
      await ImageAttachmentPicker(picker: gallery)
          .pick(moduleId: 'captions', field: 'video_file', video: true),
      isNull,
    );
  });
  test('social multipart image and video uploads include explicit, byte-verified MIME types', () async {
    final video = [
      0,
      0,
      0,
      24,
      ...ascii.encode('ftypmp42'),
      ...List.filled(64, 0),
    ];
    var count = 0;
    final api = workflowApi((request) async {
      count++;
      expect(request.url.path, '/api/mobile/v1/social-media/attachments');
      expect(
        latin1.decode(request.bodyBytes),
        contains(count == 1 ? 'image/png' : 'video/mp4'),
      );
      expect(request.bodyBytes, containsAllInOrder(count == 1 ? png : video));
      return {'url': 'https://magicai.example.test/uploads/asset'};
    });
    await api.uploadImage(png, 'photo.png');
    await SocialPostService(api).upload(video, 'clip.mp4', 'video');
    await expectLater(
      api.uploadImage([], 'empty.png'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      SocialPostService(api).upload([1, 2], 'fake.mp4', 'video'),
      throwsA(isA<ApiFailure>()),
    );
    expect(count, 2);
  });
  testWidgets(
    'native schema file inputs honor PDF MIME filters and require actual attachments before submit',
    (tester) async {
      Map? saved;
      final methods = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureStore.channel, (call) async {
            methods.add(call.method);
            expect(call.arguments['accept'], 'application/pdf');
            return {
              'name': 'knowledge.pdf',
              'bytes': Uint8List.fromList(
                ascii.encode('%PDF-1.4\nA test document'),
              ),
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SecureStore.channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeSchemaForm(
              definition: const {
                'title': 'Upload document',
                'fields': [
                  {
                    'name': 'document',
                    'label': 'Source document',
                    'type': 'file',
                    'accept': 'application/pdf',
                    'required': true,
                  },
                ],
              },
              busy: false,
              submit: (inputs, files) async {
                saved = files;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Upload document'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.tap(find.text('Source document'));
      await tester.pumpAndSettle();
      expect(find.text('knowledge.pdf'), findsOneWidget);
      await tester.tap(find.text('Upload document'));
      await tester.pumpAndSettle();
      expect(methods, ['pickFile']);
      expect(
        ascii.decode(base64Decode(saved?['document']['bytes'])),
        startsWith('%PDF-1.4'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Creative Suite uploads a real picked photo instead of a placeholder attachment',
    (tester) async {
      final gallery = GalleryPicker()
        ..result = NamedPhoto(png, 'creative-photo.png');
      var uploaded = false;
      final api = workflowApi((request) async {
        final path = request.url.path;
        if (path.endsWith('/social-media/attachments')) {
          uploaded = true;
          expect(request.bodyBytes, containsAllInOrder(png));
          expect(request.body, contains('image/png'));
          expect(request.body, contains('creative-photo.png'));
          return {'url': 'https://magicai.example.test/uploads/creative.png'};
        }
        if (path.endsWith('/image-models')) return {'data': []};
        if (path.endsWith('/templates')) return [];
        return {'data': [], 'current_page': 1, 'last_page': 1};
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeCreativeScreen(
              api: api,
              imagePicker: ImageAttachmentPicker(picker: gallery),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await reveal(tester, find.byTooltip('Add reference image'));
      await tester.runAsync(
        () => tester.tap(find.byTooltip('Add reference image')),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(uploaded, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'URL video polls the owned preview and confirms before sending a render job',
    (tester) async {
      const id = '12345678-1234-4234-8234-123456789abc';
      var rendered = false;
      final calls = <String>[];
      final api = workflowApi((request) async {
        expect(request.url.path, '/api/mobile/v1/native/media');
        final body = jsonDecode(request.body) as Map;
        calls.add(body['operation']);
        switch (body['operation']) {
          case 'describe':
            return {
              'title': 'URL to video',
              'view': 'url_video',
              'fields': [
                {
                  'name': 'url',
                  'label': 'Product URL',
                  'type': 'url',
                  'required': true,
                },
              ],
              'generate_label': 'Generate previews',
              'data': null,
            };
          case 'generate':
            expect(body['inputs']['url'], 'https://example.com/product');
            return {
              'workflow_id': id,
              'workflow_status': 'processing',
              'message': 'Previews submitted',
              'data': [],
            };
          case 'status':
            expect(body['workflow_id'], id);
            return {
              'workflow_id': id,
              'workflow_status': 'ready',
              'previews': [
                {
                  'id': 'owned-preview',
                  'title': 'Studio preview',
                  'output_url': 'https://example.com/preview.mp4',
                },
              ],
              'data': [],
            };
          case 'render':
            expect(body['preview_id'], 'owned-preview');
            expect(body['workflow_id'], id);
            expect(body['request_id'], isNotEmpty);
            rendered = true;
            return {
              'workflow_status': 'rendering',
              'message': 'Rendering submitted',
              'data': [],
            };
        }
        return {'data': []};
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: NativeModuleScreen(
            api: api,
            module: const {
              'id': 'web:url_to_video',
              'title': 'URL to video',
              'route_type': 'native_media',
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField),
        'https://example.com/product',
      );
      await tester.tap(find.text('Generate previews'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 8));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Studio preview'));
      await tester.tap(find.text('Render').first);
      await tester.pumpAndSettle();
      expect(rendered, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Render').last);
      await tester.pumpAndSettle();
      expect(rendered, isTrue);
      expect(
        calls,
        containsAllInOrder(['describe', 'generate', 'status', 'render']),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets(
      'Smart Edit reloads web field definitions with null history in ${theme.brightness.name} mode',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final choices = <String>[];
        final api = workflowApi((request) async {
          final body = jsonDecode(request.body) as Map;
          final selection = body['inputs']['tool'] ?? '1';
          choices.add(selection);
          return {
            'title': 'Smart Edit',
            'view': 'smart_edit',
            'fields': [
              {
                'name': 'tool',
                'label': 'Editing tool',
                'type': 'select',
                'value': selection,
                'reload': true,
                'options': [
                  {'value': '1', 'label': 'Product Placement'},
                  {'value': '2', 'label': 'Professional Avatar'},
                ],
              },
              {
                'name': selection == '1' ? 'product_image' : 'user_photo',
                'label': selection == '1' ? 'Product Image' : 'Your Photo',
                'type': 'file',
                'accept': 'image/*',
                'required': true,
              },
            ],
            'data': null,
          };
        });
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: NativeModuleScreen(
              api: api,
              module: const {
                'id': 'web:ai_image_pro_edit',
                'title': 'Smart Edit',
                'route_type': 'native_media',
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Product Image'), findsOneWidget);
        await tester.tap(find.text('Product Placement'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Professional Avatar').last);
        await tester.pumpAndSettle();
        expect(choices, ['1', '2']);
        expect(find.text('Your Photo'), findsOneWidget);
        expect(find.text('Product Image'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
