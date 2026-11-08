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

  testWidgets('BlogPilot dashboard renders metrics, status card, agents, and posts', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'blog',
        'view_type': 'dashboard',
        'metrics': [
          {'label': 'Total Posts', 'value': 12, 'icon': 'invoice'},
          {'label': 'Scheduled', 'value': 4, 'icon': 'calendar'},
          {'label': 'Pending Posts', 'value': 3, 'icon': 'balance'},
          {'label': 'New Posts', 'value': 2, 'icon': 'paid'},
        ],
        'default_agent': {'id': 1, 'name': 'Tech Writer AI'},
        'generation_status': {'status': 'idle'},
        'show_agents': true,
        'agents': [
          {
            'id': 1,
            'name': 'Tech Writer AI',
            'is_active': true,
            'frequency': 'daily',
            'daily_post_count': 2,
            'schedule_days': ['Mon', 'Wed', 'Fri'],
            'schedule_times': ['09:00'],
          },
        ],
        'data': [
          {
            'id': 201,
            'title': 'AI Innovations in 2026',
            'agent': 'Tech Writer AI',
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
              'id': 'web:ext_blogpilot_dashboard',
              'title': 'BlogPilot Dashboard',
              'category': 'AI BlogPilot',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('BlogPilot Dashboard'), findsWidgets);
    expect(find.text('Total Posts'), findsOneWidget);
    expect(find.text('BlogPilot Status'), findsOneWidget);
    expect(find.textContaining('Tech Writer AI'), findsWidgets);
    expect(find.text('New post'), findsOneWidget);

    // Scroll down to see agents section
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('New agent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BlogPilot agents view renders agent cards and New agent header button', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'blog',
        'view_type': 'agents',
        'metrics': [],
        'show_agents': true,
        'data': [
          {
            'id': 10,
            'name': 'Finance Guru',
            'is_active': false,
            'frequency': 'weekly',
            'daily_post_count': 1,
            'schedule_days': ['Sunday'],
            'schedule_times': ['14:00'],
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
              'id': 'web:ext_blogpilot_agents',
              'title': 'BlogPilot Agents',
              'category': 'AI BlogPilot',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Finance Guru'), findsOneWidget);
    expect(find.text('New agent'), findsOneWidget);
    expect(find.text('Search agents…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('BlogPilot posts view renders status filter chips and actions', (tester) async {
    final recordsCalls = <Map>[];
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        recordsCalls.add(body);
        return {'status': 'success'};
      }
      return {
        'schema_version': 1,
        'kind': 'blog',
        'view_type': 'posts',
        'metrics': [
          {'label': 'Total Posts', 'value': 5, 'icon': 'invoice'},
        ],
        'data': [
          {
            'id': 55,
            'title': 'Autonomous Code Agents',
            'agent': 'Dev Writer',
            'status': 'draft',
            'scheduled_at': '2026-11-12 08:00:00',
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
              'id': 'web:ext_blogpilot_agents_archived_posts',
              'title': 'Archived Posts',
              'category': 'AI BlogPilot',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('All posts'), findsOneWidget);
    expect(find.text('Draft'), findsWidgets);
    expect(find.text('Scheduled'), findsOneWidget);
    expect(find.text('Published'), findsOneWidget);
    expect(find.text('Autonomous Code Agents'), findsOneWidget);

    // Open post menu
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Publish now'), findsOneWidget);
    expect(find.text('Edit post'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    // Tap publish
    await tester.tap(find.text('Publish now'));
    await tester.pumpAndSettle();

    expect(recordsCalls, isNotEmpty);
    expect(recordsCalls.last['operation'], equals('publish'));
    expect(recordsCalls.last['record_id'], equals(55));
    expect(tester.takeException(), isNull);
  });

  testWidgets('BlogPilot analytics view renders publication trend chart', (tester) async {
    final api = nativeApi((path, body) async {
      return {
        'schema_version': 1,
        'kind': 'blog',
        'view_type': 'analytics',
        'metrics': [
          {'label': 'Total Posts', 'value': 24, 'icon': 'invoice'},
          {'label': 'Published', 'value': 18, 'icon': 'paid'},
        ],
        'chart': [
          {'label': 'Jan', 'value': 2},
          {'label': 'Feb', 'value': 5},
          {'label': 'Mar', 'value': 8},
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
              'id': 'web:ext_blogpilot_analytics',
              'title': 'Analytics',
              'category': 'AI BlogPilot',
            },
            api: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Publication Trend (Last 12 Months)'), findsOneWidget);
    expect(find.text('Jan'), findsOneWidget);
    expect(find.text('Feb'), findsOneWidget);
    expect(find.text('Mar'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('WorkspaceRecordEditor creates blog_agent and validates required name', (tester) async {
    Map? savedBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        savedBody = body;
        return {'status': 'success'};
      }
      return {'status': 'success'};
    });
    final service = NativeWorkspaceService(api, 'web:ext_blogpilot_agents');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: WorkspaceRecordEditor(
          service: service,
          kind: 'blog_agent',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create blog agent'), findsOneWidget);
    expect(find.text('Agent name'), findsOneWidget);
    expect(find.text('Topics / Keywords'), findsOneWidget);
    expect(find.text('Tone of voice'), findsOneWidget);

    // Fill form
    await tester.enterText(find.widgetWithText(TextFormField, 'Agent name'), 'Crypto Analyst');
    await tester.enterText(find.widgetWithText(TextFormField, 'Topics / Keywords'), 'Bitcoin, Ethereum, DeFi');
    await tester.pumpAndSettle();

    // Scroll to submit button and tap
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create agent'));
    await tester.pumpAndSettle();

    expect(savedBody, isNotNull);
    expect(savedBody?['kind'], equals('blog_agent'));
    expect(savedBody?['operation'], equals('save'));
    final inputs = savedBody?['inputs'] as Map<dynamic, dynamic>?;
    expect(inputs?['name'], equals('Crypto Analyst'));
    expect(inputs?['selected_topics'], equals('Bitcoin, Ethereum, DeFi'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('WorkspaceRecordEditor creates blog_post with title and author dropdown', (tester) async {
    Map? savedBody;
    final api = nativeApi((path, body) async {
      if (path.contains('/native/records')) {
        savedBody = body;
        return {'status': 'success'};
      }
      return {'status': 'success'};
    });
    final service = NativeWorkspaceService(api, 'web:ext_blogpilot_agents_archived_posts');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: WorkspaceRecordEditor(
          service: service,
          kind: 'blog_post',
          lookups: const {
            'agents': [
              {'id': 7, 'name': 'Tech Lead AI'},
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Create blog post'), findsOneWidget);
    expect(find.text('Post title'), findsOneWidget);
    expect(find.text('Post content'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Post title'), 'Quantum Computing Revolution');
    await tester.enterText(find.widgetWithText(TextFormField, 'Post content'), 'Quantum computing will redefine encryption.');
    await tester.pumpAndSettle();

    // Scroll to submit button and tap
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -600));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Create post'));
    await tester.pumpAndSettle();

    expect(savedBody, isNotNull);
    expect(savedBody?['kind'], equals('blog_post'));
    expect(savedBody?['operation'], equals('save'));
    final inputs = savedBody?['inputs'] as Map<dynamic, dynamic>?;
    expect(inputs?['title'], equals('Quantum Computing Revolution'));
    expect(inputs?['content'], equals('Quantum computing will redefine encryption.'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('NativeWorkspaceService duplicatePost and toggleAgent call correct mutations', (tester) async {
    final calls = <Map<String, dynamic>>[];
    final api = nativeApi((path, body) async {
      calls.add(Map<String, dynamic>.from(body));
      return {'status': 'success'};
    });
    final service = NativeWorkspaceService(api, 'web:ext_blogpilot_dashboard');

    await service.duplicatePost(requestId: 'req-dup-1', id: 42);
    expect(calls.last['operation'], equals('duplicate'));
    expect(calls.last['kind'], equals('blog_post'));
    expect(calls.last['record_id'], equals(42));

    await service.toggleAgent(requestId: 'req-tog-1', id: 8);
    expect(calls.last['operation'], equals('toggle_active'));
    expect(calls.last['kind'], equals('blog_agent'));
    expect(calls.last['record_id'], equals(8));
  });
}
