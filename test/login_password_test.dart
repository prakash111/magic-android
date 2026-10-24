import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/screens/auth/login_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api_test.dart' show jsonResponse, license, MemorySecureStore;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'login initially has only email and password, MFA appears only after server challenge',
    (tester) async {
      final submissions = <Map>[];
      final api = MobileApi(
        store: MemorySecureStore(),
        client: MockClient((request) async {
          if (request.url.path.endsWith('/license')) {
            return jsonResponse(license());
          }
          if (request.url.path.endsWith('/auth/options')) {
            return jsonResponse({'providers': []});
          }
          if (request.url.path.endsWith('/auth/login')) {
            submissions.add(jsonDecode(request.body) as Map);
            return jsonResponse({
              'message': 'Enter your authenticator code.',
              'code': 'mfa_required',
            }, 422);
          }
          throw StateError('Unexpected request');
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: LoginScreen(api: api, onThemeChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(find.textContaining('Authenticator code'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'person@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'password123',
      );
      await tester.ensureVisible(find.text('Sign In'));
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();
      expect(submissions, hasLength(1));
      expect(submissions.single.containsKey('otp'), isFalse);
      expect(find.text('Verify your sign-in'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Verify your sign-in'), findsNothing);
      expect(find.byType(TextFormField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
