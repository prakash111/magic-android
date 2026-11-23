import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_social_screen.dart';
import 'package:magicai_mobile/services/content_manager_service.dart';
import 'package:magicai_mobile/services/extension_workflow_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/content_manager_picker_sheet.dart';

import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;
import 'native_screen_test.dart' show nativeApi;

Map<String, dynamic> assetJson(String id, String type) => {
  'id': id,
  'title': '$type $id',
  'url':
      'https://magicai.example.test/uploads/$id.${type == 'video' ? 'mp4' : 'png'}',
  'type': type,
  'mime_type': type == 'video' ? 'video/mp4' : 'image/png',
  'size': 500,
};
ContentManagerAsset asset(String id, String type) =>
    ContentManagerAsset.fromJson(assetJson(id, type));

class FakeLibrary extends ContentManagerService {
  final Future<ContentManagerPage> Function(String, String, String, int)
  respond;
  FakeLibrary(this.respond) : super(nativeApi((_, _) async => {}));
  @override
  Future<ContentManagerPage> list({
    String type = 'images',
    String sort = 'newest',
    String search = '',
    int page = 1,
  }) => respond(type, sort, search, page);
  @override
  Future<WorkflowFile?> pick(String kind, int maxBytes) async =>
      WorkflowFile('new.mp4', [0, 1, 2]);
  @override
  Future<ContentManagerAsset> upload(
    WorkflowFile file, {
    void Function(double)? onProgress,
  }) async {
    onProgress?.call(.5);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    onProgress?.call(1);
    return asset('new', 'video');
  }
}

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (context, screen) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: screen!,
  ),
  home: Scaffold(body: child),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('service sends filtering sorting searching and pagination and parses normalized assets', () async {
    final api = nativeApi((path, _) async {
      final uri = Uri.parse(path);
      expect(uri.path, '/content-manager');
      expect(uri.queryParameters, containsPair('type', 'videos'));
      expect(uri.queryParameters, containsPair('search', 'a & b'));
      expect(uri.queryParameters, containsPair('page', '2'));
      return {
        'data': [assetJson('clip', 'video')],
        'meta': {'current_page': 2, 'last_page': 3, 'total': 50},
      };
    });
    final result = await ContentManagerService(api)
        .list(type: 'videos', sort: 'name', search: 'a & b', page: 2);
    expect(result.items.single.type, 'video');
    expect(result.page, 2);
    expect(result.lastPage, 3);
  });
  test('rejects unsafe server media URLs', () {
    expect(
      () => ContentManagerAsset.fromJson({
        ...assetJson('x', 'image'),
        'url': 'javascript:alert(1)',
      }),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('upload uses authenticated multipart and reports progress', () async {
    final store = MemorySecureStore()
      ..values.addAll({
        'access_token': 'private-token',
        'instance_hash': 'a' * 64,
      });
    final progress = <double>[];
    final api = MobileApi(
      store: store,
      origin: Uri.parse('https://magicai.example.test'),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return jsonResponse(license());
        }
        expect(request.url.path, '/api/mobile/v1/content-manager/upload');
        expect(request.headers['Authorization'], 'Bearer private-token');
        expect(
          request.headers['content-type'],
          contains('multipart/form-data'),
        );
        expect(request.body, contains('name="file"'));
        return jsonResponse({'data': assetJson('new', 'video')});
      }),
    );
    final result = await ContentManagerService(api)
        .upload(WorkflowFile('clip.mp4', [0, 1, 2]), onProgress: progress.add);
    expect(result.id, 'new');
    expect(progress.last, 1);
  });
  testWidgets(
    'renders all tabs and changes server filter when selecting Videos',
    (tester) async {
      final requested = <String>[];
      final library = FakeLibrary((type, sort, search, page) async {
        requested.add(type);
        return ContentManagerPage(
          [asset(type, type == 'videos' ? 'video' : 'image')],
          page: 1,
          lastPage: 1,
          total: 1,
        );
      });
      await tester.pumpWidget(
        host(ContentManagerPickerSheet(service: library)),
      );
      await tester.pumpAndSettle();
      for (final label in ['Upload Files', 'Images', 'Videos', 'Other Files']) {
        expect(find.text(label), findsOneWidget);
      }
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();
      expect(requested, ['images', 'videos']);
      expect(find.text('video videos'), findsOneWidget);
    },
  );
  testWidgets('debounced search and sorting refresh the server query', (
    tester,
  ) async {
    final queries = <String>[];
    final library = FakeLibrary((type, sort, search, page) async {
      queries.add('$sort:$search');
      return const ContentManagerPage([], page: 1, lastPage: 1, total: 0);
    });
    await tester.pumpWidget(host(ContentManagerPickerSheet(service: library)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'brand');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(queries.last, 'newest:brand');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(queries.last, 'name:brand');
  });
  testWidgets('loads additional pages while scrolling and deduplicates items', (
    tester,
  ) async {
    final pages = <int>[];
    final library = FakeLibrary((type, sort, search, page) async {
      pages.add(page);
      return ContentManagerPage(
        [for (var i = 0; i < 12; i++) asset('${(page - 1) * 12 + i}', 'image')],
        page: page,
        lastPage: 2,
        total: 24,
      );
    });
    await tester.pumpWidget(host(ContentManagerPickerSheet(service: library)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(GridView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(pages, [1, 2]);
  });
  testWidgets(
    'shows loading placeholders then error and retry without blank state',
    (tester) async {
      final first = Completer<ContentManagerPage>();
      var calls = 0;
      final library = FakeLibrary((type, sort, search, page) {
        calls++;
        return calls == 1
            ? first.future
            : Future.value(
                const ContentManagerPage([], page: 1, lastPage: 1, total: 0),
              );
      });
      await tester.pumpWidget(
        host(ContentManagerPickerSheet(service: library)),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsWidgets);
      first.completeError(const ApiFailure('Offline'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('No media found. Upload a file or try another search.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'upload immediately returns the selected video and shows progress',
    (tester) async {
      ContentManagerAsset? selected;
      final library = FakeLibrary(
        (type, sort, search, page) async =>
            const ContentManagerPage([], page: 1, lastPage: 1, total: 0),
      );
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                selected = await showModalBottomSheet<ContentManagerAsset>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ContentManagerPickerSheet(service: library),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Upload Files'));
      await tester.tap(find.text('Upload Files'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Upload video'));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(selected?.id, 'new');
      expect(selected?.type, 'video');
    },
  );
  testWidgets('keeps the picker open for unsupported post attachments', (
    tester,
  ) async {
    final library = FakeLibrary(
      (type, sort, search, page) async => ContentManagerPage(
        [asset('report', 'other')],
        page: 1,
        lastPage: 1,
        total: 1,
      ),
    );
    await tester.pumpWidget(
      host(
        ContentManagerPickerSheet(
          service: library,
          allowedTypes: const {'image', 'video'},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('other report'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This post supports images and videos. Other files remain available in your library.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('does not overflow at 360 dp with 1.6 text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final library = FakeLibrary(
      (type, sort, search, page) async => ContentManagerPage(
        [asset('long title for testing accessibility', 'video')],
        page: 1,
        lastPage: 1,
        total: 1,
      ),
    );
    await tester.pumpWidget(
      host(ContentManagerPickerSheet(service: library), scale: 1.6),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Upload Files'));
    await tester.tap(find.text('Upload Files'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  for (final schedule in [false, true]) {
    testWidgets(
      'composer selects a library video and ${schedule ? 'schedules' : 'saves a draft'} with its URL and owned id',
      (tester) async {
        Map<String, dynamic>? saved;
        final api = nativeApi((path, body) async {
          if (path.startsWith('/content-manager?')) {
            return {
              'data': [assetJson('generation_12', 'video')],
              'meta': {'current_page': 1, 'last_page': 1, 'total': 1},
            };
          }
          if (path == '/social-media/posts') {
            saved = Map<String, dynamic>.from(body);
            return {
              'data': {'id': 1},
            };
          }
          return {};
        });
        await tester.pumpWidget(
          host(
            SocialPostComposer(
              api: api,
              accounts: const [
                {
                  'id': '7',
                  'platform': 'facebook',
                  'displayName': 'Facebook',
                  'isConnected': true,
                },
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField).first, 'Test post');
        await tester.ensureVisible(find.text('Content Manager'));
        await tester.tap(find.text('Content Manager'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('video generation_12'));
        await tester.pumpAndSettle();
        expect(find.text('Video attached'), findsOneWidget);
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>),
              )
              .initialValue,
          'video',
        );
        if (schedule) {
          await tester.ensureVisible(find.byType(SwitchListTile));
          await tester.tap(find.byType(SwitchListTile));
          await tester.pumpAndSettle();
        }
        await tester.drag(find.byType(ListView).first, const Offset(0, -500));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byType(CheckboxListTile));
        await tester.tap(find.byType(CheckboxListTile));
        await tester.pumpAndSettle();
        final button = find.widgetWithText(
          FilledButton,
          schedule ? 'Publish now' : 'Save draft',
        );
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(saved?['media_id'], 'generation_12');
        expect(saved?['media_type'], 'video');
        expect(
          saved?['media_url'],
          'https://magicai.example.test/uploads/generation_12.mp4',
        );
        expect(saved?['status'], schedule ? 'scheduled' : 'draft');
      },
    );
  }
}
