import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/home_screen.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/theme/app_colors.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/theme/brand_config.dart';
import 'package:magicai_mobile/widgets/magic_bottom_navigation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'android_ui_probe.dart' show probeNavigation;
import 'explore_layout_test.dart' show tools;
import 'native_screen_test.dart' show nativeApi;

const _captureDirectory = String.fromEnvironment('MAGICAI_UI_CAPTURE');

void expectExploreColors(WidgetTester tester, AppColors colors) {
  final field = tester.widget<TextField>(find.byType(TextField));
  expect(field.decoration!.fillColor, colors.input);
  expect(field.style!.color, colors.text);
  expect(field.decoration!.hintStyle!.color, colors.inputHint);
  final searchBorder = field.decoration!.enabledBorder! as OutlineInputBorder;
  expect(searchBorder.borderSide.color, colors.outline);
  final control = tester.widget<Container>(
    find.byKey(const ValueKey('explore-layout-control')),
  );
  final decoration = control.decoration! as BoxDecoration;
  expect(decoration.color, colors.input);
  expect(decoration.borderRadius, searchBorder.borderRadius);
  expect(
    tester
        .getSize(find.byKey(const ValueKey('explore-search-container')))
        .height,
    tester.getSize(find.byKey(const ValueKey('explore-layout-control'))).height,
  );
  for (final key in ['explore-grid-toggle', 'explore-list-toggle']) {
    final button = tester.widget<IconButton>(find.byKey(ValueKey(key)));
    expect(
      button.style!.backgroundColor!.resolve({}),
      button.isSelected! ? colors.primary : Colors.transparent,
    );
    expect(
      button.style!.foregroundColor!.resolve({}),
      button.isSelected! ? colors.onPrimary : colors.muted,
    );
  }
  for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
    expect(chip.backgroundColor, colors.surface);
    expect(chip.selectedColor, colors.primary);
    expect(
      chip.labelStyle!.color,
      chip.selected ? colors.onPrimary : colors.text,
    );
    expect(chip.side!.color, chip.selected ? colors.primary : colors.outline);
  }
  final card = tester.widget<Card>(
    find.byKey(const ValueKey('explore-tool-creative')),
  );
  expect(card.color, colors.surface);
  expect((card.shape! as RoundedRectangleBorder).side.color, colors.outline);
  expect(
    tester.widget<Text>(find.text('Creative Suite')).style!.color,
    colors.text,
  );
  expect(tester.widget<Text>(find.text('2 tools')).style!.color, colors.muted);
  expect(find.byTooltip('Notifications'), findsNothing);
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  if (_captureDirectory.isEmpty) return;
  final render =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_captureDirectory).createSync(recursive: true);
    File('$_captureDirectory/$name.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    if (_captureDirectory.isEmpty) return;
    final fonts = {
      'Roboto': '../license-builder/app-builder/assets/magicai-preview/assets/fonts/fallback/Roboto-Regular.ttf',
      'MaterialIcons': '/tmp/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    };
    for (final entry in fonts.entries) {
      final file = File(entry.value);
      if (file.existsSync()) {
        await (FontLoader(entry.key)..addFont(
              Future.value(ByteData.sublistView(file.readAsBytesSync())),
            ))
            .load();
      }
    }
  });

  test('theme tokens match the requested dark and light surfaces', () {
    expect(AppColors.dark.page, const Color(0xFF131620));
    expect(AppColors.dark.surface, const Color(0xFF1E2230));
    expect(AppColors.dark.outline, const Color(0xFF2C3246));
    expect(AppColors.dark.text.toARGB32(), BrandConfig.text);
    expect(AppColors.dark.muted, const Color(0xFF818898));
    expect(AppColors.light.page, const Color(0xFFF8FAFC));
    expect(AppColors.light.surface, Colors.white);
    expect(AppColors.light.input, const Color(0xFFF1F5F9));
    expect(AppColors.light.outline, const Color(0xFFE2E8F0));
    expect(AppColors.light.text, const Color(0xFF0F172A));
    expect(AppColors.light.muted, const Color(0xFF64748B));
    for (final colors in [AppColors.dark, AppColors.light]) {
      expect(colors.primary, const Color(0xFF6366F1));
      expect(
        colors.text.computeLuminance() > colors.surface.computeLuminance(),
        colors == AppColors.dark,
      );
    }
    expect(AppColors.dark.lerp(AppColors.light, 0), same(AppColors.dark));
    expect(AppColors.dark.lerp(AppColors.light, 1), same(AppColors.light));
    final blended = AppColors.dark.lerp(AppColors.light, .5);
    expect(blended.onPrimary, same(Colors.white));
    expect(blended.chatbotForeground, same(Colors.white));
    expect(
      blended.surface,
      Color.lerp(AppColors.dark.surface, AppColors.light.surface, .5),
    );
    expect(
      AppColors.dark.copyWith(muted: AppColors.light.muted).muted,
      AppColors.light.muted,
    );
  });

  for (final list in [false, true]) {
    testWidgets(
      'Account appearance action repaints ${list ? 'list' : 'grid'} without losing saved preference',
      (tester) async {
        tester.view.physicalSize = const Size(430, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var mode = ThemeMode.dark;
        final boundary = GlobalKey();
        final api = nativeApi((path, _) async {
          expect(path, '/config');
          return {
            'app': 'magicai',
            'schema_version': 1,
            'navigation': probeNavigation,
            'modules': tools,
            'tools': [],
            'credits': {},
            'user': {'id': 7, 'name': 'Prakash'},
          };
        });
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, update) => RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                themeAnimationDuration: Duration.zero,
                theme: AppTheme.lightTheme,
                darkTheme: AppTheme.darkTheme,
                themeMode: mode,
                home: HomeScreen(
                  api: api,
                  onThemeChanged: (value) => update(() => mode = value),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).at(1));
        await tester.pumpAndSettle();
        if (list) {
          await tester.tap(find.byTooltip('List view'));
          await tester.pumpAndSettle();
        }
        expectExploreColors(tester, AppColors.dark);
        await capture(tester, boundary, 'dark-${list ? 'list' : 'grid'}');
        for (final colors in [AppColors.light, AppColors.dark]) {
          await tester.tap(find.byType(NavigationDestination).at(4));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Switch appearance'));
          await tester.tap(find.text('Switch appearance'));
          await tester.pumpAndSettle();
          expect(
            mode,
            colors == AppColors.light ? ThemeMode.light : ThemeMode.dark,
          );
          await tester.tap(find.byType(NavigationDestination).at(1));
          await tester.pumpAndSettle();
          expectExploreColors(tester, colors);
          expect(
            find.byType(SliverGrid),
            list ? findsNothing : findsNWidgets(2),
          );
          final nav = NavigationBarTheme.of(
            tester.element(find.byType(NavigationBar)),
          );
          expect(nav.iconTheme!.resolve({})!.color, colors.muted);
          expect(
            nav.labelTextStyle!.resolve({WidgetState.selected})!.color,
            colors.text,
          );
          await capture(
            tester,
            boundary,
            '${colors == AppColors.light ? 'light' : 'dark-restored'}-${list ? 'list' : 'grid'}',
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'theme changes repaint a mounted Explore and retain the current search',
    (tester) async {
      var light = false;
      late StateSetter updateTheme;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, update) {
            updateTheme = update;
            return MaterialApp(
              theme: light ? AppTheme.lightTheme : AppTheme.darkTheme,
              home: Scaffold(
                body: WorkspaceScreen(modules: tools, refresh: () async {}),
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Creative');
      await tester.tap(find.byTooltip('List view'));
      await tester.pumpAndSettle();
      final before = tester.state(find.byType(WorkspaceScreen));
      updateTheme(() => light = true);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(WorkspaceScreen)), same(before));
      expect(find.text('Creative'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.fillColor,
        AppColors.light.input,
      );
      expect(find.byType(SliverGrid), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 568), const Size(568, 320)]) {
    testWidgets(
      'floating Chatbot, cradle and accessible labels fit $size with safe-area and enlarged text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        tester.view.padding = const FakeViewPadding(bottom: 24);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPadding);
        final selected = <int>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: Scaffold(
              bottomNavigationBar: MagicBottomNavigation(
                items: probeNavigation,
                selectedIndex: 1,
                onSelected: selected.add,
              ),
            ),
          ),
        );
        final circle = tester.getRect(
          find.byKey(const ValueKey('chatbot-floating-action')),
        );
        final frame = tester.getRect(
          find.byKey(const ValueKey('navigation-cradle')),
        );
        expect(circle.center.dx, size.width / 2);
        final painter =
            tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('navigation-cradle')),
                    )
                    .painter!
                as NavigationCradlePainter;
        expect(circle.top, lessThan(frame.top + painter.barTop));
        final outline = painter.outlineForSize(frame.size);
        expect(
          outline.contains(Offset(frame.width / 2, painter.barTop + 2)),
          isFalse,
        );
        expect(outline.contains(Offset(4, painter.barTop + 2)), isTrue);
        expect(outline.contains(Offset(frame.width / 2, 84)), isTrue);
        expect(
          tester.getRect(find.text('Chatbot')).top,
          greaterThan(circle.bottom),
        );
        await tester.tapAt(Offset(circle.center.dx, circle.top + 12));
        expect(selected, [2]);
        final semantics = tester.ensureSemantics();
        try {
          final root = tester
              .getSemantics(find.byType(NavigationBar))
              .toStringDeep();
          expect(RegExp('Chatbot').allMatches(root).length, 1);
        } finally {
          semantics.dispose();
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'floating control follows Chatbot position in RTL and omitted entitlements remain omitted',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              bottomNavigationBar: MagicBottomNavigation(
                items: probeNavigation.take(4).toList(),
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      final circle = tester.getRect(
        find.byKey(const ValueKey('chatbot-floating-action')),
      );
      final frame = tester.getRect(find.byType(MagicBottomNavigation));
      expect(circle.center.dx, closeTo(frame.left + frame.width * .375, .1));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: MagicBottomNavigation(
              items: [probeNavigation[0], probeNavigation[4]],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      expect(
        find.byKey(const ValueKey('chatbot-floating-action')),
        findsNothing,
      );
      expect(find.byType(NavigationDestination), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
