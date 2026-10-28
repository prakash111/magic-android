import '../services/app_localizations.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/mobile_api.dart';
import '../services/workspace_catalog.dart';
import '../services/workspace_service.dart';
import '../theme/brand_config.dart';
import '../theme/app_colors.dart';
import '../theme/design.dart';
import 'server_screen.dart';
import 'native_module_screen.dart';
import 'native_settings_screen.dart';

IconData workspaceIcon(String value) {
  final key = value.toLowerCase();
  if (key.contains('automation') || key.contains('marketing')) {
    return Icons.bolt_rounded;
  }
  if (key.contains('calendar') || key.contains('schedule')) {
    return Icons.calendar_month_rounded;
  }
  if (key.contains('account') || key.contains('platform')) {
    return Icons.hub_rounded;
  }
  if (key.contains('image') ||
      key.contains('photo') ||
      key.contains('creative')) {
    return Icons.auto_awesome_rounded;
  }
  if (key.contains('video') || key.contains('clip')) {
    return Icons.movie_creation_outlined;
  }
  if (key.contains('voice') || key.contains('audio') || key.contains('music')) {
    return Icons.graphic_eq_rounded;
  }
  if (key.contains('chat') || key.contains('agent')) {
    return Icons.forum_outlined;
  }
  return Icons.dashboard_customize_outlined;
}

Future<void> openModule(
  BuildContext context,
  Map<String, dynamic> module, {
  MobileApi? api,
}) async {
  if (module['available'] != true) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return const PlansScreen();
        },
      ),
    );
    return;
  }
  try {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return NativeModuleScreen(module: module, api: api);
        },
      ),
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(appTr(error.toString()))));
    }
  }
}

class WorkspaceScreen extends StatefulWidget {
  final List<Map<String, dynamic>> modules;
  final Future<void> Function() refresh;
  final MobileApi? api;
  final Map<String, dynamic> user;
  final VoidCallback? openAccount;
  const WorkspaceScreen({
    super.key,
    required this.modules,
    required this.refresh,
    this.api,
    this.user = const {},
    this.openAccount,
  });
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  String _query = '', _category = 'All';
  bool _grid = true, _layoutChanged = false;
  final _searchFocus = FocusNode();
  Future<void> _saveLayout = Future.value();

  String get _preferenceKey =>
      'explore_layout:${widget.api?.origin.authority ?? Uri.parse(BrandConfig.serverUrl).authority}:${widget.user['id'] ?? 'default'}';

  @override
  void initState() {
    super.initState();
    _restoreLayout();
  }

  Future<void> _restoreLayout() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 2),
      );
      if (mounted && !_layoutChanged) {
        setState(() => _grid = prefs.getString(_preferenceKey) != 'list');
      }
    } catch (_) {
      // An unavailable preference store must never block Explore.
    }
  }

  void _setLayout(bool grid) {
    _layoutChanged = true;
    setState(() => _grid = grid);
    final key = _preferenceKey;
    _saveLayout = _saveLayout.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          const Duration(seconds: 2),
        );
        await prefs
            .setString(key, grid ? 'grid' : 'list')
            .timeout(const Duration(seconds: 2));
      } catch (_) {
        // Layout changes remain usable if device storage is unavailable.
      }
    });
  }

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  Widget _headerButton(IconData icon, String tooltip, VoidCallback onPressed) {
    final colors = AppColors.of(context);
    return IconButton.filledTonal(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      style: IconButton.styleFrom(
        backgroundColor: colors.surface,
        foregroundColor: colors.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.outline),
        ),
      ),
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }

  Widget _layoutButton(bool grid) {
    final colors = AppColors.of(context);
    final selected = grid == _grid;
    return IconButton(
      key: ValueKey(grid ? 'explore-grid-toggle' : 'explore-list-toggle'),
      tooltip: appTr(grid ? 'Grid view' : 'List view'),
      isSelected: selected,
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        backgroundColor: selected ? colors.primary : Colors.transparent,
        foregroundColor: selected ? colors.onPrimary : colors.muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: () => _setLayout(grid),
      icon: Icon(grid ? Icons.grid_view_rounded : Icons.view_list_outlined),
    );
  }

  Widget _toolCard(Map<String, dynamic> module, {required bool grid}) {
    final colors = AppColors.of(context);
    final locked = module['available'] != true;
    final icon = IconChip(
      icon: workspaceIcon('${module['id']} ${module['title']}'),
      color: colors.toolAccent('${module['id']}'),
    );
    final title = Text(
      appTr(workspaceTitle(module)),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: colors.text,
        fontWeight: FontWeight.w700,
        fontSize: 14.5,
        height: 1.2,
      ),
    );
    final subtitle = Text(
      appTr(locked ? 'Upgrade to unlock' : '${module['description'] ?? ''}'),
      maxLines: grid ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: colors.muted, fontSize: 12, height: 1.3),
    );
    return Card(
      key: ValueKey('explore-tool-${module['id']}'),
      margin: EdgeInsets.zero,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openModule(context, module, api: widget.api),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: grid
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        icon,
                        const Spacer(),
                        if (locked)
                          Icon(
                            Icons.lock_outline,
                            size: 18,
                            color: colors.muted,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    title,
                    const SizedBox(height: 4),
                    subtitle,
                  ],
                )
              : Row(
                  children: [
                    icon,
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 4), subtitle],
                      ),
                    ),
                    if (locked)
                      Icon(Icons.lock_outline, size: 18, color: colors.muted),
                    Icon(Icons.chevron_right, color: colors.muted),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final colors = AppColors.of(context);
    final categories = [
      'All',
      ...widget.modules.map(workspaceCategory).toSet(),
    ];
    final selectedCategory = categories.contains(_category) ? _category : 'All';
    final sections = groupedWorkspaces(
      widget.modules,
      category: selectedCategory,
      query: _query,
    );
    final name = '${widget.user['name'] ?? ''}'.trim();
    final initial = name.isEmpty ? 'M' : name.characters.first.toUpperCase();
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final searchHeight = math.max(56.0, 32 + 18 * scale);
    final searchBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colors.outline),
    );
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: colors.primary,
        backgroundColor: colors.surface,
        onRefresh: widget.refresh,
        child: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Semantics(
                          label: appTr('Open account'),
                          button: widget.openAccount != null,
                          child: InkWell(
                            onTap: widget.openAccount,
                            customBorder: const CircleBorder(),
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor: colors.primary,
                              foregroundColor: colors.onPrimary,
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            appTr('Explore'),
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colors.text,
                                ),
                          ),
                        ),
                        _headerButton(
                          Icons.search_rounded,
                          'Search tools',
                          _searchFocus.requestFocus,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            key: const ValueKey('explore-search-container'),
                            height: searchHeight,
                            child: TextField(
                              focusNode: _searchFocus,
                              textAlignVertical: TextAlignVertical.center,
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 14,
                              ),
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              decoration: InputDecoration(
                                hintText: appTr('Search tools...'),
                                hintStyle: TextStyle(
                                  color: colors.inputHint,
                                  fontSize: 14,
                                ),
                                prefixIcon: Icon(
                                  Icons.search,
                                  color: colors.muted,
                                ),
                                filled: true,
                                fillColor: colors.input,
                                border: searchBorder,
                                enabledBorder: searchBorder,
                                focusedBorder: searchBorder.copyWith(
                                  borderSide: BorderSide(
                                    color: colors.primary,
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 16,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          key: const ValueKey('explore-layout-control'),
                          height: searchHeight,
                          decoration: BoxDecoration(
                            color: colors.input,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.outline),
                          ),
                          padding: const EdgeInsets.all(3),
                          child: Row(
                            children: [
                              _layoutButton(false),
                              _layoutButton(true),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48 * scale,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: categories.length,
                        separatorBuilder: (localizationContext, index) {
                          AppLocalizations.watch(localizationContext);
                          return const SizedBox(width: 8);
                        },
                        itemBuilder: (localizationContext, index) {
                          AppLocalizations.watch(localizationContext);
                          return ChoiceChip(
                            label: Text(appTr(categories[index])),
                            selected: selectedCategory == categories[index],
                            selectedColor: colors.primary,
                            backgroundColor: colors.surface,
                            side: BorderSide(
                              color: selectedCategory == categories[index]
                                  ? colors.primary
                                  : colors.outline,
                            ),
                            shape: const StadiumBorder(),
                            labelStyle: TextStyle(
                              color: selectedCategory == categories[index]
                                  ? colors.onPrimary
                                  : colors.text,
                            ),
                            showCheckmark: false,
                            onSelected: (_) =>
                                setState(() => _category = categories[index]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (sections.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    appTr('No workspaces match your search.'),
                    style: TextStyle(color: colors.muted),
                  ),
                ),
              ),
            for (final section in sections.entries) ...[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 22, bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(
                              appTr(section.key),
                              key: ValueKey('workspace-section-${section.key}'),
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: colors.text,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          appTr(
                            ':length tool|:length tools',
                            {'length': section.value.length},
                            section.value.length,
                          ),
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: _grid
                    ? SliverLayoutBuilder(
                        builder: (context, constraints) {
                          AppLocalizations.watch(context);
                          final width = (constraints.crossAxisExtent - 10) / 2;
                          return SliverGrid.builder(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 10,
                                  mainAxisSpacing: 10,
                                  mainAxisExtent: math.max(
                                    width / 1.1,
                                    84 + 68 * scale,
                                  ),
                                ),
                            itemCount: section.value.length,
                            itemBuilder: (localizationContext, index) {
                              AppLocalizations.watch(localizationContext);
                              return _toolCard(
                                section.value[index],
                                grid: true,
                              );
                            },
                          );
                        },
                      )
                    : SliverList.separated(
                        itemCount: section.value.length,
                        separatorBuilder: (localizationContext, index) {
                          AppLocalizations.watch(localizationContext);
                          return const SizedBox(height: 10);
                        },
                        itemBuilder: (localizationContext, index) {
                          AppLocalizations.watch(localizationContext);
                          return _toolCard(section.value[index], grid: false);
                        },
                      ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class StudioDashboard extends StatelessWidget {
  final MobileApi? api;
  final Map<String, dynamic> user, credits;
  final List<Map<String, dynamic>> modules, tools;
  final Future<void> Function() refresh;
  const StudioDashboard({
    super.key,
    this.api,
    required this.user,
    required this.credits,
    required this.modules,
    required this.tools,
    required this.refresh,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Widget _stat(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
      ),
      Text(
        appTr(label),
        style: const TextStyle(color: Colors.white70, fontSize: 12.5),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final name = (user['name']?.toString() ?? '').split(' ').first;
    final suggestions =
        [
              ...modules.where(
                (m) =>
                    '${m['id']}'.contains('social') && m['available'] == true,
              ),
              ...modules.where((m) => m['available'] == true),
            ]
            .fold<List<Map<String, dynamic>>>([], (list, item) {
              if (!list.any((m) => m['id'] == item['id'])) list.add(item);
              return list;
            })
            .take(6)
            .toList();
    final tileWidth = (MediaQuery.sizeOf(context).width - 50) / 2;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          if (name.isNotEmpty)
            Text(
              '${appTr(_greeting())}, $name',
              style: TextStyle(color: mutedText(context), fontSize: 14),
            ),
          const SizedBox(height: 2),
          Text(
            appTr(
              name.isEmpty
                  ? 'Your next big idea starts here.'
                  : 'What will you\ncreate today?',
            ),
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w700, height: 1.15),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: kBrandGradient,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.30),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          appTr(":value workspace", {
                            "value": credits['plan'] ?? 'Free',
                          }),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.auto_awesome, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 18),
                if (credits['shared'] != null)
                  _stat(compactNumber(credits['shared']), 'shared credits left')
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stat(
                        compactNumber(credits['words'] ?? '—'),
                        'words left',
                      ),
                      const SizedBox(width: 28),
                      _stat(
                        compactNumber(credits['images'] ?? '—'),
                        'images left',
                      ),
                    ],
                  ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: const Color(0xFF4F46E5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (localizationContext) {
                          AppLocalizations.watch(localizationContext);
                          return const PlansScreen();
                        },
                      ),
                    ),
                    child: Text(appTr('Explore plans')),
                  ),
                ),
              ],
            ),
          ),
          SectionHeader(
            title: appTr('Create something new'),
            action: appTr('All tools'),
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (localizationContext) {
                  AppLocalizations.watch(localizationContext);
                  return Scaffold(
                    appBar: AppBar(title: Text(appTr('All tools'))),
                    body: ToolDirectory(
                      api: api,
                      tools: tools,
                      credits: credits,
                      dashboard: false,
                      refresh: refresh,
                    ),
                  );
                },
              ),
            ),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final tool in tools.take(4))
                SizedBox(
                  width: tileWidth,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (localizationContext) {
                            AppLocalizations.watch(localizationContext);
                            return DynamicToolScreen(tool: tool, api: api);
                          },
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            IconChip(
                              icon: workspaceIcon(
                                '${tool['kind']} ${tool['title']}',
                              ),
                              color: accentFor('${tool['title']}'),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                appTr(tool['title'].toString()),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SectionHeader(title: appTr('Your creative toolkit')),
          for (final module in suggestions)
            ToolRow(
              icon: workspaceIcon('${module['id']}'),
              color: accentFor('${module['id']}'),
              title: appTr(module['title'].toString()),
              subtitle: module['category'].toString(),
              onTap: () => openModule(context, module),
            ),
          if (suggestions.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                appTr('Open Explore to discover your available workspaces.'),
              ),
            ),
        ],
      ),
    );
  }
}

class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  String? _error;
  int? _busy;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final data =
          await MobileApi.instance.request('/plans') as Map<String, dynamic>;
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _buy(Map plan) async {
    final gateways = (_data?['gateways'] as List? ?? [])
        .whereType<Map>()
        .toList();
    if (gateways.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appTr(
              'Payment methods are temporarily unavailable. Please try again later.',
            ),
          ),
        ),
      );
      return;
    }
    final gateway = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        AppLocalizations.watch(context);
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                appTr('Choose a payment method'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              for (final item in gateways)
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text((item['title'] ?? item['code']).toString()),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pop(context, item['code'].toString()),
                ),
            ],
          ),
        );
      },
    );
    if (gateway == null) return;
    setState(() => _busy = int.parse(plan['id'].toString()));
    try {
      final data = await MobileApi.instance.request(
        '/checkout',
        method: 'POST',
        body: {'plan_id': plan['id'], 'gateway': gateway},
      ) as Map<String, dynamic>;
      await WorkspaceService().openTicket(
        data,
        title: 'Secure checkout',
        browser: true,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      appBar: AppBar(title: Text(appTr('Plans & credits'))),
      body: _data == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : RetryPanel(message: appTr(_error!), retry: _load),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    appTr('More room to create.'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appTr(
                      'Choose a subscription or top up your credits. Your balance updates after payment is confirmed.',
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Text(
                      appTr(_error!),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  if ((_data!['data'] as List).isEmpty)
                    Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        appTr(
                          'No plans are available right now. Pull down to check again.',
                        ),
                      ),
                    ),
                  for (final plan in (_data!['data'] as List).whereType<Map>())
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              plan['name'].toString(),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${plan['currency'] ?? 'USD'} ${plan['price']}',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              appTr(
                                plan['type'] == 'prepaid'
                                    ? 'One-time credit pack'
                                    : plan['frequency'].toString(),
                              ),
                            ),
                            if ((plan['description']?.toString() ?? '')
                                .isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                child: Text(
                                  appTr(
                                    plan['description'].toString().replaceAll(
                                      RegExp(r'<[^>]*>'),
                                      '',
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _busy != null
                                    ? null
                                    : () => _buy(plan),
                                child: Text(
                                  appTr(
                                    _busy == plan['id']
                                        ? 'Opening checkout…'
                                        : 'Continue to checkout',
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  TextButton(
                    onPressed: () async {
                      try {
                        await WorkspaceService().open(
                          destination: 'subscription',
                          title: 'Manage billing',
                          browser: true,
                        );
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(appTr(error.toString()))),
                          );
                        }
                      }
                    },
                    child: Text(appTr('Manage existing subscription')),
                  ),
                ],
              ),
            ),
    );
  }
}

class SocialAccountsScreen extends StatefulWidget {
  final MobileApi? api;
  final bool embedded;
  const SocialAccountsScreen({super.key, this.api, this.embedded = false});
  @override
  State<SocialAccountsScreen> createState() => _SocialAccountsScreenState();
}

class _SocialAccountsScreenState extends State<SocialAccountsScreen>
    with WidgetsBindingObserver {
  List<Map>? _accounts;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final items = await (widget.api ?? MobileApi.instance).request(
        '/social-media/platforms',
      ) as List;
      if (mounted) {
        setState(() {
          _accounts = items.whereType<Map>().toList();
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _connect(String platform, {String? account}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await WorkspaceService(api: widget.api).open(
        destination: 'social_connect',
        platform: platform,
        accountId: account,
        title: 'Connect account',
        browser: true,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(appTr('Connected accounts'))),
      body: _accounts == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : RetryPanel(message: appTr(_error!), retry: _load),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(
                    appTr('One place. Every account.'),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appTr(
                      'Connect multiple profiles and choose the right audience for every post.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) Text(appTr(_error!)),
                  for (final account in _accounts!)
                    Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          child: Icon(
                            account['isConnected'] == true
                                ? Icons.check
                                : Icons.link,
                          ),
                        ),
                        title: Text('${account['displayName']}'),
                        subtitle: Text(
                          appTr(
                            account['isConnected'] == true
                                ? '${account['handle']} · ${account['followers']} followers'
                                : (int.tryParse(account['id'].toString()) !=
                                          null
                                      ? 'Reconnect ${account['handle']}'
                                      : 'Connect your first profile'),
                          ),
                        ),
                        trailing: account['isConnected'] != true
                            ? IconButton(
                                icon: const Icon(Icons.add_link),
                                onPressed: _busy
                                    ? null
                                    : () => _connect(
                                        account['platform'].toString(),
                                        account:
                                            int.tryParse(
                                                  account['id'].toString(),
                                                ) !=
                                                null
                                            ? account['id'].toString()
                                            : null,
                                      ),
                              )
                            : PopupMenuButton<String>(
                                onSelected: (value) async {
                                  if (value == 'add') {
                                    await _connect(
                                      account['platform'].toString(),
                                    );
                                    return;
                                  }
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) {
                                      AppLocalizations.watch(context);
                                      return AlertDialog(
                                        title: Text(
                                          appTr('Disconnect this account?'),
                                        ),
                                        content: Text(
                                          appTr(
                                            'You can reconnect it any time. Scheduled posts using this account may need updating.',
                                          ),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: Text(appTr('Keep account')),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: Text(appTr('Disconnect')),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  if (confirm != true) return;
                                  try {
                                    await (widget.api ?? MobileApi.instance)
                                        .request(
                                          '/social-media/platforms/${account['id']}',
                                          method: 'DELETE',
                                        );
                                    await _load();
                                  } catch (error) {
                                    if (mounted) {
                                      setState(() => _error = error.toString());
                                    }
                                  }
                                },
                                itemBuilder: (localizationContext) {
                                  AppLocalizations.watch(localizationContext);
                                  return [
                                    PopupMenuItem(
                                      value: 'add',
                                      child: Text(appTr('Add another account')),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Text(appTr('Disconnect')),
                                    ),
                                  ];
                                },
                              ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class AccountHub extends StatelessWidget {
  final MobileApi? api;
  final Map<String, dynamic> user, credits;
  final VoidCallback logout, toggleTheme;
  final Future<void> Function()? refresh;
  const AccountHub({
    super.key,
    this.api,
    required this.user,
    required this.credits,
    required this.logout,
    required this.toggleTheme,
    this.refresh,
  });
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return RefreshIndicator(
      onRefresh: refresh ?? () async {},
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 8),
          CircleAvatar(
            radius: 38,
            child: Text(
              (user['name']?.toString().isNotEmpty ?? false)
                  ? user['name'].toString()[0].toUpperCase()
                  : 'M',
              style: const TextStyle(fontSize: 30),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            user['name']?.toString() ?? BrandConfig.name,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text(user['email']?.toString() ?? '', textAlign: TextAlign.center),
          const SizedBox(height: 26),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: Text(
                appTr(":value plan", {"value": credits['plan'] ?? 'Free'}),
              ),
              subtitle: Text(appTr('Subscription, payments & credit packs')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return const PlansScreen();
                  },
                ),
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text(appTr('Connected accounts')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (localizationContext) {
                        AppLocalizations.watch(localizationContext);
                        return const SocialAccountsScreen();
                      },
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(appTr('My documents')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (localizationContext) {
                        AppLocalizations.watch(localizationContext);
                        return Scaffold(
                          appBar: AppBar(title: Text(appTr('Documents'))),
                          body: ServerListScreen(
                            api: api,
                            path: '/documents',
                            title: appTr('Documents'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.manage_accounts_outlined),
                  title: Text(appTr('Profile & security')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (localizationContext) {
                        AppLocalizations.watch(localizationContext);
                        return Scaffold(
                          resizeToAvoidBottomInset: true,
                          appBar: AppBar(
                            title: Text(appTr('Account settings')),
                          ),
                          body: NativeSettingsScreen(api: MobileApi.instance),
                        );
                      },
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.brightness_6_outlined),
                  title: Text(appTr('Switch appearance')),
                  onTap: toggleTheme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: logout,
            icon: const Icon(Icons.logout),
            label: Text(appTr('Sign out')),
          ),
        ],
      ),
    );
  }
}
