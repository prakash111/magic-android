import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_social_screen.dart';
import 'package:magicai_mobile/screens/server_screen.dart';
import 'package:magicai_mobile/services/chat_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'mobile_api_test.dart' show MemorySecureStore, jsonResponse, license;
import 'native_screen_test.dart' show nativeApi;

Widget app(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(resizeToAvoidBottomInset: true, body: child),
);
const options = {
  'personas': [
    {'id': 0, 'name': 'AI Assistant'},
  ],
  'models': [
    {'id': 'gpt-4o', 'title': 'GPT-4o'},
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final theme in [AppTheme.darkTheme, AppTheme.lightTheme]) {
    testWidgets(
      'chat selectors fit long live persona metadata on small ${theme.brightness.name} screens',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = nativeApi(
          (path, _) async => path.startsWith('/chat/options')
              ? {
                  'personas': [
                    {
                      'id': 0,
                      'name': 'Customer relationship management assistant',
                      'sub_description': 'Default conversational agent with customer relationship tools and image generation',
                      'type': 'text',
                    },
                  ],
                  'models': [
                    {
                      'id': 'gpt-4o',
                      'title':
                          'A long configured model name from the live provider',
                    },
                  ],
                }
              : {'data': []},
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(body: ServerChatScreen(api: api)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Customer relationship management assistant'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('parses resource envelopes and rejects malformed chat data', () {
    expect(
      ChatService.records({
        'data': [
          {'id': 1},
        ],
      }).first['id'],
      1,
    );
    expect(
      () => ChatService.records({'message': 'invalid'}),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('native registry dispatches web chat and legacy scheduler directly', () {
    final api = nativeApi((_, body) async => {});
    expect(
      NativeModuleRegistry.build({'route_type': 'web_chat'}, api: api),
      isA<ServerChatScreen>().having((screen) => screen.web, 'web mode', true),
    );
    expect(
      NativeModuleRegistry.build({'route_type': 'social_calendar'}, api: api),
      isA<ServerSocialScreen>(),
    );
  });

  testWidgets('chat remains usable when conversation history fails', (
    tester,
  ) async {
    final api = nativeApi((path, body) async {
      if (path == '/chat/conversations') {
        throw const ApiFailure('History unavailable');
      }
      return options;
    });
    await tester.pumpWidget(app(ServerChatScreen(api: api)));
    await tester.pumpAndSettle();
    expect(find.text('GPT-4o'), findsOneWidget);
    expect(find.byTooltip('Send message'), findsOneWidget);
    expect(
      find.textContaining('Conversation history could not be loaded'),
      findsOneWidget,
    );
    expect(
      find.text('No personas or models are enabled for your plan.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale persona identifiers select the public default safely', (
    tester,
  ) async {
    final api = nativeApi(
      (path, body) async => path == '/chat/options' ? options : [],
    );
    await tester.pumpWidget(
      app(ServerChatScreen(api: api, initialPersona: '999')),
    );
    await tester.pumpAndSettle();
    expect(find.text('AI Assistant'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'web chat creates a URL-bound session streams and opens saved source citations',
    (tester) async {
      final calls = <String>[];
      final store = MemorySecureStore()
        ..values.addAll({'access_token': 'test', 'instance_hash': 'a' * 64});
      final api = MobileApi(
        store: store,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/license')) {
            return jsonResponse(license());
          }
          final path = request.url.path.replaceFirst('/api/mobile/v1', '');
          if (path == '/chat/options') {
            expect(request.url.queryParameters['context'], 'web');
            return jsonResponse(options);
          }
          if (path == '/chat/conversations' && request.method == 'GET') {
            return jsonResponse([]);
          }
          if (path == '/chat/conversations') {
            final body = jsonDecode(request.body) as Map;
            expect(body['context'], 'web');
            expect(body['website_url'], 'https://example.com');
            expect(body['category_id'], 0);
            return jsonResponse({
              'id': 3,
              'title': 'Web Assistant Chat',
              'website_url': 'https://example.com',
            });
          }
          expect(path, '/chat/conversations/3/stream');
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], 'gpt-4o');
          return http.Response(
            'data: ${jsonEncode({'delta': 'Answer\n\nSources:\n[Example](https://example.com)'})}\n\ndata: {"done":true}\n\n',
            200,
            headers: {'content-type': 'text/event-stream'},
          );
        }),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SecureStore.channel, (call) async {
            if (call.method == 'openUrl') {
              calls.add(call.arguments['url'] as String);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SecureStore.channel, null),
      );
      await tester.pumpWidget(app(ServerChatScreen(api: api, web: true)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Website URL (optional)'),
        'https://example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Message your assistant'),
        'Summarize this page',
      );
      await tester.tap(find.byTooltip('Send message'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Answer'), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'Example'));
      await tester.pumpAndSettle();
      expect(calls, ['https://example.com']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('web chat rejects non-HTTP URLs before creating a session', (
    tester,
  ) async {
    final requests = <String>[];
    final api = nativeApi((path, body) async {
      requests.add(path);
      return path.startsWith('/chat/options') ? options : [];
    });
    await tester.pumpWidget(app(ServerChatScreen(api: api, web: true)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Website URL (optional)'),
      'file:///private',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Message your assistant'),
      'Read',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid public website URL.'), findsOneWidget);
    expect(requests.where((path) => path == '/chat/conversations'), isEmpty);
  });

  testWidgets(
    'social composer generates captions through the production adapter',
    (tester) async {
      final api = nativeApi((path, body) async {
        expect(path, '/social-media/caption');
        expect(body['content'], 'Launch news');
        expect(body['platform'], 'x');
        return {'result': 'Generated launch caption'};
      });
      await tester.pumpWidget(
        app(
          SocialPostComposer(
            api: api,
            accounts: const [
              {
                'id': '7',
                'platform': 'x',
                'displayName': 'X',
                'handle': '@account',
                'isConnected': true,
              },
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Launch news');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.ensureVisible(find.text('Generate AI caption'));
      await tester.tap(find.text('Generate AI caption'));
      await tester.pumpAndSettle();
      expect(find.text('Generated launch caption'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final web in [false, true]) {
    testWidgets(
      '${web ? 'web' : 'general'} chat respects small keyboard viewports',
      (tester) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final api = nativeApi(
          (path, body) async => path.startsWith('/chat/options') ? options : [],
        );
        await tester.pumpWidget(app(ServerChatScreen(api: api, web: web)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'displays backend-driven chat types (AI Assistant, Chat Image, Realtime Voice Chat)',
    (tester) async {
      final multiPersonaOptions = {
        'personas': [
          {
            'id': 0,
            'name': 'AI Assistant',
            'type': 'assistant',
            'sub_description': 'Default conversational agent',
          },
          {
            'id': 4,
            'name': 'Chat Image',
            'type': 'image',
            'sub_description': 'Image Generator',
          },
          {
            'id': 5,
            'name': 'Realtime Voice Chat',
            'type': 'voice',
            'sub_description': 'Realtime Voice Chat bot',
          },
        ],
        'models': [
          {'id': 'gpt-4o', 'title': 'GPT-4o'},
        ],
      };
      final api = nativeApi(
        (path, body) async =>
            path.startsWith('/chat/options') ? multiPersonaOptions : [],
      );
      await tester.pumpWidget(app(ServerChatScreen(api: api)));
      await tester.pumpAndSettle();

      expect(find.text('AI Assistant'), findsOneWidget);
      await tester.tap(find.text('AI Assistant'));
      await tester.pumpAndSettle();

      expect(find.text('Chat Image'), findsWidgets);
      expect(find.text('Realtime Voice Chat'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deleting an active chat session issues DELETE request and resets active conversation',
    (tester) async {
      final calls = <String>[];
      final chats = [
        {
          'id': 42,
          'title': 'Test Chat to Delete',
          'type': 'assistant',
          'can_delete': true,
        },
      ];
      final api = nativeApi((path, body) async {
        calls.add(path);
        if (path.startsWith('/chat/options')) return options;
        if (path == '/chat/conversations') return chats;
        if (path == '/chat/conversations/42/messages') return [];
        if (path == '/chat/conversations/42') {
          return {'success': true, 'message': 'Chat session deleted', 'id': 42};
        }
        return [];
      });

      await tester.pumpWidget(app(ServerChatScreen(api: api)));
      await tester.pumpAndSettle();

      // Open chat 42
      await tester.tap(find.text('Conversation history'), warnIfMissed: false);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Test Chat to Delete').last);
      await tester.pumpAndSettle();

      // Delete button is visible when chat is selected
      final deleteButton = find.byKey(const ValueKey('delete-chat-button'));
      expect(deleteButton, findsOneWidget);

      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Delete Chat'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Verify DELETE API was called
      expect(calls, contains('/chat/conversations/42'));
      // Verify chat was deleted and UI reset
      expect(find.text('Chat session deleted'), findsOneWidget);
      expect(find.byKey(const ValueKey('delete-chat-button')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deletes individual session from conversation history modal and updates UI',
    (tester) async {
      final calls = <String>[];
      final chats = [
        {
          'id': 101,
          'title': 'Active Session 101',
          'type': 'assistant',
          'created_at': '2026-10-20T10:00:00Z',
          'can_delete': true,
        },
        {
          'id': 102,
          'title': 'Image Session 102',
          'type': 'image',
          'created_at': '2026-10-20T11:00:00Z',
          'can_delete': true,
        },
      ];
      final api = nativeApi((path, body) async {
        calls.add(path);
        if (path.startsWith('/chat/options')) return options;
        if (path == '/chat/conversations') return chats;
        if (path == '/chat/conversations/101/messages') return [];
        if (path == '/chat/conversations/102') {
          return {
            'success': true,
            'message': 'Chat session deleted',
            'id': 102,
          };
        }
        return [];
      });

      await tester.pumpWidget(app(ServerChatScreen(api: api)));
      await tester.pumpAndSettle();

      // Open conversation history modal
      await tester.tap(find.text('Conversation history'));
      await tester.pumpAndSettle();

      // Verify modal header and items
      expect(find.text('Conversation History'), findsOneWidget);
      expect(find.text('Active Session 101'), findsOneWidget);
      expect(find.text('Image Session 102'), findsOneWidget);

      // Verify individual delete button for session 102
      final deleteSession102 = find.byKey(const ValueKey('delete-session-102'));
      expect(deleteSession102, findsOneWidget);

      // Tap delete on session 102
      await tester.tap(deleteSession102);
      await tester.pumpAndSettle();

      // Confirmation dialog appears
      expect(find.text('Delete Conversation'), findsOneWidget);
      expect(find.text('Delete this conversation?'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      // Verify DELETE API called
      expect(calls, contains('/chat/conversations/102'));
      // Verify session 102 is removed immediately from modal
      expect(find.text('Image Session 102'), findsNothing);
      expect(find.text('Active Session 101'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clears all conversations at once and shows empty state', (
    tester,
  ) async {
    final calls = <String>[];
    final chats = [
      {
        'id': 201,
        'title': 'Session 201',
        'type': 'assistant',
        'created_at': '2026-10-20T10:00:00Z',
      },
      {
        'id': 202,
        'title': 'Session 202',
        'type': 'voice',
        'created_at': '2026-10-20T11:00:00Z',
      },
    ];
    final api = nativeApi((path, body) async {
      calls.add(path);
      if (path.startsWith('/chat/options')) return options;
      if (path == '/chat/conversations') return chats;
      if (path == '/chat/conversations/clear-all') {
        return {
          'success': true,
          'message': 'All conversation history cleared',
          'count': 2,
        };
      }
      return [];
    });

    await tester.pumpWidget(app(ServerChatScreen(api: api)));
    await tester.pumpAndSettle();

    // Open conversation history modal
    await tester.tap(find.text('Conversation history'));
    await tester.pumpAndSettle();

    // Clear All button is present in header
    final clearAllBtn = find.byKey(const ValueKey('clear-all-button'));
    expect(clearAllBtn, findsOneWidget);

    await tester.tap(clearAllBtn);
    await tester.pumpAndSettle();

    // Verify confirmation dialog
    expect(find.text('Clear All Conversations'), findsOneWidget);
    expect(
      find.text('Clear all conversations? This action cannot be undone.'),
      findsOneWidget,
    );

    // Confirm Clear All
    await tester.tap(find.widgetWithText(FilledButton, 'Clear All'));
    await tester.pumpAndSettle();

    // Verify bulk delete API called
    expect(calls, contains('/chat/conversations/clear-all'));
    // Verify chat view resets
    expect(find.text('How can I help today?'), findsOneWidget);

    // Open conversation history again - verify empty state
    await tester.tap(find.text('Conversation history'));
    await tester.pumpAndSettle();

    expect(find.text('No conversation history yet'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '+ New Chat'), findsOneWidget);

    // Tapping + New Chat closes modal
    await tester.tap(find.widgetWithText(OutlinedButton, '+ New Chat'));
    await tester.pumpAndSettle();

    expect(find.text('Conversation History'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
