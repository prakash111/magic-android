import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_preferences_probe.dart' as probe;

void main() {
  testWidgets(
    'release storage probe verifies profile persistence and restores existing data',
    (tester) async {
      final originalUser = jsonEncode({
        'id': 7,
        'name': 'Existing user',
        'email': 'existing@example.invalid',
      });
      SharedPreferences.setMockInitialValues({
        'auth_user': originalUser,
        'theme_mode': 'light',
      });
      await probe.main();
      await tester.pumpAndSettle();
      expect(find.text('Preferences read and write verified'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('release_preferences_probe_ready'), isTrue);
      expect(
        prefs.getString('auth_user'),
        contains('storage-probe@example.invalid'),
      );
      await tester.pumpWidget(const SizedBox());
      await probe.main();
      await tester.pumpAndSettle();
      expect(find.text('Preferences persisted across restart'), findsOneWidget);
      expect(prefs.getString('auth_user'), originalUser);
      expect(prefs.getString('theme_mode'), 'light');
      expect(
        prefs.getKeys().where(
          (key) => key.startsWith('release_preferences_probe_'),
        ),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
