import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_workspace_screen.dart';
import 'package:magicai_mobile/services/native_workspace_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Brand Voice workspace renders metrics, company card, and products', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'brand_voice',
        'metrics': [
          {'label': 'Total Brands', 'value': '1', 'icon': 'brand'},
          {'label': 'Products & Services', 'value': '2', 'icon': 'product'},
          {'label': 'Default Voice Tone', 'value': 'Professional', 'icon': 'voice'},
        ],
        'data': [
          {
            'id': 10,
            'name': 'Starlight AI',
            'tagline': 'Intelligent Voice Systems',
            'tone_of_voice': 'Witty',
            'industry': 'Software',
            'website': 'https://starlight.example.com',
            'target_audience': 'Product Managers',
            'brand_color': '#6366F1',
            'description': 'Building next-gen voice assistants for teams.',
            'specific_instructions': 'Avoid technical jargon in public copy.',
            'products': [
              {
                'id': 101,
                'name': 'Starlight Core',
                'type': 0,
                'key_features': 'Fast latency, 50+ languages',
                'company_id': 10,
              },
              {
                'id': 102,
                'name': 'Voice Concierge Service',
                'type': 1,
                'key_features': '24/7 managed support',
                'company_id': 10,
              },
            ],
          },
        ],
        'modules': [],
        'current_page': 1,
        'last_page': 1,
        'lookups': {
          'voice_tones': [
            'Professional',
            'Funny',
            'Casual',
            'Excited',
            'Witty',
            'Sarcastic',
            'Feminine',
            'Masculine',
            'Bold',
            'Dramatic',
            'Grumpy',
            'Secretive',
          ],
        },
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeWorkspaceScreen(
            module: const {
              'id': 'web:brand_voice',
              'title': 'Brand Voice',
              'category': 'Audio & voice',
              'route': 'dashboard.user.brand.index',
              'route_type': 'brand_voice',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify metrics
    expect(find.text('Total Brands'), findsOneWidget);
    expect(find.text('Products & Services'), findsOneWidget);
    expect(find.text('Default Voice Tone'), findsOneWidget);

    // Verify company details
    expect(find.text('Starlight AI'), findsOneWidget);
    expect(find.text('Intelligent Voice Systems'), findsOneWidget);
    expect(find.text('Witty'), findsOneWidget);
    expect(find.text('Software'), findsOneWidget);
    expect(find.text('Building next-gen voice assistants for teams.'), findsOneWidget);
    expect(find.text('Audience: Product Managers'), findsOneWidget);

    // Verify products
    expect(find.text('Starlight Core'), findsOneWidget);
    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Voice Concierge Service'), findsOneWidget);
    expect(find.text('Service'), findsOneWidget);
  });

  testWidgets('Brand Voice empty state renders action button', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'brand_voice',
        'metrics': [
          {'label': 'Total Brands', 'value': '0', 'icon': 'brand'},
          {'label': 'Products & Services', 'value': '0', 'icon': 'product'},
        ],
        'data': [],
        'modules': [],
        'current_page': 1,
        'last_page': 1,
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeWorkspaceScreen(
            module: const {
              'id': 'web:brand_voice',
              'title': 'Brand Voice',
              'category': 'Audio & voice',
              'route': 'dashboard.user.brand.index',
              'route_type': 'brand_voice',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No brand voices yet'), findsOneWidget);
    expect(find.text('Create brand voice'), findsOneWidget);
  });

  testWidgets('WorkspaceRecordEditor validates and saves brand_voice', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map? lastMutateBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        lastMutateBody = body;
        return {
          'message': 'Brand voice profile saved.',
          'record_id': 12,
        };
      }
      return {'data': []};
    });

    final service = NativeWorkspaceService(api, 'web:brand_voice');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkspaceRecordEditor(
            service: service,
            kind: 'brand_voice',
            lookups: const {
              'voice_tones': ['Professional', 'Funny', 'Casual', 'Excited', 'Witty'],
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Create brand voice'), findsWidgets);

    // Try submitting without required fields
    await tester.tap(find.widgetWithText(FilledButton, 'Create brand voice'));
    await tester.pumpAndSettle();
    expect(lastMutateBody, isNull);

    // Fill required fields
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Company / Brand Name'),
      'Quantum Audio Inc',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Description'),
      'Cutting-edge spatial audio engine.',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Tagline'),
      'Hear the future',
    );

    // Submit button and tap
    await tester.tap(find.widgetWithText(FilledButton, 'Create brand voice'));
    await tester.pumpAndSettle();

    expect(lastMutateBody, isNotNull);
    expect(lastMutateBody!['kind'], 'brand_voice');
    expect(lastMutateBody!['operation'], 'save');
    expect(lastMutateBody!['inputs']['name'], 'Quantum Audio Inc');
    expect(lastMutateBody!['inputs']['description'], 'Cutting-edge spatial audio engine.');
    expect(lastMutateBody!['inputs']['tagline'], 'Hear the future');
  });

  testWidgets('WorkspaceRecordEditor saves brand_product', (tester) async {
    Map? lastMutateBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        lastMutateBody = body;
        return {
          'message': 'Product saved.',
          'record_id': 55,
        };
      }
      return {'data': []};
    });

    final service = NativeWorkspaceService(api, 'web:brand_voice');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkspaceRecordEditor(
            service: service,
            kind: 'brand_product',
            lookups: const {'company_id': 10},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Add product / service'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Product or Service Name'),
      'Spatial Engine SDK',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Key Features'),
      'Ultra-low 5ms latency, Dolby Atmos support',
    );

    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Add product'));
    await tester.pumpAndSettle();

    expect(lastMutateBody, isNotNull);
    expect(lastMutateBody!['kind'], 'brand_product');
    expect(lastMutateBody!['operation'], 'save');
    expect(lastMutateBody!['inputs']['name'], 'Spatial Engine SDK');
    expect(lastMutateBody!['inputs']['key_features'], 'Ultra-low 5ms latency, Dolby Atmos support');
    expect(lastMutateBody!['inputs']['company_id'], 10);
  });

  testWidgets('Brand Voice card popup menu triggers delete confirmation', (tester) async {
    Map? deleteBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        deleteBody = body;
        return {'status': 'success', 'message': 'Brand voice profile deleted.'};
      }
      return {
        'schema_version': 1,
        'kind': 'brand_voice',
        'metrics': [],
        'data': [
          {
            'id': 10,
            'name': 'Starlight AI',
            'tagline': 'Intelligent Voice Systems',
            'tone_of_voice': 'Witty',
            'description': 'Building next-gen voice assistants.',
            'products': [],
          },
        ],
        'modules': [],
        'current_page': 1,
        'last_page': 1,
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeWorkspaceScreen(
            module: const {
              'id': 'web:brand_voice',
              'title': 'Brand Voice',
              'category': 'Audio & voice',
              'route': 'dashboard.user.brand.index',
              'route_type': 'brand_voice',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Open company popup menu
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Edit brand voice'), findsOneWidget);
    expect(find.text('Add product / service'), findsOneWidget);
    expect(find.text('Delete brand voice'), findsOneWidget);

    await tester.tap(find.text('Delete brand voice'));
    await tester.pumpAndSettle();

    // Confirmation dialog
    expect(find.text('Delete Starlight AI?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleteBody, isNotNull);
    expect(deleteBody!['kind'], 'brand_voice');
    expect(deleteBody!['operation'], 'delete');
    expect(deleteBody!['record_id'], 10);
  });

  testWidgets('Brand Voice card product delete icon triggers product delete', (tester) async {
    Map? deleteBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        deleteBody = body;
        return {'status': 'success', 'message': 'Product deleted.'};
      }
      return {
        'schema_version': 1,
        'kind': 'brand_voice',
        'metrics': [],
        'data': [
          {
            'id': 10,
            'name': 'Starlight AI',
            'description': 'Building next-gen voice assistants.',
            'products': [
              {
                'id': 101,
                'name': 'Starlight Core',
                'type': 0,
                'company_id': 10,
              },
            ],
          },
        ],
        'modules': [],
        'current_page': 1,
        'last_page': 1,
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeWorkspaceScreen(
            module: const {
              'id': 'web:brand_voice',
              'title': 'Brand Voice',
              'category': 'Audio & voice',
              'route': 'dashboard.user.brand.index',
              'route_type': 'brand_voice',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Starlight Core'), findsOneWidget);

    // Tap the delete icon next to product
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Delete Starlight Core?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleteBody, isNotNull);
    expect(deleteBody!['kind'], 'brand_product');
    expect(deleteBody!['operation'], 'delete');
    expect(deleteBody!['record_id'], 101);
  });
}
