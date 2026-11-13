import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/crm_presentations_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart' show openModule;
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

const module = <String, dynamic>{
  'id': 'web:crm_presentations',
  'title': 'Presentations',
  'route': 'dashboard.user.crm.presentations.index',
  'route_type': 'crm_presentations',
  'available': true,
};
Map<String, dynamic> deck({String status = 'completed'}) => {
  'id': 7,
  'title': 'Pitch Deck - Acme',
  'status': status,
  'style': 'modern',
  'deal': {'id': 21, 'title': 'Acme opportunity'},
  'company': 'Acme',
  'progress': status == 'completed' ? 100 : 50,
  'total_slides': 2,
  'completed_slides': status == 'completed' ? 2 : 1,
  'has_pdf': true,
  'has_pptx': true,
  'slides': [
    {
      'id': 31,
      'title': 'Our proposal',
      'status': 'completed',
      'content': {'body': 'Shared CRM knowledge and deal details.'},
      'image_url': null,
    },
  ],
};
Map<String, dynamic> listing({bool empty = false, bool deals = true}) => {
  'kind': 'crm_presentations',
  'data': empty ? [] : [deck()],
  'current_page': 1,
  'last_page': 1,
  'deals': deals
      ? [
          {'id': 21, 'title': 'Acme opportunity', 'company': 'Acme'},
        ]
      : [],
};
Widget app(MobileApi api, {double scale = 1}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: NativeModuleScreen(module: module, api: api),
);
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final type in ['crm_presentations', 'schema']) {
    testWidgets(
      'Explore binds CRM presentations with $type metadata to native records',
      (tester) async {
        final api = nativeApi((path, body) async {
          expect(path, '/native/extension');
          expect(body['module_id'], 'web:crm_presentations');
          expect(body['operation'], 'load');
          return listing();
        });
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => openModule(context, {
                    ...module,
                    'route_type': type,
                  }, api: api),
                  child: const Text('Open decks'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open decks'));
        await tester.pumpAndSettle();
        expect(find.byType(CrmPresentationsScreen), findsOneWidget);
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.text('Pitch Deck - Acme'), findsOneWidget);
        expect(find.text('Acme opportunity'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'creates a presentation from an owned deal and opens the saved CRM deck',
    (tester) async {
      Map? submitted;
      final api = nativeApi((path, body) async {
        expect(path, '/native/extension');
        if (body['operation'] == 'create_presentation') {
          submitted = body;
          return {'record_id': 7, 'message': 'Generation started.'};
        }
        return body['record_id'] == 7
            ? {'presentation': deck()}
            : listing(empty: true);
      });
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('New Presentation'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme opportunity · Acme').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Modern').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Generate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(submitted?['inputs'], {'crm_deal_id': 21, 'style': 'modern'});
      expect(submitted?['request_id'], isNotEmpty);
      expect(find.text('Our proposal'), findsOneWidget);
      expect(
        find.text('Shared CRM knowledge and deal details.'),
        findsOneWidget,
      );
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('Download PowerPoint'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pending decks refresh every five seconds and stop after completion',
    (tester) async {
      var details = 0;
      final api = nativeApi(
        (path, body) async => body['record_id'] == 7
            ? {
                'presentation': deck(
                  status: ++details == 1 ? 'generating' : 'completed',
                ),
              }
            : listing(),
      );
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pitch Deck - Acme'));
      await tester.pumpAndSettle();
      expect(details, 1);
      expect(
        find.text(
          'Your slides are being created. Progress updates automatically.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(details, 2);
      await tester.pump(const Duration(seconds: 10));
      expect(details, 2);
      expect(
        find.text(
          'Your slides are being created. Progress updates automatically.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'PDF export uses the authenticated backend ticket and opens it securely',
    (tester) async {
      const channel = MethodChannel('com.magicai.mobile/secure');
      MethodCall? opened;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        opened = call;
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      Map? exported;
      final api = nativeApi((path, body) async {
        if (body['operation'] == 'export_presentation') {
          exported = body;
          return {
            'url': 'https://magicai.example.test/mobile/open/temporary-ticket',
          };
        }
        return body['record_id'] == 7 ? {'presentation': deck()} : listing();
      });
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pitch Deck - Acme'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download PDF'));
      await tester.pumpAndSettle();
      expect(exported?['record_id'], 7);
      expect(exported?['inputs'], {'format': 'pdf'});
      expect(opened?.method, 'openUrl');
      expect(
        opened?.arguments['url'],
        'https://magicai.example.test/mobile/open/temporary-ticket',
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'confirmed deletion uses the same CRM record and refreshes the list',
    (tester) async {
      var deleted = false;
      final api = nativeApi((path, body) async {
        if (body['operation'] == 'delete_presentation') {
          expect(body['record_id'], 7);
          deleted = true;
          return {'message': 'Presentation deleted.'};
        }
        return body['record_id'] == 7
            ? {'presentation': deck()}
            : listing(empty: deleted);
      });
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pitch Deck - Acme'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete presentation'));
      await tester.pumpAndSettle();
      expect(deleted, isFalse);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
      expect(find.text('No presentations found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'load errors show Retry and empty deals cannot start generation',
    (tester) async {
      var requests = 0;
      final api = nativeApi((_, _) async {
        if (++requests == 1) throw const ApiFailure('CRM is unavailable');
        return listing(empty: true, deals: false);
      });
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      expect(find.text('CRM is unavailable'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(
        find.text('Create a deal in CRM before generating a presentation.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'New Presentation'),
            )
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('list and slide detail fit a small phone with 160 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = nativeApi(
      (path, body) async =>
          body['record_id'] == 7 ? {'presentation': deck()} : listing(),
    );
    await tester.pumpWidget(app(api, scale: 1.6));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Pitch Deck - Acme'));
    await tester.tap(find.text('Pitch Deck - Acme'));
    await tester.pumpAndSettle();
    expect(find.text('Our proposal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'Gamma decks show their online and PDF actions without an empty-slide warning',
    (tester) async {
      final gamma = {
        ...deck(),
        'engine': 'gamma',
        'slides': [],
        'completed_slides': 0,
        'total_slides': 8,
        'has_web_view': true,
      };
      final api = nativeApi(
        (path, body) async => body['record_id'] == 7
            ? {'presentation': gamma}
            : {
                ...listing(),
                'data': [gamma],
              },
      );
      await tester.pumpWidget(app(api));
      await tester.pumpAndSettle();
      expect(find.text('Generated with Gamma.'), findsOneWidget);
      await tester.tap(find.text('Pitch Deck - Acme'));
      await tester.pumpAndSettle();
      expect(
        find.text('Generated with Gamma. View it online or download the PDF.'),
        findsOneWidget,
      );
      expect(find.text('Open presentation'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('No slides available.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
