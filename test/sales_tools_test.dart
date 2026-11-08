import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_workspace_screen.dart';
import 'package:magicai_mobile/services/native_workspace_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sales invoices workspace renders metrics, cards, and create button', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'invoices',
        'metrics': [
          {'label': 'Total Invoiced', 'value': 2500.0, 'currency': 'USD', 'icon': 'invoice'},
          {'label': 'Outstanding Balance', 'value': 500.0, 'currency': 'USD', 'icon': 'balance'},
        ],
        'currency': 'USD',
        'currencies': ['USD', 'EUR'],
        'data': [
          {
            'id': 101,
            'number': 'INV-2026-001',
            'customer': 'Globex Corp',
            'total': 1200.0,
            'balance': 300.0,
            'currency': 'USD',
            'status': 'sent',
            'issue_date': '2026-11-01',
            'due_date': '2026-12-01',
            'notes': 'Test invoice note',
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
              'id': 'web:sales_invoices',
              'title': 'Invoices',
              'category': 'Sales',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invoices'), findsWidgets);
    expect(find.text('INV-2026-001'), findsOneWidget);
    expect(find.text('Globex Corp'), findsOneWidget);
    expect(find.text('Create invoice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sales payments workspace renders metrics, payment cards, and record button', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'payments',
        'metrics': [
          {'label': 'Total Received', 'value': 1200.0, 'currency': 'USD', 'icon': 'paid'},
          {'label': 'Completed', 'value': 3, 'icon': 'invoice'},
        ],
        'currency': 'USD',
        'currencies': ['USD', 'EUR'],
        'data': [
          {
            'id': 201,
            'amount': 450.0,
            'currency': 'USD',
            'payment_date': '2026-11-05',
            'payment_method': 'bank_transfer',
            'reference': 'WIRE-9988',
            'status': 'completed',
            'invoice_number': 'INV-2026-001',
            'customer': 'Globex Corp',
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
              'id': 'web:sales_payments',
              'title': 'Payments',
              'category': 'Sales',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Payments'), findsWidgets);
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.textContaining('INV-2026-001'), findsOneWidget);
    expect(find.textContaining('450'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sales proposals and estimates workspaces render successfully', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'proposals',
        'metrics': [
          {'label': 'Total Proposals', 'value': 5, 'icon': 'invoice'},
        ],
        'currency': 'USD',
        'currencies': ['USD'],
        'data': [
          {
            'id': 301,
            'title': 'Website Redesign',
            'number': 'PRP-001',
            'status': 'sent',
            'total': 8500.0,
            'currency': 'USD',
            'customer': 'Wayne Enterprises',
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
              'id': 'web:sales_proposals',
              'title': 'Proposals',
              'category': 'Sales',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Proposals'), findsWidgets);
    expect(find.text('Create proposal'), findsOneWidget);
    expect(find.text('Website Redesign'), findsOneWidget);
    expect(find.text('Wayne Enterprises'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WorkspaceRecordEditor validates and saves invoice and payment mutations', (tester) async {
    Map? savedRecord;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        savedRecord = body;
        return {'status': 'success'};
      }
      return {
        'schema_version': 1,
        'kind': 'invoices',
        'metrics': [],
        'currency': 'USD',
        'currencies': ['USD', 'EUR'],
        'companies': [
          {'id': 1, 'name': 'Acme Inc'},
        ],
        'contacts': [
          {'id': 10, 'name': 'Alice Smith'},
        ],
        'data': [],
        'modules': [],
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeWorkspaceScreen(
            module: const {
              'id': 'web:sales_invoices',
              'title': 'Invoices',
              'category': 'Sales',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap "Create invoice"
    await tester.tap(find.text('Create invoice').first);
    await tester.pumpAndSettle();

    expect(find.text('Create invoice'), findsWidgets);
    expect(find.text('Total amount'), findsOneWidget);

    // Enter total amount
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Total amount'),
      '750.50',
    );
    await tester.pumpAndSettle();

    // Scroll down in editor and tap Save button
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create invoice'));
    await tester.pumpAndSettle();

    expect(savedRecord, isNotNull);
    expect(savedRecord?['kind'], 'invoice');
    expect(savedRecord?['inputs']['total'], '750.50');
  });

  testWidgets('crm companies workspace renders company cards and New company button with direct List data', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'companies',
        'module': {
          'id': 'web:crm_companies',
          'title': 'Companies',
          'category': 'CRM',
        },
        'modules': [],
        'data': [
          {
            'id': 3,
            'name': 'Zoomnearby Network',
            'industry': 'textiles',
            'website': 'https://zoomnearby.com',
            'phone': '918535075196',
            'email': 'prakashks045@gmail.com',
            'city': 'delhi',
          },
        ],
        'current_page': 1,
        'last_page': 1,
        'total': 1,
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeWorkspaceScreen(
            module: const {
              'id': 'web:crm_companies',
              'title': 'Companies',
              'category': 'CRM',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zoomnearby Network'), findsOneWidget);
    expect(find.text('textiles'), findsOneWidget);
    expect(find.text('New company'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crm companies workspace normalizes legacy nested Map data gracefully', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'companies',
        'module': {
          'id': 'web:crm_companies',
          'title': 'Companies',
          'category': 'CRM',
        },
        'modules': [],
        'data': {
          'data': [
            {
              'id': 7,
              'name': 'Acme Global Ventures',
              'industry': 'technology',
            },
          ],
          'current_page': 1,
          'last_page': 1,
          'total': 1,
        },
      };
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: NativeWorkspaceScreen(
            module: const {
              'id': 'web:crm_companies',
              'title': 'Companies',
              'category': 'CRM',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Acme Global Ventures'), findsOneWidget);
    expect(find.text('technology'), findsOneWidget);
    expect(find.text('New company'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('NativeWorkspaceService normalizes both nested Map and direct List payloads', () async {
    final flatApi = nativeApi((path, body) async => {
      'schema_version': 1,
      'kind': 'companies',
      'modules': [],
      'data': [{'id': 1, 'name': 'Alpha'}],
    });
    final flatService = NativeWorkspaceService(flatApi, 'web:crm_companies');
    final flatResult = await flatService.load();
    expect(flatResult['data'], isA<List>());
    expect((flatResult['data'] as List).length, 1);

    final nestedApi = nativeApi((path, body) async => {
      'schema_version': 1,
      'kind': 'companies',
      'modules': [],
      'data': {
        'data': [{'id': 2, 'name': 'Beta'}],
        'current_page': 1,
        'last_page': 1,
        'total': 1,
      },
    });
    final nestedService = NativeWorkspaceService(nestedApi, 'web:crm_companies');
    final nestedResult = await nestedService.load();
    expect(nestedResult['data'], isA<List>());
    expect((nestedResult['data'] as List).length, 1);
    expect(nestedResult['total'], 1);
  });

  test('NativeModuleRegistry dispatches companies route_type to NativeWorkspaceScreen', () {
    final api = nativeApi((path, body) async => {});
    final widget = NativeModuleRegistry.build({
      'id': 'web:crm_companies',
      'title': 'Companies',
      'route_type': 'companies',
    }, api: api);
    expect(widget, isA<NativeWorkspaceScreen>());
  });
}
