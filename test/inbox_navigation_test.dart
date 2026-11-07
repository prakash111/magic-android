import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/screens/inbox/inbox_screen.dart';
import 'package:magicai_mobile/screens/native_module_screen.dart';
import 'package:magicai_mobile/screens/home_screen.dart';

import 'extension_workflow_test.dart' show workflowApi;
import 'unified_inbox_test.dart' as fixture;

const inboxModule = {
  'id': 'web:ext-marketing-bot-inbox',
  'route_type': 'marketing_inbox',
  'title': 'Inbox',
  'category': 'Messaging',
  'available': true,
};
const settingsModule = {
  'id': 'web:ext-marketing-bot-settings',
  'route_type': 'marketing_settings',
  'title': 'Marketing Bot Settings',
  'category': 'Messaging',
  'available': true,
};
final auditModules = <Map<String, dynamic>>[
  inboxModule,
  {
    'id': 'web:telegram-groups',
    'route_type': 'schema',
    'title': 'Telegram Groups',
    'category': 'Messaging',
    'available': true,
  },
  {
    'id': 'web:whatsapp',
    'route_type': 'schema',
    'title': 'WhatsApp',
    'category': 'Messaging',
    'available': true,
  },
  {
    'id': 'web:marketing-bot',
    'route_type': 'marketing_dashboard',
    'title': 'Marketing Bot',
    'category': 'Messaging',
    'available': true,
  },
  settingsModule,
  {
    'id': 'web:contact-lists',
    'route_type': 'schema',
    'title': 'Contact Lists',
    'category': 'Messaging',
    'available': true,
  },
  {
    'id': 'web:segments',
    'route_type': 'schema',
    'title': 'Segments',
    'category': 'Messaging',
    'available': true,
  },
];
MobileApi navigationApi({
  bool empty = false,
  List<String>? requests,
  Completer<dynamic>? inboxPending,
}) => workflowApi((request) async {
  final path = request.url.path;
  requests?.add(path);
  if (path.endsWith('/config')) {
    return {
      'app': 'magicai',
      'schema_version': 1,
      'capabilities': {'unified_inbox': true},
      'navigation': [
        {'id': 'home', 'component': 'dashboard', 'label': 'Home'},
        {'id': 'explore', 'component': 'workspace', 'label': 'Explore'},
        {'id': 'account', 'component': 'account', 'label': 'Account'},
      ],
      'modules': auditModules,
      'tools': [],
      'user': {'id': 1},
      'credits': {},
    };
  }
  if (path.endsWith('/me/favorites')) {
    return {
      'tool_ids': [inboxModule['id']],
    };
  }
  if (path.endsWith('/me/prefs')) return {'data': {}};
  if (path.endsWith('/modules')) return {'data': auditModules};
  if (path.endsWith('/inbox/counts')) {
    return empty
        ? {
            'all': 0,
            'telegram': 0,
            'whatsapp': 0,
            'needs_reply': 0,
            'chats_total': 0,
          }
        : {
            'all': 4,
            'telegram': 3,
            'whatsapp': 1,
            'needs_reply': 2,
            'chats_total': 4,
          };
  }
  if (path.endsWith('/inbox/chats')) {
    if (inboxPending != null) return inboxPending.future;
    final rows = empty
        ? <Map<String, dynamic>>[]
        : fixture.sampleChats
              .where(
                (chat) => ('${chat['title']}').toLowerCase().contains(
                  (request.url.queryParameters['q'] ?? '').toLowerCase(),
                ),
              )
              .toList();
    return {
      'data': rows,
      'meta': empty
          ? {
              'all': 0,
              'telegram': 0,
              'whatsapp': 0,
              'needs_reply': 0,
              'chats_total': 0,
            }
          : {
              'all': 4,
              'telegram': 3,
              'whatsapp': 1,
              'needs_reply': 2,
              'chats_total': 4,
            },
      'networks': [],
    };
  }
  if (path.endsWith('/native/extension')) {
    return {
      'telegram': {'configured': true, 'name': 'Test bot'},
      'providers': ['meta'],
      'whatsapp': {'whatsapp_provider': 'meta', 'meta_token_configured': true},
      'data': [],
      'metrics': [],
      'periods': {},
      'current_page': 1,
      'last_page': 1,
    };
  }
  if (path.endsWith('/native/workspace')) {
    return {
      'schema_version': 1,
      'kind': 'collection',
      'data': [],
      'modules': [],
      'current_page': 1,
      'last_page': 1,
    };
  }
  return {'data': [], 'stats': [], 'chart': []};
});
Future<void> explore(
  WidgetTester tester,
  MobileApi api, {
  List<Map<String, dynamic>>? modules,
}) => fixture.mount(
  tester,
  Scaffold(
    body: WorkspaceScreen(
      modules: modules ?? auditModules,
      user: const {'id': 1},
      api: api,
      refresh: () async {},
    ),
  ),
);
void singleHeader({required bool pushed}) {
  expect(find.byType(AppBar), findsOneWidget);
  expect(find.byType(BackButton), pushed ? findsOneWidget : findsNothing);
  expect(find.byIcon(Icons.arrow_back).evaluate().length, lessThanOrEqualTo(1));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final fonts = Platform.environment['INBOX_FONT_DIR'];
    if (fonts == null) return;
    final loader = FontLoader('Roboto');
    for (final file in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(await File('$fonts/$file').readAsBytes()),
        ),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('$fonts/MaterialIcons-Regular.otf').readAsBytes(),
          ),
        ),
      );
    await icons.load();
  });
  for (final module in auditModules) {
    testWidgets('${module['title']} through Explore has exactly one header', (
      tester,
    ) async {
      await explore(tester, navigationApi(), modules: [module]);
      final card = find.byKey(ValueKey('explore-tool-${module['id']}'));
      await tester.ensureVisible(card);
      await tester.tap(card);
      await tester.pumpAndSettle();
      singleHeader(pushed: true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'Favorites Inbox uses its own single header and contains no connection UI',
    (tester) async {
      final requests = <String>[];
      await explore(
        tester,
        navigationApi(requests: requests),
        modules: const [inboxModule],
      );
      final favorite = find
          .descendant(
            of: find.byType(SliverPersistentHeader),
            matching: find.text('Inbox'),
          )
          .first;
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      singleHeader(pushed: true);
      expect(find.byTooltip('Refresh'), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.text('Connect Telegram and WhatsApp'), findsNothing);
      expect(find.textContaining('webhook'), findsNothing);
      expect(
        requests.where((path) => path.contains('inbox/connections')),
        isEmpty,
      );
      await fixture.screenshot(tester, 'after-favorites');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Inbox opened from Explore search and list has the same header', (
    tester,
  ) async {
    await explore(tester, navigationApi());
    await tester.enterText(find.byType(TextField).first, 'Inbox');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('explore-tool-${inboxModule['id']}')));
    await tester.pumpAndSettle();
    singleHeader(pushed: true);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('bottom navigation Inbox has one header and no back arrow', (
    tester,
  ) async {
    await fixture.mount(
      tester,
      HomeScreen(api: navigationApi(), onThemeChanged: (_) {}),
    );
    await tester.tap(find.widgetWithText(NavigationDestination, 'Inbox'));
    await tester.pumpAndSettle();
    singleHeader(pushed: false);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'empty Inbox navigates to the existing native Marketing Bot Settings screen',
    (tester) async {
      final requests = <String>[];
      final api = navigationApi(empty: true, requests: requests);
      await fixture.mount(tester, InboxScreen(api: api));
      expect(
        find.text(
          'No chats yet. Connect channels in Chatbot or Marketing Bot settings.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Open Marketing Bot settings'));
      await tester.pumpAndSettle();
      singleHeader(pushed: true);
      expect(find.byType(NativeModuleScreen), findsOneWidget);
      expect(find.text('Marketing Bot Settings'), findsOneWidget);
      expect(requests, contains('/api/mobile/v1/native/extension'));
      expect(
        requests.where(
          (path) =>
              path.contains('inbox/connections') ||
              path.contains('workspace/open'),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'connection hint is absent during loading and with populated or filtered chats',
    (tester) async {
      final pending = Completer<dynamic>();
      await fixture.mount(
        tester,
        InboxScreen(api: navigationApi(inboxPending: pending)),
      );
      expect(find.text('Open Marketing Bot settings'), findsNothing);
      pending.complete({
        'data': fixture.sampleChats,
        'meta': {
          'all': 4,
          'telegram': 3,
          'whatsapp': 1,
          'needs_reply': 2,
          'chats_total': 4,
        },
      });
      await tester.pumpAndSettle();
      expect(find.text('Open Marketing Bot settings'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await fixture.mount(tester, InboxScreen(api: navigationApi()));
      await tester.enterText(find.byType(TextField), 'unmatched search');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('No chats match your search.'), findsOneWidget);
      expect(find.text('Open Marketing Bot settings'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
