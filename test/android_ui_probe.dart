import 'package:flutter/material.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/services/storage_service.dart';
import 'package:magicai_mobile/theme/app_colors.dart';
import 'package:magicai_mobile/theme/app_theme.dart';
import 'package:magicai_mobile/widgets/magic_bottom_navigation.dart';

const probeNavigation = <Map<String, dynamic>>[
  {'id': 'home', 'label': 'Home', 'component': 'dashboard'},
  {'id': 'explore', 'label': 'Explore', 'component': 'workspace'},
  {'id': 'chat', 'label': 'Chatbot', 'component': 'chat'},
  {'id': 'social', 'label': 'Calendar', 'component': 'social'},
  {'id': 'account', 'label': 'Account', 'component': 'account'},
];
const probeModules = <Map<String, dynamic>>[
  {
    'id': 'creative',
    'title': 'Creative Suite',
    'category': 'Creative studio',
    'description': 'Design ads, posts and assets',
    'available': true,
  },
  {
    'id': 'video',
    'title': 'Url To Video',
    'category': 'Creative studio',
    'description': 'Turn any link into a video',
    'available': true,
  },
  {
    'id': 'voice',
    'title': 'AI Realtime Voice Chat',
    'category': 'Audio & voice',
    'description': 'Talk to AI hands-free',
    'available': true,
  },
];

/// Release-only test target. Uses real widgets with a deterministic UI catalog;
/// it makes no claims about authenticated backend or generated AI content.
class AndroidUiProbe extends StatefulWidget {
  final ThemeMode initialMode;
  const AndroidUiProbe({super.key, this.initialMode = ThemeMode.dark});
  @override
  State<AndroidUiProbe> createState() => _AndroidUiProbeState();
}

class _AndroidUiProbeState extends State<AndroidUiProbe> {
  final _frame = GlobalKey();
  late ThemeMode _mode = widget.initialMode;
  int _selected = 1;

  @override
  void initState() {
    super.initState();
    _scheduleCheck();
  }

  void _scheduleCheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted && _selected == 1) await _checkFrame();
    });
  }

  void _select(int index) {
    setState(() => _selected = index);
    if (index == 1) _scheduleCheck();
    if (index == 2) debugPrint('UI_PROBE_CHATBOT_SELECTED');
  }

  Future<void> _checkFrame() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      final rendered = AppColors.of(_frame.currentContext!);
      final expected = _mode == ThemeMode.dark
          ? AppColors.dark
          : AppColors.light;
      if (rendered.page != expected.page ||
          rendered.surface != expected.surface) {
        _scheduleCheck();
        return;
      }
      var grids = 0;
      void inspect(Element element) {
        if (element.widget is SliverGrid) grids++;
        element.visitChildren(inspect);
      }

      (_frame.currentContext! as Element).visitChildren(inspect);
      debugPrint(
        'UI_PROBE_PASSED: theme=${_mode.name} layout=${grids > 0 ? 'grid' : 'list'}',
      );
    } catch (error) {
      debugPrint('UI_PROBE_FAILED: $error');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    themeAnimationDuration: Duration.zero,
    initialRoute: '/',
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: _mode,
    home: RepaintBoundary(
      key: _frame,
      child: Scaffold(
        appBar: _selected == 4 ? AppBar(title: const Text('Account')) : null,
        body: _selected == 4
            ? AccountHub(
                user: const {'id': 0, 'name': 'Preview Tester'},
                credits: const {},
                logout: () {},
                toggleTheme: () {
                  setState(
                    () => _mode = _mode == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark,
                  );
                  StorageService.setThemeMode(_mode.name);
                },
              )
            : _selected == 1
            ? WorkspaceScreen(
                modules: probeModules,
                user: const {'id': 0, 'name': 'Preview Tester'},
                openAccount: () => _select(4),
                refresh: () async {},
              )
            : const Center(child: Icon(Icons.smart_toy_outlined)),
        bottomNavigationBar: MagicBottomNavigation(
          items: probeNavigation,
          selectedIndex: _selected,
          onSelected: _select,
        ),
      ),
    ),
  );
}
