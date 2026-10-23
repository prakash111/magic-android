import 'dart:async';

import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_social_screen.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/social_post_service.dart';
import 'package:magicai_mobile/services/workspace_catalog.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;
import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;

const modules = <Map<String, dynamic>>[
  {'id': 'crm', 'title': 'Dashboard', 'category': 'CRM', 'available': true},
  {
    'id': 'work',
    'title': 'Dashboard',
    'category': 'Work & productivity',
    'available': true,
  },
  {
    'id': 'social',
    'title': 'Dashboard',
    'category': 'Social & marketing',
    'available': true,
  },
  {'id': 'contacts', 'title': 'Contacts', 'category': 'CRM', 'available': true},
];
const accounts = <Map<String, dynamic>>[
  {
    'id': '7',
    'platform': 'x',
    'displayName': 'X',
    'handle': '@team',
    'isConnected': true,
  },
  {
    'id': 'platform_instagram',
    'platform': 'instagram',
    'displayName': 'Instagram',
    'isConnected': false,
  },
];
Map<String, dynamic> page(String caption, {int page = 1, int lastPage = 1}) => {
  'data': [
    {
      'id': '$page',
      'caption': caption,
      'platforms': ['x'],
      'status': 'draft',
    },
  ],
  'current_page': page,
  'last_page': lastPage,
};
Widget app(Widget screen) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(body: screen),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('all workspaces are grouped once in source order and duplicate names are qualified', () {
    final many = [
      for (var i = 0; i < 107; i++)
        {'id': '$i', 'title': 'Tool $i', 'category': 'Category ${i % 8}'},
    ];
    final grouped = groupedWorkspaces(many);
    expect(grouped.length, 8);
    expect(
      grouped.values
          .expand((items) => items)
          .map((item) => item['id'])
          .toSet()
          .length,
      107,
    );
    final sections = groupedWorkspaces(modules);
    expect(sections.keys, ['CRM', 'Work & productivity', 'Social & marketing']);
    expect(sections['CRM']!.map((item) => item['id']), ['crm', 'contacts']);
    expect(sections['CRM']!.first['display_title'], 'CRM Dashboard');
    expect(
      sections['Work & productivity']!.first['display_title'],
      'Productivity Dashboard',
    );
    expect(
      sections['Social & marketing']!.first['display_title'],
      'Social Media Dashboard',
    );
    expect(groupedWorkspaces(modules, category: 'CRM').keys, ['CRM']);
    expect(groupedWorkspaces(modules, query: 'social media').keys, [
      'Social & marketing',
    ]);
    expect(
      workspaceTitle({
        'title': 'Dashboard',
        'category': 'CRM',
        'display_title': 'Pipeline overview',
      }),
      'Pipeline overview',
    );
    expect(workspaceCategory({'category': '  '}), 'Work & productivity');
    expect(
      workspaceTitle({
        'title': 'Social Media Posts',
        'category': 'Social & marketing',
      }, duplicate: true),
      'Social Media Posts',
    );
  });

  testWidgets(
    'Explore renders section headers and filters and searches within categories',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        app(WorkspaceScreen(modules: modules, refresh: () async {})),
      );
      expect(find.text('CRM Dashboard'), findsOneWidget);
      expect(find.text('Productivity Dashboard'), findsOneWidget);
      expect(find.text('Social Media Dashboard'), findsOneWidget);
      final semantics = tester.ensureSemantics();
      try {
        expect(
          tester.getSemantics(
            find.byKey(const ValueKey('workspace-section-CRM')),
          ),
          matchesSemantics(label: 'CRM', isHeader: true),
        );
      } finally {
        semantics.dispose();
      }
      await tester.tap(find.widgetWithText(ChoiceChip, 'CRM'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-section-CRM')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-section-Social & marketing')),
        findsNothing,
      );
      expect(find.text('Contacts'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'contacts');
      await tester.pumpAndSettle();
      expect(find.text('CRM Dashboard'), findsNothing);
      expect(find.text('Contacts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Explore search stays usable with a keyboard on a small viewport',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        app(WorkspaceScreen(modules: modules, refresh: () async {})),
      );
      await tester.enterText(find.byType(TextField), 'CRM');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'social posts load paginated drafts scheduled and published lists',
    (tester) async {
      final calls = <Uri>[];
      final api = nativeApi((path, body) async {
        if (path == '/social-media/platforms') return accounts;
        final uri = Uri.parse(path);
        calls.add(uri);
        final status = uri.queryParameters['status'];
        final current = int.parse(uri.queryParameters['page']!);
        return page(
          '$status audience $current',
          page: current,
          lastPage: status == 'all' ? 2 : 1,
        );
      });
      await tester.pumpWidget(app(ServerSocialScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.text('all audience 1'), findsOneWidget);
      await tester.ensureVisible(find.text('Load more posts'));
      await tester.tap(find.text('Load more posts'));
      await tester.pumpAndSettle();
      expect(find.text('all audience 2'), findsOneWidget);
      for (final label in ['Drafts', 'Scheduled', 'Published']) {
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, label));
        await tester.tap(find.widgetWithText(ChoiceChip, label));
        await tester.pumpAndSettle();
        final status = {
          'Drafts': 'draft',
          'Scheduled': 'scheduled',
          'Published': 'published',
        }[label];
        expect(find.text('$status audience 1'), findsOneWidget);
        expect(calls.last.queryParameters['status'], status);
        expect(calls.last.queryParameters['page'], '1');
        expect(find.byType(CircularProgressIndicator), findsNothing);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'social calendar sends bounded day queries and drafts clear calendar filtering',
    (tester) async {
      final calls = <Uri>[];
      final api = nativeApi((path, body) async {
        if (path == '/social-media/platforms') return accounts;
        calls.add(Uri.parse(path));
        return {'data': [], 'current_page': 1, 'last_page': 1};
      });
      await tester.pumpWidget(
        app(ServerSocialScreen(api: api, calendarInitiallyVisible: true)),
      );
      await tester.pumpAndSettle();
      expect(calls.last.queryParameters['status'], 'scheduled');
      expect(
        DateTime.parse(calls.last.queryParameters['until']!)
            .difference(DateTime.parse(calls.last.queryParameters['from']!))
            .inHours,
        24,
      );
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Drafts'));
      await tester.pumpAndSettle();
      expect(calls.last.queryParameters.containsKey('from'), isFalse);
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(find.text('No drafts yet.'), findsOneWidget);
    },
  );

  testWidgets(
    'social failures stop loading and retry without losing the native screen',
    (tester) async {
      var fails = true;
      final api = nativeApi((path, body) async {
        if (path == '/social-media/platforms') return accounts;
        if (fails) throw const ApiFailure('Connection unavailable. Retry.');
        return page('Recovered post');
      });
      await tester.pumpWidget(app(ServerSocialScreen(api: api)));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Connection unavailable'), findsOneWidget);
      fails = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Recovered post'), findsOneWidget);
    },
  );

  testWidgets(
    'social requests time out to retry UI rather than spinning forever',
    (tester) async {
      final pending = Completer<dynamic>();
      final api = nativeApi(
        (path, body) async =>
            path == '/social-media/platforms' ? accounts : pending.future,
      );
      await tester.pumpWidget(app(ServerSocialScreen(api: api)));
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
      pending.complete(page('Late post'));
      await tester.pumpAndSettle();
      expect(find.text('Late post'), findsNothing);
    },
  );

  testWidgets(
    'native composer preserves failures and request identity while retrying drafts',
    (tester) async {
      final submissions = <Map>[];
      final api = nativeApi((path, body) async {
        submissions.add(Map.from(body));
        throw const ApiFailure('Temporary failure. Retry.');
      });
      await tester.pumpWidget(
        app(SocialPostComposer(api: api, accounts: accounts)),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Post body'),
        'Native draft',
      );
      await tester.ensureVisible(find.byType(CheckboxListTile).first);
      await tester.tap(find.byType(CheckboxListTile).first);
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save draft'));
      await tester.pumpAndSettle();
      expect(submissions.length, 2);
      expect(submissions[0]['targets'], [
        {'account_id': 7},
      ]);
      expect(submissions[0]['status'], 'draft');
      expect(submissions[0]['request_id'], submissions[1]['request_id']);
      expect(submissions[0].containsKey('scheduled_at'), isFalse);
      expect(find.text('Create a post'), findsOneWidget);
      expect(find.text('Save draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'native composer schedules UTC media posts only to connected accounts',
    (tester) async {
      Map? saved;
      final api = nativeApi((path, body) async {
        saved = body;
        return {};
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SocialPostComposer(api: api, accounts: accounts),
                  ),
                ),
                child: const Text('Compose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Compose'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Post body'),
        'Scheduled native post',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Media URL (optional)'),
        'https://example.com/photo.jpg',
      );
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.tap(find.text('Schedule post'));
      await tester.pumpAndSettle();
      expect(saved!['status'], 'scheduled');
      expect(saved!['media_url'], 'https://example.com/photo.jpg');
      expect(saved!['media_type'], 'image');
      expect(DateTime.parse(saved!['scheduled_at']).isUtc, isTrue);
      expect(
        DateTime.parse(saved!['scheduled_at']).isAfter(DateTime.now()),
        isTrue,
      );
      expect(find.text('Compose'), findsOneWidget);
    },
  );

  testWidgets('composer input and save remain accessible with a keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      app(
        SocialPostComposer(
          api: nativeApi((_, body) async => {}),
          accounts: accounts,
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Post body'),
      'Small screen draft',
    );
    await tester.pumpAndSettle();
    expect(find.text('Save draft').hitTestable(), findsOneWidget);
    expect(
      tester
          .widget<Scaffold>(find.byType(Scaffold).last)
          .resizeToAvoidBottomInset,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    expect(AppTheme.backgroundDark, const Color(0xFF131620));
    expect(AppTheme.surfaceDark, const Color(0xFF1E2230));
  });

  for (final schema in [
    {'schema_version': 99, 'components': []},
    {'schema_version': 2, 'components': []},
    {
      'schema_version': 2,
      'components': [
        {'type': 'future_js_widget'},
      ],
    },
    {
      'schema_version': 2,
      'components': [
        {
          'type': 'table',
          'rows': [null, 'unexpected'],
        },
      ],
    },
  ]) {
    testWidgets(
      'future and malformed extension schemas fail gracefully: $schema',
      (tester) async {
        final api = nativeApi((path, body) async => schema);
        await tester.pumpWidget(
          app(NativeSchemaScreen(module: const {'id': 'web:future'}, api: api)),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        if (schema['schema_version'] == 99) {
          expect(find.text('Retry'), findsOneWidget);
        }
        if ((schema['components'] as List).isEmpty &&
            schema['schema_version'] == 2) {
          expect(find.text('Nothing here yet'), findsOneWidget);
        }
      },
    );
  }

  for (final type in ['image', 'video']) {
    test(
      'social $type attachments use authenticated native multipart uploads',
      () async {
        var uploads = 0;
        final store = MemorySecureStore()
          ..values.addAll({
            'access_token': 'private-token',
            'instance_hash': 'a' * 64,
          });
        final api = MobileApi(
          store: store,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/license')) {
              return jsonResponse(license());
            }
            expect(request.url.path, '/api/mobile/v1/social-media/attachments');
            expect(request.method, 'POST');
            expect(request.headers['Authorization'], 'Bearer private-token');
            expect(request.headers['X-Mobile-Session'], isNotEmpty);
            expect(
              request.headers['content-type'],
              startsWith('multipart/form-data; boundary='),
            );
            expect(request.body, contains('name="$type"'));
            expect(
              request.body,
              contains('filename="media.${type == 'video' ? 'mp4' : 'png'}"'),
            );
            uploads++;
            return jsonResponse({
              'url': 'https://magicai.example.test/uploads/media.$type',
            });
          }),
        );
        final url = await SocialPostService(
          api,
        ).upload([1, 2, 3], 'media.${type == 'video' ? 'mp4' : 'png'}', type);
        expect(url, 'https://magicai.example.test/uploads/media.$type');
        expect(uploads, 1);
      },
    );
  }

  testWidgets('unmigrated workspaces time out into a clean retry screen', (
    tester,
  ) async {
    final pending = Completer<dynamic>();
    final api = nativeApi((path, body) async => pending.future);
    await tester.pumpWidget(
      app(NativeSchemaScreen(module: const {'id': 'web:future'}, api: api)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(
      find.text('The server took too long. Please retry.'),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    pending.complete({'schema_version': 2, 'components': []});
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('request identifiers are unique RFC 4122 version 4 UUIDs', () {
    final ids = {for (var i = 0; i < 100; i++) SocialPostService.requestId()};
    expect(ids.length, 100);
    expect(
      ids.every(
        (id) => RegExp(
          r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
        ).hasMatch(id),
      ),
      isTrue,
    );
  });
}
