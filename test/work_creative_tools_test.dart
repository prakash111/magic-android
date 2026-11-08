import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/native_workspace_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Work & Productivity Tools Tests', () {
    testWidgets('team workspace renders seats metrics, member list and invite button', (tester) async {
      final api = nativeApi((path, body) async {
        return {
          'schema_version': 1,
          'kind': 'team',
          'metrics': [
            {'label': 'Total Seats', 'value': 10, 'icon': 'paid'},
            {'label': 'Used Seats', 'value': 2, 'icon': 'invoice'},
            {'label': 'Active Members', 'value': 2, 'icon': 'calendar'},
            {'label': 'Available Seats', 'value': 8, 'icon': 'balance'},
          ],
          'data': [
            {
              'id': 1,
              'name': 'Sarah Connor',
              'email': 'sarah@example.com',
              'role': 'admin',
              'status': 'active',
              'created_at': '2026-11-01T10:00:00Z',
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
                'id': 'web:team_menu',
                'title': 'Team',
                'category': 'Work & productivity',
              },
              api: api,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Sarah Connor'), findsOneWidget);
      expect(find.text('sarah@example.com'), findsOneWidget);
      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.text('Invite member'), findsOneWidget);
    });

    testWidgets('api keys workspace renders providers and key configuration cards', (tester) async {
      final api = nativeApi((path, body) async {
        return {
          'schema_version': 1,
          'kind': 'api_keys',
          'metrics': [
            {'label': 'Total Providers', 'value': 3, 'icon': 'invoice'},
            {'label': 'Configured', 'value': 1, 'icon': 'paid'},
          ],
          'data': [
            {
              'id': 'openai',
              'provider': 'openai',
              'title': 'OpenAI API Key',
              'description': 'Used for GPT models, DALL-E',
              'is_configured': true,
              'key_masked': 'sk-12...99aa',
            },
            {
              'id': 'anthropic',
              'provider': 'anthropic',
              'title': 'Anthropic Claude API Key',
              'description': 'Used for Claude 3.5 Sonnet',
              'is_configured': false,
              'key_masked': '',
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
                'id': 'web:api_keys',
                'title': 'API Keys',
                'category': 'Work & productivity',
              },
              api: api,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Api Keys Setting'), findsOneWidget);
      expect(find.text('OpenAI API Key'), findsOneWidget);
      expect(find.text('sk-12...99aa'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Anthropic Claude API Key'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Anthropic Claude API Key'), findsOneWidget);
      expect(find.text('Using server-configured key'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Save'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('api keys workspace saves entered personal keys', (tester) async {
      var savedInputs = <String, dynamic>{};
      final api = nativeApi((path, body) async {
        if (path == '/native/records' && (body as Map?)?['operation'] == 'save') {
          savedInputs = Map<String, dynamic>.from(body['inputs'] as Map? ?? {});
          return {'success': true, 'message': 'Settings saved successfully.'};
        }
        return {
          'schema_version': 1,
          'kind': 'api_keys',
          'default_engine': 'gemini',
          'providers': [
            {
              'id': 'gemini',
              'provider': 'gemini',
              'title': 'Google Gemini API Key',
              'label': 'Gemini API Secret',
              'is_default': true,
              'is_configured': false,
              'key_masked': '',
            },
          ],
          'data': [],
        };
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: NativeWorkspaceScreen(
              module: const {
                'id': 'web:api_keys',
                'title': 'API Keys',
                'category': 'Work & productivity',
              },
              api: api,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Api Keys Setting'), findsOneWidget);
      expect(find.text('Gemini API Secret'), findsAtLeastNWidgets(1));

      await tester.enterText(find.byType(TextField).first, 'AIzaSy_custom_gemini_key_123');
      await tester.pump();

      await tester.scrollUntilVisible(find.text('Save'), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(savedInputs['gemini_api_keys'], equals('AIzaSy_custom_gemini_key_123'));
    });

    testWidgets('affiliates workspace renders referral link and payouts history', (tester) async {
      final api = nativeApi((path, body) async {
        return {
          'schema_version': 1,
          'kind': 'affiliates',
          'metrics': [
            {'label': 'Total Earnings', 'value': '\$450.00', 'icon': 'paid'},
            {'label': 'Available Balance', 'value': '\$150.00', 'icon': 'balance'},
          ],
          'referral_url': 'https://ai.zoomnearby.com/register?aff=TESTCODE',
          'currency': '\$',
          'data': [
            {
              'id': 10,
              'amount': 300.0,
              'status': 'completed',
              'created_at': '2026-11-05T12:00:00Z',
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
                'id': 'web:affiliates',
                'title': 'Affiliates',
                'category': 'Work & productivity',
              },
              api: api,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Your Referral Link'), findsOneWidget);
      expect(find.text('https://ai.zoomnearby.com/register?aff=TESTCODE'), findsOneWidget);
      expect(find.text('\$300.00'), findsOneWidget);
      expect(find.text('Request payout'), findsOneWidget);
    });

    testWidgets('integration workspace renders integration status and cards', (tester) async {
      final api = nativeApi((path, body) async {
        return {
          'schema_version': 1,
          'kind': 'integration',
          'metrics': [
            {'label': 'Total Integrations', 'value': 1, 'icon': 'invoice'},
            {'label': 'Connected', 'value': 1, 'icon': 'paid'},
          ],
          'data': [
            {
              'id': 1,
              'title': 'WordPress',
              'description': 'Publish directly to your blog',
              'is_connected': true,
              'image': null,
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
                'id': 'web:integration',
                'title': 'Integration',
                'category': 'Work & productivity',
              },
              api: api,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('WordPress'), findsOneWidget);
      expect(find.text('Publish directly to your blog'), findsOneWidget);
      expect(find.text('Connected'), findsAtLeastNWidgets(1));
    });
  });

  group('Creative Studio Tools Tests', () {
    testWidgets('video studio hub renders tools launcher and aggregated media cards', (tester) async {
      final api = nativeApi((path, body) async {
        return {
          'schema_version': 1,
          'kind': 'video_studio',
          'metrics': [
            {'label': 'Total Outputs', 'value': 2, 'icon': 'invoice'},
            {'label': 'Studio Tools', 'value': 6, 'icon': 'paid'},
          ],
          'data': [
            {
              'id': 'fall_1',
              'title': 'Cyberpunk futuristic city at dusk',
              'video_url': 'https://example.com/video1.mp4',
              'thumbnail_url': null,
              'tool': 'AI Video Pro',
              'status': 'complete',
              'duration': '15s',
              'created_at': '2026-11-08T14:00:00Z',
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
                'id': 'web:video_studio',
                'title': 'Video Studio',
                'category': 'Creative studio',
              },
              api: api,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Video Studio Tools'), findsOneWidget);
      expect(find.text('Cyberpunk futuristic city at dusk'), findsOneWidget);
      expect(find.text('AI Video Pro'), findsOneWidget);
      expect(find.text('15s'), findsOneWidget);
    });

    testWidgets('media workspaces render properly across video and image tools', (tester) async {
      final testCases = [
        {'kind': 'video_pro', 'title': 'Cinematic drone shot'},
        {'kind': 'video_agent', 'title': 'Explainer avatar session'},
        {'kind': 'auto_edit', 'title': 'Rough cut to final edit'},
        {'kind': 'product_shot', 'title': 'Perfume bottle studio background'},
        {'kind': 'presentation', 'title': 'AI Pitch Deck 2026'},
        {'kind': 'viral_clips', 'title': 'Top 5 productivity hacks'},
      ];

      for (final tc in testCases) {
        final api = nativeApi((path, body) async {
          return {
            'schema_version': 1,
            'kind': tc['kind'],
            'metrics': [
              {'label': 'Total', 'value': 1, 'icon': 'invoice'},
            ],
            'data': [
              {
                'id': 1,
                'title': tc['title'],
                'video_url': 'https://example.com/out.mp4',
                'status': 'complete',
                'duration': '30s',
                'created_at': '2026-11-08T15:00:00Z',
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
                key: ValueKey(tc['kind']),
                module: {
                  'id': 'web:${tc['kind']}',
                  'title': '${tc['kind']} Studio',
                  'category': 'Creative studio',
                },
                api: api,
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        expect(find.text(tc['title']!), findsOneWidget);
      }
    });

    test('all 33 tools route to native screens without schema fallbacks', () {
      final allTools = [
        // Work & productivity
        {'id': 'web:dashboard', 'route_type': 'dashboard'},
        {'id': 'web:workbook', 'route_type': 'documents'},
        {'id': 'web:favorites', 'route_type': 'tool_directory'},
        {'id': 'web:seo_tool_extension', 'route_type': 'tool_directory'},
        {'id': 'web:ai_rewriter', 'route_type': 'writer_tool', 'tool': {'title': 'AI Rewriter'}},
        {'id': 'web:ai_editor', 'route_type': 'tool_directory'},
        {'id': 'web:ai_article_wizard', 'route_type': 'writer_tool', 'tool': {'title': 'Article Wizard'}},
        {'id': 'web:ai_plagiarism_extension', 'route_type': 'writer_tool', 'tool': {'title': 'Plagiarism Checker'}},
        {'id': 'web:ai_detector_extension', 'route_type': 'writer_tool', 'tool': {'title': 'AI Detector'}},
        {'id': 'web:team_menu', 'route_type': 'team'},
        {'id': 'web:api_keys', 'route_type': 'api_keys'},
        {'id': 'web:affiliates', 'route_type': 'affiliates'},
        {'id': 'web:integration', 'route_type': 'integration'},
        {'id': 'web:ai_influencer', 'route_type': 'ai_influencer'},
        {'id': 'web:ai_persona', 'route_type': 'ai_persona'},
        // Creative studio
        {'id': 'web:creative_suite', 'route_type': 'creative_suite'},
        {'id': 'web:url_to_video', 'route_type': 'native_media'},
        {'id': 'web:influencer_avatar', 'route_type': 'native_media'},
        {'id': 'web:ai_realtime_image', 'route_type': 'extension_workflow'},
        {'id': 'web:ai_image_pro_real_time', 'route_type': 'extension_workflow'},
        {'id': 'web:ai_image_pro_edit', 'route_type': 'native_media'},
        {'id': 'web:advanced_image', 'route_type': 'native_media'},
        {'id': 'web:ai_captions', 'route_type': 'extension_workflow'},
        {'id': 'web:video_editor', 'route_type': 'extension_workflow'},
        {'id': 'web:video_studio', 'route_type': 'video_studio'},
        {'id': 'web:ai_video_pro', 'route_type': 'video_pro'},
        {'id': 'web:video_agent', 'route_type': 'video_agent'},
        {'id': 'web:auto_edit_videos', 'route_type': 'auto_edit'},
        {'id': 'web:ai_product_shot', 'route_type': 'product_shot'},
        {'id': 'web:ai_presentation', 'route_type': 'presentation'},
        {'id': 'web:ai_avatar', 'route_type': 'ai_avatar'},
        {'id': 'web:ai_image_pro_get_inspired', 'route_type': 'image_pro'},
        {'id': 'web:viral_clips', 'route_type': 'viral_clips'},
      ];

      for (final tool in allTools) {
        final widget = NativeModuleRegistry.build(tool);
        expect(widget, isNot(isA<NativeSchemaScreen>()), reason: '${tool['id']} should not route to NativeSchemaScreen');
      }
    });
  });
}
