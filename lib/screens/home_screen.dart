import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/inbox_service.dart';
import '../services/app_localizations.dart';
import '../services/workspace_catalog.dart';
import '../widgets/language_picker.dart';
import '../services/ai_model_selection.dart';
import '../services/mobile_api.dart';
import 'auth/login_screen.dart';
import 'server_screen.dart';
import 'workspace_screen.dart';
import '../theme/brand_config.dart';
import '../widgets/magic_bottom_navigation.dart';
import 'inbox/inbox_screen.dart';

class HomeScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final MobileApi? api;
  const HomeScreen({super.key, required this.onThemeChanged, this.api});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _config;
  String? _error;
  String _selected = 'home';
  bool _loading = false;
  int _refreshVersion = 0;
  Timer? _timer, _inboxTimer;
  bool _foreground = true;
  final _sectionNavigator = GlobalKey<NavigatorState>();
  bool _nativeRouteVisible = false;
  late final _sectionObserver = _SectionObserver(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final visible = _sectionNavigator.currentState?.canPop() ?? false;
      if (visible != _nativeRouteVisible) {
        setState(() => _nativeRouteVisible = visible);
      }
    });
  });

  void _selectSection(String id) {
    _sectionNavigator.currentState?.popUntil((route) => route.isFirst);
    setState(() {
      _selected = id;
      _nativeRouteVisible = false;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _inboxTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_foreground && _config?['capabilities']?['unified_inbox'] == true) {
        _refreshInboxCount();
      }
    });
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
  }

  Future<void> _refreshInboxCount() async {
    try {
      final service = InboxService.forApi(widget.api ?? MobileApi.instance);
      if (!service.state.inboxVisible) await service.refreshCounts();
      unawaited(service.flush().catchError((_) {}));
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _inboxTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _load();
      if (_config?['capabilities']?['unified_inbox'] == true) {
        _refreshInboxCount();
      }
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _loading = true;
    final translations = AppLocalizations.current;
    if (identical(translations.api, widget.api ?? MobileApi.instance)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(translations.refresh());
      });
    }
    try {
      final data = await (widget.api ?? MobileApi.instance).request(
        '/config',
      ) as Map<String, dynamic>;
      if (data['app'] != 'magicai' ||
          data['schema_version'] != 1 ||
          data['navigation'] is! List) {
        throw const ApiFailure(
          'This app needs an update to display the server configuration.',
        );
      }
      AiModelSelection.configure(widget.api ?? MobileApi.instance, data);
      if (mounted) {
        setState(() {
          _config = data;
          ++_refreshVersion;
          _error = null;
        });
        if (data['capabilities']?['unified_inbox'] == true) {
          unawaited(_refreshInboxCount());
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      _loading = false;
    }
  }

  Future<void> _logout() async {
    try {
      await ApiService.logout();
    } catch (_) {}
    if (!mounted) return;
    InboxService.forApi(widget.api ?? MobileApi.instance).resetSession();
    MobileApi.failure.value = null;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return LoginScreen(onThemeChanged: widget.onThemeChanged);
        },
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_config == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : RetryPanel(message: appTr(_error!), retry: _load),
        ),
      );
    }
    final navigation = (_config!['navigation'] as List)
        .whereType<Map>()
        .where(
          (item) => [
            'dashboard',
            'tools',
            'chat',
            'social',
            'documents',
            'workspace',
            'account',
            'plans',
          ].contains(item['component']),
        )
        .toList();
    if (navigation.isEmpty) {
      return Scaffold(
        body: RetryPanel(
          message: appTr('No supported navigation is enabled.'),
          retry: _load,
        ),
      );
    }
    final inboxEnabled =
        (_config!['capabilities'] as Map?)?['unified_inbox'] == true &&
        (_config!['modules'] as List? ?? []).whereType<Map>().any(
          (module) =>
              module['available'] == true &&
              (module['route_type'] == 'marketing_inbox' ||
                  '${module['route']}'.contains('marketing-bot.inbox')),
        );
    if (inboxEnabled) {
      navigation.add({'id': 'inbox', 'component': 'inbox', 'label': 'Inbox'});
    }
    final allNavigation = List<Map>.from(navigation);
    navigation.removeWhere(
      (item) =>
          item['placement'] == 'secondary' ||
          (inboxEnabled && item['component'] == 'social'),
    );
    const primaryOrder = [
      'dashboard',
      'workspace',
      'chat',
      'inbox',
      'social',
      'account',
    ];
    navigation.sort((first, second) {
      final firstIndex = primaryOrder.indexOf(first['component']);
      final secondIndex = primaryOrder.indexOf(second['component']);
      return (firstIndex < 0 ? primaryOrder.length : firstIndex).compareTo(
        secondIndex < 0 ? primaryOrder.length : secondIndex,
      );
    });
    if (navigation.length > 5) navigation.removeRange(5, navigation.length);
    var index = navigation.indexWhere((item) => item['id'] == _selected);
    if (index < 0) index = 0;
    final selected = allNavigation.firstWhere(
      (item) => item['id'] == _selected,
      orElse: () => navigation[index],
    );
    final tools = (_config!['tools'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final modules = (_config!['modules'] as List? ?? [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final user = Map<String, dynamic>.from(_config!['user'] as Map? ?? {});
    final credits = Map<String, dynamic>.from(
      _config!['credits'] as Map? ?? {},
    );
    final visibleTools = selected['tool_ids'] is List
        ? tools
              .where(
                (tool) => (selected['tool_ids'] as List).contains(tool['id']),
              )
              .toList()
        : tools;
    final body = switch (selected['component']) {
      'inbox' => InboxScreen(api: widget.api),
      'dashboard' => StudioDashboard(
        api: widget.api,
        user: user,
        credits: credits,
        modules: modules,
        tools: tools,
        refresh: _load,
      ),
      'workspace' => WorkspaceScreen(
        modules: modules,
        refresh: _load,
        api: widget.api,
        user: user,
        openAccount: allNavigation.any((item) => item['id'] == 'account')
            ? () => _selectSection('account')
            : null,
      ),
      'account' => AccountHub(
        api: widget.api,
        refresh: _load,
        user: user,
        credits: credits,
        logout: _logout,
        toggleTheme: () => widget.onThemeChanged(
          Theme.of(context).brightness == Brightness.dark
              ? ThemeMode.light
              : ThemeMode.dark,
        ),
      ),
      'plans' => const PlansScreen(),
      'chat' => ServerChatScreen(
        api: widget.api,
        refreshVersion: _refreshVersion,
      ),
      'social' => ServerSocialScreen(
        api: widget.api,
        refreshVersion: _refreshVersion,
      ),
      'documents' => ServerListScreen(
        api: widget.api,
        path: '/documents',
        title: appTr('Documents'),
      ),
      _ => ToolDirectory(
        api: widget.api,
        tools: visibleTools,
        credits: credits,
        dashboard: selected['component'] == 'dashboard',
        refresh: _load,
      ),
    };
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar:
          _nativeRouteVisible ||
              selected['component'] == 'workspace' ||
              selected['component'] == 'inbox'
          ? null
          : AppBar(
              title: Text(
                appTr(
                  selected['component'] == 'dashboard'
                      ? BrandConfig.name
                      : selected['component'] == 'chat'
                      ? 'Chatbot'
                      : toolDisplayName(selected),
                ),
              ),
              centerTitle: false,
              actions: [
                const LanguagePicker(),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_horiz),
                  onSelected: _selectSection,
                  itemBuilder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return allNavigation
                        .map(
                          (item) => PopupMenuItem(
                            value: item['id'].toString(),
                            child: Text(
                              appTr(
                                item['component'] == 'chat'
                                    ? 'Chatbot'
                                    : toolDisplayName(item),
                              ),
                            ),
                          ),
                        )
                        .toList();
                  },
                ),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: appTr('Refresh'),
                ),
              ],
            ),
      body: Column(
        children: [
          if (_error != null)
            MaterialBanner(
              content: Text(appTr(_error!)),
              actions: [
                TextButton(onPressed: _load, child: Text(appTr('Retry'))),
              ],
            ),
          Expanded(
            child: NavigatorPopHandler(
              onPopWithResult: (result) =>
                  _sectionNavigator.currentState?.pop(result),
              child: Navigator(
                key: _sectionNavigator,
                observers: [_sectionObserver],
                pages: [
                  MaterialPage(key: ValueKey(selected['id']), child: body),
                ],
                onDidRemovePage: (_) {},
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: navigation.length < 2
          ? null
          : MagicBottomNavigation(
              items: navigation,
              inboxState: InboxService.forApi(widget.api ?? MobileApi.instance)
                  .state,
              selectedIndex: index,
              onSelected: (index) =>
                  _selectSection(navigation[index]['id'].toString()),
            ),
    );
  }
}

class _SectionObserver extends NavigatorObserver {
  final VoidCallback changed;
  _SectionObserver(this.changed);
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => changed();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      changed();
}
