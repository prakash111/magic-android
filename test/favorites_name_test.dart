import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/services/workspace_catalog.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/theme/brand_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

const favoritesTools = <Map<String, dynamic>>[
  {
    'id': 'agent-dashboard',
    'title': 'Dashboard',
    'display_title': 'AI Agent Dashboard',
    'category': 'AI Agent',
    'available': true,
  },
  {
    'id': 'social-dashboard',
    'title': 'Dashboard',
    'display_title': 'Social media agents Dashboard',
    'category': 'Social media agents',
    'available': true,
  },
];
const boundaryKey = ValueKey('favorites-screenshot');
String get favoritesKey =>
    'explore_layout:${Uri.parse(BrandConfig.serverUrl).authority}:17:favorites';

Future<void> mountFavorites(
  WidgetTester tester, {
  double scale = 1,
  List<Map<String, dynamic>> modules = favoritesTools,
}) async {
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: WorkspaceScreen(
            modules: modules,
            user: const {'id': 17},
            refresh: () async {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['FAVORITES_FONT_DIR'];
    if (fonts != null) {
      await (FontLoader('Roboto')..addFont(
            Future.value(
              ByteData.sublistView(
                await File('$fonts/Roboto-Regular.ttf').readAsBytes(),
              ),
            ),
          ))
          .load();
      await (FontLoader('MaterialIcons')..addFont(
            Future.value(
              ByteData.sublistView(
                await File('$fonts/MaterialIcons-Regular.otf').readAsBytes(),
              ),
            ),
          ))
          .load();
    }
  });
  setUp(
    () => SharedPreferences.setMockInitialValues({
      favoritesKey: ['agent-dashboard', 'social-dashboard'],
    }),
  );

  testWidgets('favorites evidence screenshot', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountFavorites(tester);
    final directory = Platform.environment['FAVORITES_SCREENSHOT_DIR'];
    if (directory != null) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/${Platform.environment['FAVORITES_SCREENSHOT_NAME'] ?? 'after'}.png',
        ).writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(tester.takeException(), isNull);
  });
  test('display names match section names and migrate legacy favorites without confusing IDs', () {
    expect(toolDisplayName(favoritesTools.first), 'AI Agent Dashboard');
    expect(
      toolDisplayName({'title': 'AI Agent Dashboard', 'category': 'AI Agent'}),
      'AI Agent Dashboard',
    );
    expect(
      migrateToolFavorites([
        'Social media agents Dashboard',
        'AI Agent Dashboard',
        'agent-dashboard',
      ], favoritesTools),
      ['social-dashboard', 'agent-dashboard'],
    );
    expect(migrateToolFavorites(['Dashboard'], favoritesTools), ['Dashboard']);
  });

  testWidgets(
    'pinning both dashboard tools displays full names, captions and accessible labels',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      await mountFavorites(tester);
      await tester.tap(
        find.byKey(const ValueKey('favorite-agent-dashboard-false')),
      );
      await tester.pumpAndSettle();
      final section = find.byKey(
        const ValueKey('workspace-section-Social media agents'),
      );
      await tester.ensureVisible(section);
      await tester.tap(section);
      await tester.pumpAndSettle();
      final star = find.byKey(
        const ValueKey('favorite-social-dashboard-false'),
      );
      await tester.ensureVisible(star);
      await tester.tap(star);
      await tester.pumpAndSettle();
      for (final tool in favoritesTools) {
        final card = find.byKey(ValueKey('favorite-card-${tool['id']}'));
        expect(
          find.descendant(
            of: card,
            matching: find.text(tool['display_title'] as String),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: card,
            matching: find.text(tool['category'] as String),
          ),
          findsOneWidget,
        );
        expect(
          find.byTooltip('${tool['display_title']}, ${tool['category']}'),
          findsWidgets,
        );
        expect(
          find.bySemanticsLabel(
            '${tool['display_title']}, ${tool['category']}',
          ),
          findsOneWidget,
        );
        expect(tester.getSize(card).width, 118);
      }
      expect(find.text('Dashboard'), findsNothing);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(favoritesKey), [
        'agent-dashboard',
        'social-dashboard',
      ]);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'favorites fit a 360dp screen at 160 percent text and grow vertically',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountFavorites(tester);
      final card = find.byKey(const ValueKey('favorite-card-agent-dashboard'));
      final height = tester.getSize(card).height;
      await mountFavorites(tester, scale: 1.6);
      expect(tester.getSize(card).width, 118);
      expect(tester.getSize(card).height, greaterThan(height));
      expect(find.text('AI Agent Dashboard'), findsWidgets);
      expect(find.text('Social media agents Dashboard'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'favorites survive restart in the same order and remain tied to IDs when names change',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        favoritesKey: ['Social media agents Dashboard', 'AI Agent Dashboard'],
      });
      await mountFavorites(tester);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(favoritesKey), [
        'social-dashboard',
        'agent-dashboard',
      ]);
      await tester.pumpWidget(const SizedBox());
      SharedPreferences.resetStatic();
      await mountFavorites(
        tester,
        modules: [
          for (final tool in favoritesTools)
            {...tool, 'display_title': 'Overview'},
        ],
      );
      final social = find.byKey(
        const ValueKey('favorite-card-social-dashboard'),
      );
      final agent = find.byKey(const ValueKey('favorite-card-agent-dashboard'));
      expect(
        tester.getTopLeft(social).dx,
        lessThan(tester.getTopLeft(agent).dx),
      );
      expect(
        find.descendant(of: social, matching: find.text('Social media agents')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: agent, matching: find.text('AI Agent')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: social, matching: find.text('Overview')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: agent, matching: find.text('Overview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
