import 'package:magicai_mobile/services/native_extension_service.dart';

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/testing.dart';

import 'mobile_api_test.dart' show MemorySecureStore, license, jsonResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/bound_tool_workspace_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

Map<String, dynamic> field(
  String name,
  String label, {
  String type = 'text',
  bool required = false,
  dynamic value,
  List<Map<String, dynamic>>? options,
}) => {
  'name': name,
  'label': label,
  'type': type,
  'required': required,
  'default': ?value,
  'options': ?options,
};

Map<String, dynamic> listing(
  String workspace, {
  List<Map<String, dynamic>> fields = const [],
  List<Map<String, dynamic>> rows = const [],
}) => {
  'workspace': workspace,
  'fields': fields,
  'data': rows,
  'current_page': 1,
  'last_page': 1,
};
Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> reveal(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    150,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final id in [
    'marketing_bot_whatsapp_contact',
    'marketing_bot_whatsapp_contact_list',
    'marketing_bot_whatsapp_segment',
    'marketing_bot_campaigns_whatsapp',
    'marketing_bot_campaigns_telegram',
    'ai_music',
    'ext_ai_music_pro',
  ]) {
    testWidgets(
      'Explore binds $id even when cached route metadata says schema',
      (tester) async {
        final api = nativeApi((path, body) async {
          expect(path, '/native/extension');
          expect(body['module_id'], 'web:$id');
          expect(body['operation'], 'load');
          return listing(
            id.contains('music') ? 'music_pro' : 'marketing_contacts',
          );
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NativeModuleRegistry.build({
                'id': 'web:$id',
                'route_type': 'schema',
              }, api: api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(BoundToolWorkspaceScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'recipient edit restores phone group and segment selections and submits their ids',
    (tester) async {
      Map? submitted;
      final fields = [
        field('name', 'Name', required: true),
        field('last_name', 'Last name'),
        field('country_code', 'Country calling code', required: true),
        field('phone', 'Phone number', required: true),
        field(
          'contacts',
          'Contact lists',
          type: 'multiselect',
          options: [
            {'value': 9, 'label': 'Customers'},
          ],
        ),
        field(
          'segments',
          'Segments',
          type: 'multiselect',
          options: [
            {'value': 12, 'label': 'VIP'},
          ],
        ),
      ];
      final rows = [
        {
          'id': 4,
          'title': 'Jane',
          'values': {
            'name': 'Jane',
            'last_name': 'Doe',
            'phone': '1511234567',
            'country_code': '49',
            'contacts': [9],
            'segments': [12],
          },
        },
      ];
      final api = nativeApi((path, body) async {
        if (body['operation'] == 'bound_save') {
          submitted = body;
          return {'message': 'Saved'};
        }
        return listing('marketing_contact_lists', fields: fields, rows: rows);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeModuleRegistry.build({
              'id': 'web:marketing_bot_whatsapp_contact_list',
            }, api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(input('Phone number')).controller!.text,
        '1511234567',
      );
      expect(
        tester
            .widget<TextField>(input('Country calling code'))
            .controller!
            .text,
        '49',
      );
      await tester.enterText(input('Name'), 'Jane updated');
      await reveal(tester, find.text('VIP'));
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'Customers'),
            )
            .value,
        isTrue,
      );
      expect(
        tester
            .widget<CheckboxListTile>(
              find.widgetWithText(CheckboxListTile, 'VIP'),
            )
            .value,
        isTrue,
      );
      await reveal(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(submitted?['record_id'], 4);
      expect(submitted?['inputs']['name'], 'Jane updated');
      expect(submitted?['inputs']['contacts'], [9]);
      expect(submitted?['inputs']['segments'], [12]);
    },
  );

  testWidgets(
    'campaign supports send now and AI reply with contacts without requiring a date',
    (tester) async {
      Map? submitted;
      final fields = [
        field('name', 'Name', required: true),
        field('content', 'Message', type: 'textarea'),
        field(
          'contacts',
          'Contact lists',
          type: 'multiselect',
          required: true,
          options: [
            {'value': 9, 'label': 'Customers'},
          ],
        ),
        field('is_scheduled', 'Schedule for later', type: 'checkbox'),
        {
          ...field('scheduled_at', 'Scheduled time', type: 'datetime'),
          'visible_when': 'is_scheduled',
        },
        field('ai_reply', 'AI reply', type: 'checkbox'),
        field('instruction', 'AI instructions', type: 'textarea'),
      ];
      final api = nativeApi((path, body) async {
        if (body['operation'] == 'bound_save') {
          submitted = body;
          return {'message': 'Saved'};
        }
        return listing('marketing_campaigns', fields: fields);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeModuleRegistry.build({
              'id': 'web:marketing_bot_campaigns_whatsapp',
            }, api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      await tester.enterText(input('Name'), 'Campaign');
      await tester.enterText(input('Message'), 'Hello');
      await reveal(tester, find.text('Customers'));
      await tester.tap(find.text('Customers'));
      await reveal(tester, find.text('AI reply'));
      await tester.tap(find.text('AI reply'));
      await reveal(tester, input('AI instructions'));
      await tester.enterText(input('AI instructions'), 'Use our catalog');
      expect(input('Scheduled time'), findsNothing);
      await reveal(tester, find.widgetWithText(FilledButton, 'Save'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(submitted?['inputs']['contacts'], [9]);
      expect(submitted?['inputs']['ai_reply'], isTrue);
      expect(submitted?['inputs']['instruction'], 'Use our catalog');
      expect(
        (submitted?['inputs'] as Map).containsKey('scheduled_at'),
        isFalse,
      );
    },
  );

  testWidgets(
    'Pro generation sends provider inputs and shows credit failures without closing the form',
    (tester) async {
      Map? submitted;
      final api = nativeApi((path, body) async {
        if (body['operation'] == 'bound_save') {
          submitted = body;
          throw const ApiFailure('Insufficient credits.');
        }
        return listing(
          'music_pro',
          fields: [
            field('workbook_title', 'Title', required: true),
            field(
              'ai_music_prompt',
              'Prompt',
              type: 'textarea',
              required: true,
            ),
            field('duration', 'Duration (seconds)', type: 'number'),
            field('music_style', 'Music style'),
          ],
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeModuleRegistry.build({
              'id': 'web:ext_ai_music_pro',
            }, api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate Music'));
      await tester.pumpAndSettle();
      await tester.enterText(input('Title'), 'Piano');
      await tester.enterText(input('Prompt'), 'Relaxing piano');
      await tester.enterText(input('Duration (seconds)'), '60');
      await reveal(tester, find.widgetWithText(FilledButton, 'Generate Music'));
      await tester.tap(find.widgetWithText(FilledButton, 'Generate Music'));
      await tester.pumpAndSettle();
      expect(submitted?['inputs']['workbook_title'], 'Piano');
      expect(submitted?['inputs']['duration'], '60');
      expect(find.textContaining('Insufficient credits.'), findsOneWidget);
      expect(input('Title'), findsOneWidget);
    },
  );

  testWidgets('failed refresh keeps the saved records and offers retry', (
    tester,
  ) async {
    var loads = 0;
    final api = nativeApi((_, body) async {
      if (++loads == 2) throw Exception('Network unavailable');
      return listing(
        'music',
        rows: [
          {'id': 1, 'title': 'Saved song'},
        ],
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeModuleRegistry.build({'id': 'web:ai_music'}, api: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Saved song'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(loads, 3);
  });

  testWidgets(
    'CSV import maps columns previews recipients and imports selected phones',
    (tester) async {
      const channel = MethodChannel('com.magicai.mobile/secure');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'pickFile'
            ? {
                'name': 'contacts.csv',
                'bytes': utf8.encode(
                  'name,phone,country_code\nJane,+4915112345678,49\n',
                ),
              }
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var imports = 0;
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
          final body = request.body;
          if (body.contains('bound_csv_headers')) {
            return jsonResponse({
              'headers': ['name', 'phone', 'country_code'],
            });
          }
          if (body.contains('bound_csv_preview')) {
            return jsonResponse({
              'valid': [
                {'name': 'Jane', 'phone': '+4915112345678', 'country_code': 49},
              ],
              'invalid': [],
            });
          }
          if (body.contains('bound_csv_import')) {
            imports++;
            expect(body, contains('include_phones'));
            expect(body, contains('+4915112345678'));
            return jsonResponse({'message': 'Imported', 'count': 1});
          }
          return jsonResponse({
            ...listing('marketing_contact_lists'),
            'import_supported': true,
            'import_contacts': [],
            'import_segments': [],
          });
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeModuleRegistry.build({
              'id': 'web:marketing_bot_whatsapp_contact_list',
            }, api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import CSV'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose CSV file'));
      await tester.pumpAndSettle();
      expect(find.text('Phone column'), findsOneWidget);
      await reveal(tester, find.text('Preview import'));
      await tester.tap(find.text('Preview import'));
      await tester.pumpAndSettle();
      await reveal(tester, find.text('Jane'));
      expect(find.text('+4915112345678'), findsOneWidget);
      await reveal(tester, find.text('Import contacts (1)'));
      await tester.tap(find.text('Import contacts (1)'));
      await tester.pumpAndSettle();
      expect(imports, 1);
      expect(find.text('Create'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  test(
    'audio uploads accept the byte list returned by real device file pickers',
    () async {
      var uploaded = false;
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
          expect(request.body, contains('uploads[audio]'));
          expect(request.body, contains('audio/mpeg'));
          expect(request.body, contains('sample.mp3'));
          uploaded = true;
          return jsonResponse({'message': 'Generated'});
        }),
      );
      final result = await NativeExtensionService(api, 'web:ai_music').call(
        'bound_save',
        inputs: {'purpose': 'song', 'lyrics': 'Hello'},
        files: {
          'audio': {
            'name': 'sample.mp3',
            'bytes': [73, 68, 51, 4, 0, 0, 0, 0, 0, 0],
          },
        },
      );
      expect(uploaded, isTrue);
      expect(result['message'], 'Generated');
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      '360 dp form supports text scale 1.6 in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = nativeApi(
          (_, __) async => listing(
            'music',
            fields: [
              field('audio', 'Source audio', type: 'audio'),
              field('link', 'Source audio HTTPS URL'),
              field(
                'purpose',
                'Purpose',
                type: 'select',
                value: 'song',
                options: [
                  {'value': 'song', 'label': 'Song'},
                ],
              ),
              field('lyrics', 'Lyrics', type: 'textarea', required: true),
            ],
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                size: const Size(360, 800),
                textScaler: TextScaler.linear(1.6),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: NativeModuleRegistry.build({
                'id': 'web:ai_music',
              }, api: api),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Generate Music'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await reveal(
          tester,
          find.widgetWithText(FilledButton, 'Generate Music'),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
