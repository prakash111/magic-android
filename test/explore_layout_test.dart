import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/home_screen.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native_screen_test.dart' show nativeApi;

const tools = <Map<String, dynamic>>[
  {
    'id': 'creative',
    'title': 'Creative Suite',
    'description': 'Design ads, posts and assets for your next campaign.',
    'category': 'Creative studio',
    'available': true,
  },
  {
    'id': 'avatar',
    'title': 'Influencer Avatar',
    'description': 'Create a digital presenter for your audience.',
    'category': 'Creative studio',
    'available': true,
  },
  {
    'id': 'voice',
    'title': 'AI Realtime Voice Chat',
    'description': 'Talk to AI hands-free.',
    'category': 'Audio & voice',
    'available': false,
  },
];

Widget explore({double scale = 1, ThemeData? theme, int userId = 7}) =>
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        resizeToAvoidBottomInset: true,
        body: WorkspaceScreen(
          modules: tools,
          user: {'id': userId, 'name': 'Prakash'},
          refresh: () async {},
        ),
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'grid is default; list persists and keeps search and categories',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(explore());
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsNWidgets(2));
      expect(find.text('P'), findsOneWidget);
      expect(find.text('2 tools'), findsOneWidget);
      expect(find.text('1 tool'), findsOneWidget);
      final first = tester.getRect(
        find.byKey(const ValueKey('explore-tool-creative')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('explore-tool-avatar')),
      );
      expect(first.top, second.top);
      expect(first.right, lessThan(second.left));
      expect(first.width / first.height, closeTo(1.1, .15));
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsNothing);
      final row = tester.getRect(
        find.byKey(const ValueKey('explore-tool-creative')),
      );
      expect(row.width, 390);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
      final listButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('explore-list-toggle')),
      );
      expect(listButton.isSelected, isTrue);
      expect(
        listButton.style!.backgroundColor!.resolve({}),
        const Color(0xFF6366F1),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('explore_layout:magicai.example.test:7'), 'list');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Creative studio'));
      await tester.enterText(find.byType(TextField), 'avatar');
      await tester.pumpAndSettle();
      expect(find.text('Creative Suite'), findsNothing);
      expect(find.text('Influencer Avatar'), findsOneWidget);
      await tester.tap(find.byTooltip('Grid view'));
      await tester.pumpAndSettle();
      expect(find.text('Creative Suite'), findsNothing);
      expect(find.byType(SliverGrid), findsOneWidget);
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      SharedPreferences.resetStatic();
      await tester.pumpWidget(explore());
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsNothing);
      expect(find.text('Creative Suite'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(explore(userId: 8));
      await tester.pumpAndSettle();
      expect(find.byType(SliverGrid), findsNWidgets(2));
    },
  );

  testWidgets(
    'header keeps account and search and removes notification controls',
    (tester) async {
      await tester.pumpWidget(explore());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Search tools'));
      await tester.pump();
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
      expect(find.byTooltip('Notifications'), findsNothing);
      expect(find.byType(Badge), findsNothing);
      expect(find.byIcon(Icons.notifications_none_rounded), findsNothing);
      expect(find.text('P'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(430, 932),
  ]) {
    for (final light in [false, true]) {
      testWidgets(
        'both modes fit $size, 130% text, ${light ? 'light' : 'dark'} and keyboard',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpWidget(
            explore(scale: 1.3, theme: light ? AppTheme.lightTheme : null),
          );
          await tester.pumpAndSettle();
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -120),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, 1000),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('List view'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          tester.view.viewInsets = FakeViewPadding(bottom: size.height * .4);
          await tester.enterText(find.byType(TextField), 'voice');
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'five primary destinations keep Chatbot centered and use the reference pill styling',
    (tester) async {
      final api = nativeApi((path, _) async {
        if (path == '/config') {
          return {
            'app': 'magicai',
            'schema_version': 1,
            'navigation': [
              {'id': 'home', 'label': 'Home', 'component': 'dashboard'},
              {'id': 'explore', 'label': 'Explore', 'component': 'workspace'},
              {'id': 'chat', 'label': 'Chat', 'component': 'chat'},
              {'id': 'calendar', 'label': 'Calendar', 'component': 'social'},
              {'id': 'extra', 'label': 'Documents', 'component': 'documents'},
              {'id': 'account', 'label': 'Account', 'component': 'account'},
            ],
            'modules': tools,
            'tools': [],
            'credits': {},
            'user': {'name': 'Prakash', 'id': 7},
          };
        }
        throw StateError('Unexpected request $path');
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: HomeScreen(api: api, onThemeChanged: (_) {}),
        ),
      );
      await tester.pumpAndSettle();
      final destinations = tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .toList();
      expect(destinations.map((item) => item.label), [
        'Home',
        'Explore',
        'Chatbot',
        'Calendar',
        'Account',
      ]);
      expect(
        find.byKey(const ValueKey('chatbot-floating-action')),
        findsOneWidget,
      );
      final context = tester.element(find.byType(NavigationBar));
      final style = NavigationBarTheme.of(context);
      expect(style.indicatorColor, const Color(0xFF6366F1));
      expect(style.indicatorShape, isA<StadiumBorder>());
      expect(
        style.iconTheme!.resolve({WidgetState.selected})!.color,
        Colors.white,
      );
      expect(style.iconTheme!.resolve({})!.color, const Color(0xFF818898));
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        1,
      );
      expect(find.byType(AppBar), findsNothing);
      expect(find.byTooltip('Search tools'), findsOneWidget);
      await tester.tap(find.text('P'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        4,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
