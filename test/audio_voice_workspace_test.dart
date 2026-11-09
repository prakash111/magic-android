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

  testWidgets('Voice Chatbots workspace renders metrics and voice bot card', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'voice_chatbots',
        'metrics': [
          {'label': 'Total Voice Bots', 'value': '1', 'icon': 'voice_bot'},
          {'label': 'Active Bots', 'value': '1', 'icon': 'active'},
        ],
        'data': [
          {
            'id': 20,
            'title': 'Concierge Assistant',
            'active': true,
            'language': 'en',
            'voice_id': '21m00Tcm4TlvDq8ikWAM',
            'welcome_message': 'Welcome to our voice concierge!',
            'instructions': 'Answer concisely and warmly.',
            'frame_url': 'https://ai.zoomnearby.com/ext/chatbot-voice/20/frame',
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
              'id': 'ext_voice_chatbot',
              'title': 'AI Voice Bots',
              'category': 'Audio & voice',
              'route': 'dashboard.chatbot-voice.index',
              'route_type': 'voice_chatbots',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Total Voice Bots'), findsOneWidget);
    expect(find.text('Active Bots'), findsOneWidget);
    expect(find.text('Concierge Assistant'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Lang: EN'), findsOneWidget);
    expect(find.text('Voice: 21m00Tcm4TlvDq8ikWAM'), findsOneWidget);
    expect(find.text('Welcome: Welcome to our voice concierge!'), findsOneWidget);
  });

  testWidgets('Voice Chatbots empty state renders action button', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'voice_chatbots',
        'metrics': [
          {'label': 'Total Voice Bots', 'value': '0', 'icon': 'voice_bot'},
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
              'id': 'ext_voice_chatbot',
              'title': 'AI Voice Bots',
              'category': 'Audio & voice',
              'route': 'dashboard.chatbot-voice.index',
              'route_type': 'voice_chatbots',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('No voice bots configured'), findsOneWidget);
    expect(find.text('New voice bot'), findsWidgets);
  });

  testWidgets('WorkspaceRecordEditor validates and saves voice_chatbot', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map? lastMutateBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        lastMutateBody = body;
        return {
          'message': 'Voice bot saved.',
          'record_id': 20,
        };
      }
      return {'data': []};
    });

    final service = NativeWorkspaceService(api, 'ext_voice_chatbot');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkspaceRecordEditor(
            service: service,
            kind: 'voice_chatbot',
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Create voice bot'), findsWidgets);

    // Try submitting without required title
    await tester.tap(find.widgetWithText(FilledButton, 'Create voice bot'));
    await tester.pumpAndSettle();
    expect(lastMutateBody, isNull);

    // Fill title and parameters
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Voice Bot Title'),
      'Sales Calling Agent',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Voice ID / Model'),
      'alloy',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Welcome Greeting'),
      'Hello, thanks for calling!',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'System Prompt / Instructions'),
      'You are an SDR scheduling meetings.',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Create voice bot'));
    await tester.pumpAndSettle();

    expect(lastMutateBody, isNotNull);
    expect(lastMutateBody!['kind'], 'voice_chatbot');
    expect(lastMutateBody!['operation'], 'save');
    expect(lastMutateBody!['inputs']['title'], 'Sales Calling Agent');
    expect(lastMutateBody!['inputs']['voice_id'], 'alloy');
    expect(lastMutateBody!['inputs']['welcome_message'], 'Hello, thanks for calling!');
    expect(lastMutateBody!['inputs']['instructions'], 'You are an SDR scheduling meetings.');
  });

  testWidgets('AI Music workspace renders track card and audio player action', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'ai_music',
        'metrics': [
          {'label': 'Total Tracks', 'value': '1', 'icon': 'music'},
        ],
        'data': [
          {
            'id': 33,
            'title': 'Synthwave Odyssey',
            'prompt': 'Upbeat 80s synthwave with retro drums and neon bassline',
            'audio_url': 'https://ai.zoomnearby.com/uploads/music/track-33.mp3',
            'provider': 'elevenlabs',
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
              'id': 'ai_music',
              'title': 'AI Music',
              'category': 'Audio & voice',
              'route': 'dashboard.user.ai-music.index',
              'route_type': 'ai_music',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Total Tracks'), findsOneWidget);
    expect(find.text('Synthwave Odyssey'), findsOneWidget);
    expect(find.text('ELEVENLABS'), findsOneWidget);
    expect(find.text('Upbeat 80s synthwave with retro drums and neon bassline'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('AI Music delete card popup menu triggers delete mutation', (tester) async {
    Map? deleteBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        deleteBody = body;
        return {'status': 'success', 'message': 'Audio track deleted.'};
      }
      return {
        'schema_version': 1,
        'kind': 'ai_music',
        'metrics': [],
        'data': [
          {
            'id': 33,
            'title': 'Synthwave Odyssey',
            'prompt': 'Retro synthwave track',
            'audio_url': 'https://ai.zoomnearby.com/uploads/music/track-33.mp3',
            'provider': 'elevenlabs',
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
              'id': 'ai_music',
              'title': 'AI Music',
              'category': 'Audio & voice',
              'route': 'dashboard.user.ai-music.index',
              'route_type': 'ai_music',
              'available': true,
            },
            api: api,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Delete track'), findsOneWidget);
    await tester.tap(find.text('Delete track'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Synthwave Odyssey?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleteBody, isNotNull);
    expect(deleteBody!['kind'], 'ai_music');
    expect(deleteBody!['operation'], 'delete');
    expect(deleteBody!['record_id'], 33);
  });
}
