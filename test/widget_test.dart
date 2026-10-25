import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:magicai_mobile/services/mobile_api.dart';

import 'mobile_api_test.dart' show MemorySecureStore, jsonResponse, license;

import 'package:magicai_mobile/models/user_model.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/screens/auth/login_screen.dart';
import 'package:magicai_mobile/services/seo_engine.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('UserModel parses real database fields correctly', () {
    final rawUser = {
      'id': 1,
      'name': 'Admin',
      'surname': 'User',
      'email': 'admin@admin.com',
      'remaining_words': '12500.00',
      'type': 'super_admin',
    };
    final user = UserModel.fromJson(rawUser);
    expect(user.id, equals(1));
    expect(user.fullName, equals('Admin User'));
    expect(user.credits, equals(12500));
    expect(user.plan, equals('Administrator'));
  });

  test('SEOEngine accurately audits content and calculates density', () {
    const content = '''# Guide to Flutter Development
Flutter development enables cross-platform engineering with a single codebase.
## Why Flutter Development?
Flutter development simplifies UI design with declarative widgets.
[Documentation](https://flutter.dev)
![Logo](https://flutter.dev/logo.png)''';

    final result = SEOEngine.analyze(
      content: content,
      keyword: 'flutter development',
      contentType: 'article',
    );

    expect(result.wordCount, greaterThan(10));
    expect(result.headingCount, equals(2));
    expect(result.linkCount, equals(1));
    expect(result.imageCount, equals(1));
    expect(result.keywordOccurrences, equals(4));
    expect(result.percentage, greaterThan(0));
    expect(result.checklist.isNotEmpty, isTrue);
  });

  testWidgets('LoginScreen renders credentials without an offline bypass', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: LoginScreen(
          onThemeChanged: (_) {},
          api: MobileApi(
            store: MemorySecureStore(),
            client: MockClient(
              (request) async => jsonResponse(
                request.url.path.endsWith('/license')
                    ? license()
                    : {'providers': []},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.textContaining('Offline Demo'), findsNothing);
  });

  testWidgets(
    'Server supplied tools and required fields render without a client release',
    (WidgetTester tester) async {
      final tool = <String, dynamic>{
        'id': 'new-server-tool',
        'title': 'New server tool',
        'component': 'form',
        'fields': [
          {
            'name': 'new_input',
            'label': 'New input',
            'type': 'textarea',
            'required': true,
          },
        ],
      };
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: ToolDirectory(
              tools: [tool],
              credits: const {},
              dashboard: false,
              refresh: () async {},
            ),
          ),
        ),
      );
      expect(find.text('New server tool'), findsOneWidget);
      await tester.tap(find.text('New server tool'));
      await tester.pumpAndSettle();
      expect(find.text('New input'), findsOneWidget);
      await tester.tap(find.text('Generate'));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
    },
  );
}
