import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_connections_screen.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final type in ['chatbot_channels', 'agent_connections']) {
    testWidgets('$type opens native connections with exactly one header', (
      tester,
    ) async {
      final api = nativeApi((path, body) async {
        expect(path, '/native/connections');
        return {
          'kind': type == 'chatbot_channels' ? 'chatbot' : 'agent',
          'chatbots': [],
          'channels': [],
          'providers': [],
        };
      });
      final module = {'id': 'test-module', 'route_type': type};
      expect(NativeModuleRegistry.ownsHeader(module), isTrue);
      await tester.pumpWidget(
        MaterialApp(home: NativeModuleRegistry.build(module, api: api)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Channels and connectors'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('selects owned chatbot and connects with that bot id', (
    tester,
  ) async {
    Map? mutation;
    final api = nativeApi((path, body) async {
      if (body['operation'] == 'connect') {
        mutation = body;
        return {'message': 'Channel configured.'};
      }
      return {
        'kind': 'chatbot',
        'chatbots': [
          {'id': 17, 'title': 'Support'},
        ],
        'channels': [],
        'providers': [
          {
            'id': 'telegram',
            'fields': [
              {
                'name': 'telegram_token',
                'label': 'Bot token',
                'required': true,
                'secret': true,
                'options': [],
              },
            ],
          },
        ],
      };
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NativeConnectionsScreen(api: api, moduleId: 'chatbot'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Telegram'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
    await tester.enterText(find.byType(TextFormField), 'test-token');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(mutation?['chatbot_id'], 17);
    expect(mutation?['credentials'], {'telegram_token': 'test-token'});
    expect(mutation?['request_id'], isNotEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('empty credentials are validated before any connection request', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChannelConnectionForm(
          provider: const {
            'id': 'telegram',
            'fields': [
              {
                'name': 'telegram_token',
                'label': 'Bot token',
                'secret': true,
                'required': true,
                'options': [],
              },
            ],
          },
          requiresName: true,
        ),
      ),
    );
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.byType(ChannelConnectionForm), findsOneWidget);
    expect(find.text('This field is required.'), findsWidgets);
  });
  testWidgets(
    'agent channel disconnect requires confirmation and cancellation preserves it',
    (tester) async {
      var mutations = 0;
      final api = nativeApi((path, body) async {
        if (body['operation'] != 'load') mutations++;
        return {
          'kind': 'agent',
          'channels': [
            {'id': 2, 'name': 'Support agent', 'provider': 'telegram'},
          ],
        };
      });
      await tester.pumpWidget(
        MaterialApp(
          home: NativeConnectionsScreen(api: api, moduleId: 'agent'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Disconnect'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(mutations, 0);
      expect(find.text('Support agent'), findsOneWidget);
    },
  );
}
