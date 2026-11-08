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

  testWidgets('Social Media Agent dashboard renders metrics, status card, agents, and posts', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'social_agent',
        'view_type': 'dashboard',
        'metrics': [
          {'label': 'Total Posts', 'value': 24, 'icon': 'invoice'},
          {'label': 'Scheduled', 'value': 8, 'icon': 'calendar'},
          {'label': 'Pending Posts', 'value': 5, 'icon': 'balance'},
          {'label': 'New Posts', 'value': 3, 'icon': 'paid'},
        ],
        'default_agent': {'id': 1, 'name': 'Growth Hacker AI'},
        'generation_status': {'status': 'idle'},
        'show_agents': true,
        'platforms': [
          {'id': 10, 'name': 'Twitter', 'platform': 'twitter', 'username': 'growth_ai'},
          {'id': 11, 'name': 'LinkedIn', 'platform': 'linkedin', 'username': 'growth_company'},
        ],
        'agents': [
          {
            'id': 1,
            'name': 'Growth Hacker AI',
            'is_active': true,
            'frequency': 'daily',
            'daily_post_count': 3,
            'schedule_days': ['Monday', 'Wednesday', 'Friday'],
            'schedule_times': ['09:00', '15:00'],
            'platforms': [
              {'id': 10, 'name': 'Twitter', 'platform': 'twitter'},
              {'id': 11, 'name': 'LinkedIn', 'platform': 'linkedin'},
            ],
          },
        ],
        'data': [
          {
            'id': 101,
            'title': '10 tips to scale AI startups in 2026',
            'content': '10 tips to scale AI startups in 2026',
            'agent': 'Growth Hacker AI',
            'platform': 'twitter',
            'post_type': 'text',
            'status': 'draft',
            'scheduled_at': '2026-11-10 10:00:00',
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
              'id': 'web:ext_social_media_agent_dashboard',
              'title': 'Social Media Agent Dashboard',
              'category': 'Social media agents',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Social Media Agent Dashboard'), findsWidgets);
    expect(find.text('Total Posts'), findsOneWidget);
    expect(find.text('Social Media Agent Status'), findsOneWidget);
    expect(find.textContaining('Growth Hacker AI'), findsWidgets);
    expect(find.text('New post'), findsOneWidget);

    // Scroll down to see agent cards and actions
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('New agent'), findsOneWidget);
    expect(find.text('TWITTER'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Social Media Agent agents view renders agent cards with platform chips', (tester) async {
    final recordsCalls = <Map>[];
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        recordsCalls.add(body);
        return {'status': 'success'};
      }
      return {
        'schema_version': 1,
        'kind': 'social_agent',
        'view_type': 'agents',
        'metrics': [],
        'show_agents': true,
        'platforms': [
          {'id': 10, 'name': 'Instagram', 'platform': 'instagram', 'username': 'brand_ig'},
        ],
        'data': [
          {
            'id': 5,
            'name': 'Visual Storyteller',
            'is_active': true,
            'frequency': 'daily',
            'daily_post_count': 1,
            'schedule_days': ['Tuesday', 'Thursday'],
            'schedule_times': ['11:00'],
            'platforms': [
              {'id': 10, 'name': 'Instagram', 'platform': 'instagram'},
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
              'id': 'web:ext_social_media_agent_agents',
              'title': 'Social Media Agents',
              'category': 'Social media agents',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Visual Storyteller'), findsOneWidget);
    expect(find.text('New agent'), findsOneWidget);
    expect(find.text('Search agents…'), findsOneWidget);
    expect(find.text('Instagram'), findsOneWidget);

    // Open popup menu on agent card
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Pause agent'), findsOneWidget);
    expect(find.text('Edit agent'), findsOneWidget);
    expect(find.text('Delete agent'), findsOneWidget);

    // Tap pause agent
    await tester.tap(find.text('Pause agent'));
    await tester.pumpAndSettle();

    expect(recordsCalls, isNotEmpty);
    expect(recordsCalls.last['operation'], equals('toggle_active'));
    expect(recordsCalls.last['kind'], equals('social_agent'));
    expect(recordsCalls.last['record_id'], equals(5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Social Media Agent posts view renders status chips, platform tags, and post actions', (tester) async {
    final recordsCalls = <Map>[];
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        recordsCalls.add(body);
        return {'status': 'success'};
      }
      return {
        'schema_version': 1,
        'kind': 'social_agent',
        'view_type': 'posts',
        'metrics': [
          {'label': 'Total Posts', 'value': 10, 'icon': 'invoice'},
          {'label': 'Published', 'value': 6, 'icon': 'paid'},
          {'label': 'Scheduled', 'value': 2, 'icon': 'calendar'},
          {'label': 'Drafts', 'value': 2, 'icon': 'balance'},
        ],
        'data': [
          {
            'id': 77,
            'title': 'Weekly product release notes thread',
            'content': 'Weekly product release notes thread: 1. Speed boost 2. New AI styles',
            'agent': 'Product Marketer',
            'platform': 'twitter',
            'post_type': 'text',
            'status': 'draft',
            'scheduled_at': '2026-11-15 14:00:00',
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
              'id': 'web:ext_social_media_agent_agents_archived_posts',
              'title': 'Archived Posts',
              'category': 'Social media agents',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All posts'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Scheduled'), findsWidgets);
    expect(find.text('Published'), findsWidgets);
    expect(find.text('Weekly product release notes thread'), findsOneWidget);
    expect(find.text('TWITTER'), findsOneWidget);

    // Open post menu
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Publish now'), findsOneWidget);
    expect(find.text('Edit post'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Tap duplicate
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();

    expect(recordsCalls, isNotEmpty);
    expect(recordsCalls.last['operation'], equals('duplicate'));
    expect(recordsCalls.last['kind'], equals('social_post'));
    expect(recordsCalls.last['record_id'], equals(77));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Social Media Agent analytics view renders 12-month publication trend chart', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'social_agent',
        'view_type': 'analytics',
        'metrics': [
          {'label': 'Total Posts', 'value': 80, 'icon': 'invoice'},
          {'label': 'Published', 'value': 75, 'icon': 'paid'},
        ],
        'chart': [
          {'label': 'Nov', 'value': 12},
          {'label': 'Oct', 'value': 18},
          {'label': 'Sep', 'value': 15},
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
              'id': 'web:ext_social_media_agent_analytics',
              'title': 'Social Analytics',
              'category': 'Social media agents',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Publication Trend (Last 12 Months)'), findsOneWidget);
    expect(find.text('Nov'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WorkspaceRecordEditor creates and saves social_agent record with connected platform filter chips', (tester) async {
    final savedRecords = <Map>[];
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        savedRecords.add(body);
        return {'status': 'success', 'record_id': 99};
      }
      return {};
    });

    final service = NativeWorkspaceService(api, 'web:ext_social_media_agent_agents');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkspaceRecordEditor(
            service: service,
            kind: 'social_agent',
            lookups: const {
              'platforms': [
                {'id': 1, 'name': 'Twitter/X', 'platform': 'twitter'},
                {'id': 2, 'name': 'LinkedIn', 'platform': 'linkedin'},
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create social agent'), findsOneWidget);
    expect(find.text('Connected platforms'), findsOneWidget);
    expect(find.text('Twitter/X'), findsOneWidget);
    expect(find.text('LinkedIn'), findsOneWidget);

    // Enter agent name
    await tester.enterText(find.byType(TextFormField).first, 'Viral AI Agent');

    // Select Twitter/X chip
    await tester.tap(find.text('Twitter/X'));
    await tester.pumpAndSettle();

    // Scroll down and save
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create agent'));
    await tester.pumpAndSettle();

    expect(savedRecords, isNotEmpty);
    expect(savedRecords.last['kind'], equals('social_agent'));
    expect(savedRecords.last['inputs']['name'], equals('Viral AI Agent'));
    expect(savedRecords.last['inputs']['platform_ids'], contains(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('WorkspaceRecordEditor creates and saves social_post record with platform dropdown', (tester) async {
    final savedRecords = <Map>[];
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        savedRecords.add(body);
        return {'status': 'success', 'record_id': 105};
      }
      return {};
    });

    final service = NativeWorkspaceService(api, 'web:ext_social_media_agent_posts');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: WorkspaceRecordEditor(
            service: service,
            kind: 'social_post',
            lookups: const {
              'platforms': [
                {'id': 1, 'name': 'Twitter/X', 'platform': 'twitter'},
              ],
              'agents': [
                {'id': 1, 'name': 'Viral AI Agent'},
              ],
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create social post'), findsOneWidget);

    // Enter content
    await tester.enterText(find.byType(TextFormField).first, 'Excited to announce our new mobile app release!');

    // Tap Save
    await tester.tap(find.text('Create post'));
    await tester.pumpAndSettle();

    expect(savedRecords, isNotEmpty);
    expect(savedRecords.last['kind'], equals('social_post'));
    expect(savedRecords.last['inputs']['content'], equals('Excited to announce our new mobile app release!'));
    expect(tester.takeException(), isNull);
  });
}
