import 'dart:async';
import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/mobile_api.dart';
import '../services/native_workspace_service.dart';
import 'server_screen.dart';

class NativePhoneAgentScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const NativePhoneAgentScreen({
    super.key,
    required this.module,
    required this.api,
  });

  @override
  State<NativePhoneAgentScreen> createState() => _NativePhoneAgentScreenState();
}

class _NativePhoneAgentScreenState extends State<NativePhoneAgentScreen>
    with SingleTickerProviderStateMixin {
  late final _service = NativeWorkspaceService(
    widget.api,
    '${widget.module['id']}',
  );
  late TabController _tabController;

  Map<String, dynamic>? _workspace;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _voices = [];
  List<Map<String, dynamic>> _campaigns = [];
  List<Map<String, dynamic>> _eligibleAgents = [];

  String? _error;
  bool _loading = false;
  bool _busy = false;
  String _activeTab = 'agents'; // 'agents', 'history', 'outbound'
  String _historyStatus = 'all';
  String _historyDirection = 'all';
  String _outboundStatus = 'all';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabChange);

    final initialRoute = '${widget.module['route'] ?? ''}';
    if (initialRoute.contains('.history')) {
      _activeTab = 'history';
      _tabController.index = 1;
    } else if (initialRoute.contains('.outbound')) {
      _activeTab = 'outbound';
      _tabController.index = 2;
    }

    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (_tabController.indexIsChanging) return;
    final newTab = switch (_tabController.index) {
      0 => 'agents',
      1 => 'history',
      2 => 'outbound',
      _ => 'agents',
    };
    if (newTab != _activeTab) {
      setState(() {
        _activeTab = newTab;
        _searchController.clear();
      });
      _load();
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await _service.load(
        query: _searchController.text,
        viewType: _activeTab,
        status: _activeTab == 'history'
            ? _historyStatus
            : (_activeTab == 'outbound' ? _outboundStatus : 'all'),
        direction: _activeTab == 'history' ? _historyDirection : null,
      );

      if (!mounted) return;
      setState(() {
        _workspace = res;
        _records = (res['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _voices = (res['voices'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _campaigns = (res['campaigns'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _eligibleAgents = (res['eligible_agents'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _error = null;
        _loading = false;
      });

      if (res['auto_open'] == 'new_agent' && _records.isEmpty) {
        _openAgentEditor();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String val) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _load(silent: true));
  }

  Future<void> _toggleAgent(Map<String, dynamic> agent) async {
    final current = agent['active'] == true;
    setState(() => agent['active'] = !current);
    try {
      await _service.mutate(
        kind: 'phone_agent',
        operation: 'toggle_active',
        requestId: 'toggle-${agent['id']}-${DateTime.now().millisecondsSinceEpoch}',
        recordId: agent['id'] as int,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appTr(agent['active'] == true
                  ? 'Agent activated successfully.'
                  : 'Agent paused.'),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => agent['active'] = current);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appTr(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteAgent(Map<String, dynamic> agent) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appTr('Delete Phone Call Agent?')),
        content: Text(
          appTr('Are you sure you want to delete "${agent['title']}"? This action cannot be undone.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appTr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(appTr('Delete')),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await _service.mutate(
        kind: 'phone_agent',
        operation: 'delete',
        requestId: 'delete-agent-${agent['id']}',
        recordId: agent['id'] as int,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr('Agent deleted successfully.'))),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appTr(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openAgentEditor([Map<String, dynamic>? agent, int initialStep = 1]) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhoneAgentEditorSheet(
        service: _service,
        agent: agent,
        voices: _voices,
        initialStep: initialStep,
        onSaved: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  void _openSimulator(Map<String, dynamic> agent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PhoneSimulatorSheet(
        service: _service,
        agent: agent,
      ),
    );
  }

  void _openCallDetail(Map<String, dynamic> call) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CallDetailSheet(
        call: call,
        service: _service,
        onChanged: () {
          _load();
        },
      ),
    );
  }

  void _openPlaceCallDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlaceOutboundCallSheet(
        service: _service,
        eligibleAgents: _eligibleAgents.isNotEmpty
            ? _eligibleAgents
            : _records.where((a) => (a['phone_number'] ?? '').toString().isNotEmpty).toList(),
        onPlaced: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  void _openNewCampaignDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _NewCampaignSheet(
        service: _service,
        eligibleAgents: _eligibleAgents.isNotEmpty
            ? _eligibleAgents
            : _records.where((a) => (a['phone_number'] ?? '').toString().isNotEmpty).toList(),
        onCreated: () {
          Navigator.pop(ctx);
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_loading && _workspace == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _workspace == null) {
      return Center(
        child: RetryPanel(
          message: appTr(_error!),
          retry: () => _load(),
        ),
      );
    }

    final metrics = (_workspace?['metrics'] as List? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    return Column(
      children: [
        if (_loading || _busy) const LinearProgressIndicator(minHeight: 2),

        // Navigation Tabs matching web
        Container(
          color: Theme.of(context).cardColor,
          child: TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: [
              Tab(
                icon: const Icon(Icons.support_agent_outlined, size: 20),
                text: appTr('Agents'),
              ),
              Tab(
                icon: const Icon(Icons.history_outlined, size: 20),
                text: appTr('Call History'),
              ),
              Tab(
                icon: const Icon(Icons.phone_forwarded_outlined, size: 20),
                text: appTr('Outbound'),
              ),
            ],
          ),
        ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(silent: true),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              children: [
                // Metrics / Stat Summary row
                if (metrics.isNotEmpty) _buildMetricsRow(metrics),
                const SizedBox(height: 16),

                // Tab Content
                switch (_activeTab) {
                  'history' => _buildHistoryView(),
                  'outbound' => _buildOutboundView(),
                  _ => _buildAgentsView(),
                },
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsRow(List<Map<String, dynamic>> metrics) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: metrics.map((m) {
          final label = appTr('${m['label'] ?? ''}');
          final val = '${m['value'] ?? 0}';
          final icon = switch ('${m['icon'] ?? ''}') {
            'paid' => Icons.check_circle_outline,
            'calendar' => Icons.today_outlined,
            'balance' => Icons.phone_forwarded_outlined,
            _ => Icons.headset_mic_outlined,
          };
          return Container(
            width: 140,
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
                    Text(
                      val,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // -------------------------------------------------------------
  // VIEW 1: AGENTS TAB
  // -------------------------------------------------------------
  Widget _buildAgentsView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Banner matching web
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primaryContainer.withOpacity(0.6),
                Theme.of(context).colorScheme.tertiaryContainer.withOpacity(0.4),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appTr('Create AI agents that answer real phone calls and talk just like a human.'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openAgentEditor(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(appTr('Create New Agent')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _tabController.animateTo(1);
                    },
                    icon: const Icon(Icons.history, size: 18),
                    label: Text(appTr('Call History')),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      _tabController.animateTo(2);
                    },
                    icon: const Icon(Icons.phone_forwarded, size: 18),
                    label: Text(appTr('Outbound Calls')),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Search Bar
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: appTr('Search agents by title, number or prompt...'),
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 20),

        // Section Title
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              appTr('My Phone Call Agents'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              '${_records.length} ${appTr('agents')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Agents List / Empty State
        if (_records.isEmpty)
          _buildEmptyState(
            icon: Icons.phone_disabled_outlined,
            title: appTr('No agents yet'),
            subtitle: appTr('Create your first phone call agent to start answering real phone calls.'),
            actionLabel: appTr('Create Agent'),
            onAction: () => _openAgentEditor(),
          )
        else
          ..._records.map((agent) => _buildAgentCard(agent)),
      ],
    );
  }

  Widget _buildAgentCard(Map<String, dynamic> agent) {
    final title = '${agent['title'] ?? 'Agent'}';
    final isActive = agent['active'] == true;
    final phone = '${agent['phone_number'] ?? ''}';
    final provider = '${agent['provider'] ?? 'elevenlabs'}';
    final voiceName = '${agent['voice_name'] ?? agent['voice_id'] ?? 'Default Voice'}';
    final todayCalls = (agent['today_calls_count'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isActive
              ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
              : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Avatar, Title, Provider Chip, Menu
            Row(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.support_agent,
                        color: Theme.of(context).colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green : Colors.grey,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceVariant,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              provider.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            todayCalls > 0
                                ? '$todayCalls ${appTr('Calls Today')}'
                                : appTr('No Calls Today'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Options Dropdown
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (val) {
                    switch (val) {
                      case 'configure':
                        _openAgentEditor(agent, 1);
                        break;
                      case 'train':
                        _openAgentEditor(agent, 2);
                        break;
                      case 'phone':
                        _openAgentEditor(agent, 3);
                        break;
                      case 'simulate':
                        _openSimulator(agent);
                        break;
                      case 'delete':
                        _deleteAgent(agent);
                        break;
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'configure',
                      child: Row(
                        children: [
                          const Icon(Icons.settings_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(appTr('Configure')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'train',
                      child: Row(
                        children: [
                          const Icon(Icons.model_training, size: 18),
                          const SizedBox(width: 8),
                          Text(appTr('Train Knowledge')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'phone',
                      child: Row(
                        children: [
                          const Icon(Icons.phone_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text(appTr('Phone Numbers')),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'simulate',
                      child: Row(
                        children: [
                          const Icon(Icons.play_circle_outline, size: 18),
                          const SizedBox(width: 8),
                          Text(appTr('Test Simulator')),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: Theme.of(ctx).colorScheme.error),
                          const SizedBox(width: 8),
                          Text(
                            appTr('Delete'),
                            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Metadata Row: Phone & Voice
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    phone.isNotEmpty ? Icons.phone : Icons.phone_missed,
                    size: 14,
                    color: phone.isNotEmpty ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      phone.isNotEmpty ? phone : appTr('No phone number attached'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(Icons.record_voice_over, size: 14, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    voiceName,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Bottom Actions: Active Toggle, Test Call Button, Configure
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Switch.adaptive(
                      value: isActive,
                      onChanged: (val) => _toggleAgent(agent),
                    ),
                    Text(
                      appTr(isActive ? 'Active' : 'Inactive'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _openSimulator(agent),
                      icon: const Icon(Icons.call, size: 14),
                      label: Text(appTr('Test Call')),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _openAgentEditor(agent, 1),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: Text(appTr('Edit')),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // VIEW 2: CALL HISTORY TAB
  // -------------------------------------------------------------
  Widget _buildHistoryView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                '${appTr('Status')}: ',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              ...['all', 'completed', 'busy', 'no-answer', 'failed'].map((st) {
                final isSelected = _historyStatus == st;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(appTr(st == 'all' ? 'All' : st)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _historyStatus = st);
                      _load(silent: true);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
              const SizedBox(width: 8),
              Text(
                '${appTr('Direction')}: ',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              ...['all', 'inbound', 'outbound'].map((dir) {
                final isSelected = _historyDirection == dir;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(appTr(dir == 'all' ? 'All' : dir)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _historyDirection = dir);
                      _load(silent: true);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Search in history
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: appTr('Search calls by phone number...'),
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        const SizedBox(height: 16),

        if (_records.isEmpty)
          _buildEmptyState(
            icon: Icons.history_toggle_off,
            title: appTr('No call records'),
            subtitle: appTr('Calls answered or made by your agents will appear here with full transcripts.'),
          )
        else
          ..._records.map((call) => _buildCallCard(call)),
      ],
    );
  }

  Widget _buildCallCard(Map<String, dynamic> call) {
    final caller = '${call['caller_number'] ?? 'Unknown Caller'}';
    final called = '${call['called_number'] ?? ''}';
    final agentTitle = '${call['agent_title'] ?? 'Phone Agent'}';
    final direction = '${call['direction'] ?? 'inbound'}';
    final status = '${call['status'] ?? 'completed'}';
    final durationSec = (call['duration'] as num?)?.toInt() ?? 0;
    final durationStr = '${(durationSec ~/ 60).toString().padLeft(2, '0')}:${(durationSec % 60).toString().padLeft(2, '0')}';
    final startedAt = '${call['started_at'] ?? call['created_at'] ?? ''}';
    final isPinned = ((call['pinned'] as num?)?.toInt() ?? 0) > 0;

    final statusColor = switch (status) {
      'completed' => Colors.green,
      'busy' => Colors.amber,
      'failed' => Colors.red,
      _ => Theme.of(context).colorScheme.primary,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Theme.of(context).cardColor,
      child: InkWell(
        onTap: () => _openCallDetail(call),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: direction == 'outbound'
                    ? Colors.blue.withOpacity(0.15)
                    : Colors.green.withOpacity(0.15),
                child: Icon(
                  direction == 'outbound' ? Icons.call_made : Icons.call_received,
                  color: direction == 'outbound' ? Colors.blue : Colors.green,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$caller ${called.isNotEmpty ? '→ $called' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isPinned)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.push_pin, size: 14, color: Colors.amber),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      agentTitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (startedAt.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        startedAt.length > 16 ? startedAt.substring(0, 16).replaceAll('T', ' ') : startedAt,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.7),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      appTr(status).toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    durationStr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------
  // VIEW 3: OUTBOUND CALLS & CAMPAIGNS TAB
  // -------------------------------------------------------------
  Widget _buildOutboundView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Outbound Actions
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _openPlaceCallDialog(),
                icon: const Icon(Icons.phone_forwarded, size: 16),
                label: Text(appTr('Place a Call')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openNewCampaignDialog(),
                icon: const Icon(Icons.campaign_outlined, size: 16),
                label: Text(appTr('New Campaign')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Status Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Text(
                '${appTr('Status')}: ',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              ...['all', 'queued', 'in-progress', 'completed', 'failed'].map((st) {
                final isSelected = _outboundStatus == st;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(appTr(st == 'all' ? 'All' : st)),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _outboundStatus = st);
                      _load(silent: true);
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Campaigns Section
        if (_campaigns.isNotEmpty) ...[
          Text(
            appTr('Outbound Campaigns'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ..._campaigns.map((camp) => _buildCampaignCard(camp)),
          const SizedBox(height: 20),
        ],

        // Outbound Calls Section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              appTr('Outbound Calls'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              '${_records.length} ${appTr('calls')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (_records.isEmpty)
          _buildEmptyState(
            icon: Icons.phone_forwarded,
            title: appTr('No outbound calls yet'),
            subtitle: appTr('Place your first outbound call from one of your agents with an attached phone number.'),
            actionLabel: appTr('Place a Call'),
            onAction: () => _openPlaceCallDialog(),
          )
        else
          ..._records.map((call) => _buildCallCard(call)),
      ],
    );
  }

  Widget _buildCampaignCard(Map<String, dynamic> camp) {
    final name = '${camp['name'] ?? 'Campaign'}';
    final agentTitle = '${camp['agent_title'] ?? ''}';
    final total = (camp['total_recipients'] as num?)?.toInt() ?? 0;
    final completed = (camp['completed_count'] as num?)?.toInt() ?? 0;
    final status = '${camp['status'] ?? 'scheduled'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          if (agentTitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              agentTitle,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total > 0 ? (completed / total).clamp(0.0, 1.0) : 0,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completed / $total ${appTr('completed')}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            FilledButton.tonal(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }
}

// ============================================================================
// MODAL 1: PHONE AGENT CONFIGURE & TRAIN WIZARD SHEET
// ============================================================================
class _PhoneAgentEditorSheet extends StatefulWidget {
  final NativeWorkspaceService service;
  final Map<String, dynamic>? agent;
  final List<Map<String, dynamic>> voices;
  final int initialStep;
  final VoidCallback onSaved;

  const _PhoneAgentEditorSheet({
    required this.service,
    this.agent,
    required this.voices,
    this.initialStep = 1,
    required this.onSaved,
  });

  @override
  State<_PhoneAgentEditorSheet> createState() => _PhoneAgentEditorSheetState();
}

class _PhoneAgentEditorSheetState extends State<_PhoneAgentEditorSheet> {
  late int _step;
  bool _saving = false;

  // Step 1: Configure Fields
  late final TextEditingController _titleCtrl;
  late final TextEditingController _welcomeCtrl;
  late final TextEditingController _instructionsCtrl;
  late final TextEditingController _maxDurationCtrl;
  late final TextEditingController _silenceTimeoutCtrl;
  String _language = 'en';
  String _provider = 'elevenlabs';
  String _voiceId = '21m00Tcm4TlvDq8ikWAM';
  String _aiModel = 'gpt-4o-mini';
  bool _active = true;

  // Booking Fields
  bool _bookingEnabled = false;
  String _bookingProvider = 'cal_com';
  late final TextEditingController _bookingEventTypeCtrl;
  late final TextEditingController _bookingApiKeyCtrl;
  String _bookingTimezone = 'UTC';

  // Step 2: Training Data
  List<Map<String, dynamic>> _trainItems = [];
  bool _loadingTrain = false;
  final _trainUrlCtrl = TextEditingController();
  final _trainTextCtrl = TextEditingController();

  // Step 3: Phone Numbers
  String? _phoneNumber;
  final _importPhoneCtrl = TextEditingController();
  final _twilioSidCtrl = TextEditingController();
  final _twilioTokenCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
    final a = widget.agent ?? {};

    _titleCtrl = TextEditingController(text: a['title'] ?? 'Support Agent');
    _welcomeCtrl = TextEditingController(
      text: a['welcome_message'] ?? 'Hello, how can I help you today?',
    );
    _instructionsCtrl = TextEditingController(text: a['instructions'] ?? '');
    _maxDurationCtrl = TextEditingController(
      text: '${a['max_call_duration'] ?? 300}',
    );
    _silenceTimeoutCtrl = TextEditingController(
      text: '${a['silence_timeout'] ?? 30}',
    );
    _language = a['language'] ?? 'en';
    _provider = a['provider'] ?? 'elevenlabs';
    _voiceId = a['voice_id'] ?? (widget.voices.isNotEmpty ? '${widget.voices[0]['voice_id']}' : '21m00Tcm4TlvDq8ikWAM');
    _aiModel = a['ai_model'] ?? 'gpt-4o-mini';
    _active = a['active'] ?? true;

    _bookingEnabled = a['booking_enabled'] == true;
    _bookingProvider = a['booking_provider'] ?? 'cal_com';
    _bookingEventTypeCtrl = TextEditingController(text: a['booking_event_type_id'] ?? '');
    _bookingApiKeyCtrl = TextEditingController(text: a['booking_api_key'] ?? '');
    _bookingTimezone = a['booking_timezone'] ?? 'UTC';

    _phoneNumber = a['phone_number'];
    _loadTrainData();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _welcomeCtrl.dispose();
    _instructionsCtrl.dispose();
    _maxDurationCtrl.dispose();
    _silenceTimeoutCtrl.dispose();
    _bookingEventTypeCtrl.dispose();
    _bookingApiKeyCtrl.dispose();
    _trainUrlCtrl.dispose();
    _trainTextCtrl.dispose();
    _importPhoneCtrl.dispose();
    _twilioSidCtrl.dispose();
    _twilioTokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadTrainData() async {
    if (widget.agent == null) return;
    setState(() => _loadingTrain = true);
    try {
      final res = await widget.service.load(
        viewType: 'train',
        agentId: widget.agent!['id'] as int,
      );
      if (mounted) {
        setState(() {
          _trainItems = (res['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          _loadingTrain = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTrain = false);
    }
  }

  Future<void> _saveAgent() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr('Agent title is required.'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final inputs = {
        'title': title,
        'welcome_message': _welcomeCtrl.text.trim(),
        'instructions': _instructionsCtrl.text.trim(),
        'language': _language,
        'provider': _provider,
        'voice_id': _voiceId,
        'ai_model': _aiModel,
        'max_call_duration': int.tryParse(_maxDurationCtrl.text) ?? 300,
        'silence_timeout': int.tryParse(_silenceTimeoutCtrl.text) ?? 30,
        'active': _active,
        'booking_enabled': _bookingEnabled,
        'booking_provider': _bookingProvider,
        'booking_event_type_id': _bookingEventTypeCtrl.text.trim(),
        'booking_api_key': _bookingApiKeyCtrl.text.trim(),
        'booking_timezone': _bookingTimezone,
      };

      await widget.service.mutate(
        kind: 'phone_agent',
        operation: 'save',
        requestId: 'save-agent-${DateTime.now().millisecondsSinceEpoch}',
        recordId: widget.agent?['id'] as int?,
        inputs: inputs,
      );

      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appTr(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTrainItem(String type, String content) async {
    if (widget.agent == null) return;
    setState(() => _saving = true);
    try {
      await widget.service.mutate(
        kind: 'phone_agent',
        operation: 'train',
        requestId: 'train-${DateTime.now().millisecondsSinceEpoch}',
        inputs: {
          'agent_id': widget.agent!['id'],
          'type': type,
          'url': type == 'url' ? content : null,
          'text': type == 'text' ? content : null,
          'name': type == 'url' ? content : 'Text Knowledge',
        },
      );
      _loadTrainData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteTrainItem(int id) async {
    if (widget.agent == null) return;
    try {
      await widget.service.mutate(
        kind: 'phone_agent',
        operation: 'delete_train',
        requestId: 'del-train-$id',
        recordId: id,
        inputs: {'agent_id': widget.agent!['id']},
      );
      _loadTrainData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr(e.toString()))),
        );
      }
    }
  }

  Future<void> _attachPhoneNumber() async {
    if (widget.agent == null) return;
    final num = _importPhoneCtrl.text.trim();
    if (num.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.service.mutate(
        kind: 'phone_agent',
        operation: 'phone_number',
        requestId: 'phone-${DateTime.now().millisecondsSinceEpoch}',
        inputs: {
          'agent_id': widget.agent!['id'],
          'phone_number': num,
          'twilio_account_sid': _twilioSidCtrl.text.trim(),
          'twilio_auth_token': _twilioTokenCtrl.text.trim(),
        },
      );
      setState(() => _phoneNumber = num);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr('Phone number attached.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _releasePhoneNumber() async {
    if (widget.agent == null) return;
    setState(() => _saving = true);
    try {
      await widget.service.mutate(
        kind: 'phone_agent',
        operation: 'release',
        requestId: 'rel-phone-${DateTime.now().millisecondsSinceEpoch}',
        inputs: {'agent_id': widget.agent!['id']},
      );
      setState(() => _phoneNumber = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr('Phone number released.'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final isNew = widget.agent == null;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                Text(
                  isNew ? appTr('Create Phone Call Agent') : appTr('Edit Agent'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                FilledButton(
                  onPressed: _saving ? null : _saveAgent,
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(appTr('Save')),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 3 Step Navigation Pills (matching web wizard)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            child: Row(
              children: [
                _buildStepPill(1, appTr('1. Configure')),
                const SizedBox(width: 8),
                _buildStepPill(2, appTr('2. Train')),
                const SizedBox(width: 8),
                _buildStepPill(3, appTr('3. Phone Numbers')),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                switch (_step) {
                  2 => _buildTrainStep(),
                  3 => _buildPhoneNumbersStep(),
                  _ => _buildConfigureStep(),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill(int stepNumber, String title) {
    final isCurrent = _step == stepNumber;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _step = stepNumber),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isCurrent
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isCurrent
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // STEP 1: CONFIGURE
  Widget _buildConfigureStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleCtrl,
          decoration: InputDecoration(
            labelText: appTr('Agent Title *'),
            hintText: appTr('e.g. Sales Assistant'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _welcomeCtrl,
          decoration: InputDecoration(
            labelText: appTr('Welcome Message'),
            hintText: appTr('e.g. Hello, how can I help you today?'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: _instructionsCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: appTr('Agent Instructions (System Prompt)'),
            hintText: appTr('Describe agent role, tone, and what questions it can answer.'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // Language & AI Model Row
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _language,
                decoration: InputDecoration(
                  labelText: appTr('Language'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'en', child: Text(appTr('English (Auto)'))),
                  DropdownMenuItem(value: 'es', child: Text(appTr('Spanish'))),
                  DropdownMenuItem(value: 'fr', child: Text(appTr('French'))),
                  DropdownMenuItem(value: 'de', child: Text(appTr('German'))),
                  DropdownMenuItem(value: 'it', child: Text(appTr('Italian'))),
                  DropdownMenuItem(value: 'pt', child: Text(appTr('Portuguese'))),
                  DropdownMenuItem(value: 'hi', child: Text(appTr('Hindi'))),
                ],
                onChanged: (val) => setState(() => _language = val ?? 'en'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _aiModel,
                decoration: InputDecoration(
                  labelText: appTr('AI Model'),
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'gpt-4o-mini', child: Text('gpt-4o-mini')),
                  DropdownMenuItem(value: 'gpt-4o', child: Text('gpt-4o')),
                  DropdownMenuItem(value: 'claude-3-haiku', child: Text('claude-3-haiku')),
                ],
                onChanged: (val) => setState(() => _aiModel = val ?? 'gpt-4o-mini'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Voice Picker Field with Audio Preview
        Text(
          appTr('Voice Selection'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () => _openVoicePickerDialog(),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.withOpacity(0.4)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.record_voice_over, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _getVoiceName(_voiceId),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Call Duration & Silence Timeout
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _maxDurationCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: appTr('Max Duration (sec)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _silenceTimeoutCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: appTr('Silence Timeout (sec)'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Booking Integration Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        appTr('Booking Assistant'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Switch.adaptive(
                    value: _bookingEnabled,
                    onChanged: (val) => setState(() => _bookingEnabled = val),
                  ),
                ],
              ),
              if (_bookingEnabled) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  value: _bookingProvider,
                  decoration: InputDecoration(
                    labelText: appTr('Booking Provider'),
                    border: const OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cal_com', child: Text('Cal.com')),
                    DropdownMenuItem(value: 'calendly', child: Text('Calendly')),
                  ],
                  onChanged: (val) => setState(() => _bookingProvider = val ?? 'cal_com'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bookingEventTypeCtrl,
                  decoration: InputDecoration(
                    labelText: appTr('Event Type ID / URI'),
                    hintText: appTr('e.g. 12345 or URI'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bookingApiKeyCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: appTr('Booking Provider API Key'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        FilledButton(
          onPressed: () => setState(() => _step = 2),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
          ),
          child: Text(appTr('Next: Train Agent')),
        ),
      ],
    );
  }

  String _getVoiceName(String id) {
    for (final v in widget.voices) {
      if (v['voice_id'] == id) return '${v['name'] ?? id}';
    }
    return id;
  }

  void _openVoicePickerDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _VoicePickerSheet(
        voices: widget.voices,
        selectedVoiceId: _voiceId,
        onSelected: (id) {
          setState(() => _voiceId = id);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  // STEP 2: TRAIN
  Widget _buildTrainStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appTr('Agent Knowledge Base'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          appTr('Add websites or text content to give your agent specific company knowledge.'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),

        // Quick Add Actions
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openAddUrlDialog(),
                icon: const Icon(Icons.link, size: 16),
                label: Text(appTr('Add Website URL')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openAddTextDialog(),
                icon: const Icon(Icons.notes, size: 16),
                label: Text(appTr('Add Text')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (_loadingTrain)
          const Center(child: CircularProgressIndicator())
        else if (_trainItems.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Text(
              appTr('No training items yet. Add a website URL or text knowledge above.'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          )
        else
          ..._trainItems.map((item) {
            final id = item['id'] as int;
            final name = '${item['name'] ?? ''}';
            final type = '${item['type'] ?? 'url'}';
            final isTrained = item['trained_at'] != null;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.3),
              child: ListTile(
                dense: true,
                leading: Icon(
                  type == 'url' ? Icons.link : Icons.article_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  isTrained ? appTr('Trained & Embedded') : appTr('Pending training'),
                  style: TextStyle(
                    fontSize: 11,
                    color: isTrained ? Colors.green : Colors.amber,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () => _deleteTrainItem(id),
                ),
              ),
            );
          }),
        const SizedBox(height: 24),

        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _step = 1),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(appTr('Back')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => setState(() => _step = 3),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                child: Text(appTr('Next: Phone Numbers')),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _openAddUrlDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appTr('Add Website Knowledge')),
        content: TextField(
          controller: _trainUrlCtrl,
          decoration: InputDecoration(
            hintText: 'https://example.com/about',
            labelText: appTr('Website URL'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(appTr('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final url = _trainUrlCtrl.text.trim();
              if (url.isNotEmpty) {
                _addTrainItem('url', url);
                _trainUrlCtrl.clear();
              }
              Navigator.pop(ctx);
            },
            child: Text(appTr('Add URL')),
          ),
        ],
      ),
    );
  }

  void _openAddTextDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appTr('Add Text Knowledge')),
        content: TextField(
          controller: _trainTextCtrl,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: appTr('Type product features, return policy, FAQs...'),
            labelText: appTr('Knowledge Text'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(appTr('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final text = _trainTextCtrl.text.trim();
              if (text.isNotEmpty) {
                _addTrainItem('text', text);
                _trainTextCtrl.clear();
              }
              Navigator.pop(ctx);
            },
            child: Text(appTr('Add Text')),
          ),
        ],
      ),
    );
  }

  // STEP 3: PHONE NUMBERS
  Widget _buildPhoneNumbersStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appTr('Assigned Phone Number'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),

        if (_phoneNumber != null && _phoneNumber!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.phone_in_talk, color: Colors.green, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _phoneNumber!,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      Text(
                        appTr('Inbound calls to this number are handled by this agent.'),
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _saving ? null : _releasePhoneNumber,
                  icon: const Icon(Icons.link_off, size: 16, color: Colors.red),
                  label: Text(
                    appTr('Remove'),
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  appTr('Connect a Phone Number'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  appTr('Enter your Twilio or SIP phone number (in E.164 format, e.g. +14155552671).'),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _importPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: appTr('Phone Number (+1...)'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _twilioSidCtrl,
                  decoration: InputDecoration(
                    labelText: appTr('Twilio Account SID (optional)'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _twilioTokenCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: appTr('Twilio Auth Token (optional)'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saving ? null : _attachPhoneNumber,
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(appTr('Attach Phone Number')),
                ),
              ],
            ),
          ),
        const SizedBox(height: 24),

        OutlinedButton(
          onPressed: () => setState(() => _step = 2),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          child: Text(appTr('Back to Training')),
        ),
      ],
    );
  }
}

// ============================================================================
// MODAL 2: VOICE PICKER WITH AUDIO PREVIEW SHEET
// ============================================================================
class _VoicePickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> voices;
  final String selectedVoiceId;
  final ValueChanged<String> onSelected;

  const _VoicePickerSheet({
    required this.voices,
    required this.selectedVoiceId,
    required this.onSelected,
  });

  @override
  State<_VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends State<_VoicePickerSheet> {
  final _searchCtrl = TextEditingController();
  String _previewingVoiceId = '';
  Timer? _previewTimer;

  @override
  void dispose() {
    _previewTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _simulatePreview(String voiceId) {
    setState(() => _previewingVoiceId = voiceId);
    _previewTimer?.cancel();
    _previewTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _previewingVoiceId = '');
    });
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final query = _searchCtrl.text.toLowerCase().trim();
    final filtered = widget.voices.where((v) {
      if (query.isEmpty) return true;
      final name = '${v['name'] ?? ''}'.toLowerCase();
      final cat = '${v['category'] ?? ''}'.toLowerCase();
      return name.contains(query) || cat.contains(query);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    appTr('Select Agent Voice'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: appTr('Search voices by name or accent...'),
                prefixIcon: const Icon(Icons.search),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final v = filtered[i];
                final voiceId = '${v['voice_id']}';
                final name = '${v['name'] ?? voiceId}';
                final isSelected = voiceId == widget.selectedVoiceId;
                final isPreviewing = _previewingVoiceId == voiceId;

                return ListTile(
                  leading: IconButton(
                    icon: Icon(
                      isPreviewing ? Icons.volume_up : Icons.play_arrow,
                      color: isPreviewing ? Colors.green : Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () => _simulatePreview(voiceId),
                    tooltip: appTr('Preview voice sample'),
                  ),
                  title: Text(
                    name,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? Theme.of(context).colorScheme.primary : null,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
                  onTap: () => widget.onSelected(voiceId),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODAL 3: CALL SIMULATOR PHONE SHEET
// ============================================================================
class _PhoneSimulatorSheet extends StatefulWidget {
  final NativeWorkspaceService service;
  final Map<String, dynamic> agent;

  const _PhoneSimulatorSheet({
    required this.service,
    required this.agent,
  });

  @override
  State<_PhoneSimulatorSheet> createState() => _PhoneSimulatorSheetState();
}

class _PhoneSimulatorSheetState extends State<_PhoneSimulatorSheet> {
  String _status = 'ready'; // ready, connecting, talking, ended
  int _seconds = 0;
  Timer? _callTimer;

  @override
  void dispose() {
    _callTimer?.cancel();
    super.dispose();
  }

  void _startSimulation() async {
    setState(() => _status = 'connecting');
    try {
      await widget.service.mutate(
        kind: 'phone_agent',
        operation: 'simulate',
        requestId: 'sim-${DateTime.now().millisecondsSinceEpoch}',
        recordId: widget.agent['id'] as int,
      );
    } catch (_) {}

    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    setState(() {
      _status = 'talking';
      _seconds = 0;
    });

    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _seconds++);
    });
  }

  void _endCall() {
    _callTimer?.cancel();
    setState(() => _status = 'ended');
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final title = '${widget.agent['title'] ?? 'Agent'}';
    final timerStr = '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Color(0xFF1C1C1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  appTr('Call Simulator'),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Spacer(),

          // Center Call Status & Graphic
          Column(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: Colors.white12,
                child: Icon(
                  _status == 'talking' ? Icons.phone_in_talk : Icons.support_agent,
                  color: Colors.white,
                  size: 42,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                switch (_status) {
                  'connecting' => appTr('Connecting to agent...'),
                  'talking' => '${appTr('Connected')} • $timerStr',
                  'ended' => appTr('Call Ended'),
                  _ => appTr('Test Voice Simulation'),
                },
                style: TextStyle(
                  color: _status == 'talking' ? Colors.greenAccent : Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const Spacer(),

          // Action Buttons
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: switch (_status) {
              'talking' => FloatingActionButton.large(
                  backgroundColor: Colors.red,
                  onPressed: _endCall,
                  child: const Icon(Icons.call_end, color: Colors.white, size: 36),
                ),
              'connecting' => const CircularProgressIndicator(color: Colors.white),
              'ended' => FilledButton.icon(
                  onPressed: _startSimulation,
                  icon: const Icon(Icons.replay),
                  label: Text(appTr('Call Again')),
                ),
              _ => FloatingActionButton.large(
                  backgroundColor: Colors.green,
                  onPressed: _startSimulation,
                  child: const Icon(Icons.call, color: Colors.white, size: 36),
                ),
            },
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODAL 4: CALL DETAIL & TRANSCRIPTS SHEET
// ============================================================================
class _CallDetailSheet extends StatelessWidget {
  final Map<String, dynamic> call;
  final NativeWorkspaceService service;
  final VoidCallback onChanged;

  const _CallDetailSheet({
    required this.call,
    required this.service,
    required this.onChanged,
  });

  Future<void> _pinCall(BuildContext context) async {
    try {
      await service.mutate(
        kind: 'call',
        operation: 'pin',
        requestId: 'pin-${call['id']}-${DateTime.now().millisecondsSinceEpoch}',
        recordId: call['id'] as int,
      );
      if (!context.mounted) return;
      onChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr(e.toString()))),
      );
    }
  }

  Future<void> _deleteCall(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appTr('Delete Call Record?')),
        content: Text(appTr('This call record and its transcripts will be permanently removed.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(appTr('Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(appTr('Delete')),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      await service.mutate(
        kind: 'call',
        operation: 'delete',
        requestId: 'del-call-${call['id']}',
        recordId: call['id'] as int,
      );
      if (!context.mounted) return;
      onChanged();
      Navigator.pop(context);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr(e.toString()))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final caller = '${call['caller_number'] ?? 'Caller'}';
    final called = '${call['called_number'] ?? ''}';
    final agentTitle = '${call['agent_title'] ?? 'Agent'}';
    final durationSec = (call['duration'] as num?)?.toInt() ?? 0;
    final durationStr = '${(durationSec ~/ 60).toString().padLeft(2, '0')}:${(durationSec % 60).toString().padLeft(2, '0')}';
    final transcripts = (call['transcripts'] as List? ?? []).whereType<Map>().toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$caller ${called.isNotEmpty ? '→ $called' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      Text(
                        '$agentTitle • $durationStr',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.push_pin_outlined),
                  onPressed: () => _pinCall(context),
                  tooltip: appTr('Pin / Unpin'),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  color: Theme.of(context).colorScheme.error,
                  onPressed: () => _deleteCall(context),
                  tooltip: appTr('Delete call'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Transcripts
          Expanded(
            child: transcripts.isEmpty
                ? Center(
                    child: Text(
                      appTr('No transcripts recorded for this call.'),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: transcripts.length,
                    itemBuilder: (ctx, i) {
                      final t = transcripts[i];
                      final role = '${t['role'] ?? 'user'}';
                      final isAgent = role.toLowerCase() == 'assistant' || role.toLowerCase() == 'agent';
                      final msg = '${t['message'] ?? ''}';

                      return Align(
                        alignment: isAgent ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.75,
                          ),
                          decoration: BoxDecoration(
                            color: isAgent
                                ? Theme.of(context).colorScheme.surfaceVariant
                                : Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isAgent ? agentTitle : appTr('Caller'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isAgent ? Theme.of(context).colorScheme.primary : Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg,
                                style: TextStyle(
                                  color: isAgent ? Theme.of(context).colorScheme.onSurface : Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODAL 5: PLACE OUTBOUND CALL SHEET
// ============================================================================
class _PlaceOutboundCallSheet extends StatefulWidget {
  final NativeWorkspaceService service;
  final List<Map<String, dynamic>> eligibleAgents;
  final VoidCallback onPlaced;

  const _PlaceOutboundCallSheet({
    required this.service,
    required this.eligibleAgents,
    required this.onPlaced,
  });

  @override
  State<_PlaceOutboundCallSheet> createState() => _PlaceOutboundCallSheetState();
}

class _PlaceOutboundCallSheetState extends State<_PlaceOutboundCallSheet> {
  final _toCtrl = TextEditingController();
  dynamic _selectedAgentId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.eligibleAgents.isNotEmpty) {
      _selectedAgentId = widget.eligibleAgents[0]['id'];
    }
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeCall() async {
    final to = _toCtrl.text.trim();
    if (to.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr('Phone number to call is required.'))),
      );
      return;
    }
    if (_selectedAgentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr('Please select an agent with an attached number.'))),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.service.mutate(
        kind: 'call',
        operation: 'place_call',
        requestId: 'outbound-${DateTime.now().millisecondsSinceEpoch}',
        inputs: {
          'agent_id': _selectedAgentId,
          'to_number': to,
        },
      );
      widget.onPlaced();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appTr(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                appTr('Place Outbound Call'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),

          DropdownButtonFormField<dynamic>(
            value: _selectedAgentId,
            decoration: InputDecoration(
              labelText: appTr('From Agent'),
              border: const OutlineInputBorder(),
            ),
            items: widget.eligibleAgents.map((a) {
              final title = '${a['title']} (${a['phone_number']})';
              return DropdownMenuItem(value: a['id'], child: Text(title));
            }).toList(),
            onChanged: (val) => setState(() => _selectedAgentId = val),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _toCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: appTr('Phone Number to Call (E.164)'),
              hintText: '+14155552671',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _busy ? null : _placeCall,
            icon: const Icon(Icons.phone_forwarded),
            label: Text(appTr('Dial Now')),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MODAL 6: NEW CAMPAIGN SHEET
// ============================================================================
class _NewCampaignSheet extends StatefulWidget {
  final NativeWorkspaceService service;
  final List<Map<String, dynamic>> eligibleAgents;
  final VoidCallback onCreated;

  const _NewCampaignSheet({
    required this.service,
    required this.eligibleAgents,
    required this.onCreated,
  });

  @override
  State<_NewCampaignSheet> createState() => _NewCampaignSheetState();
}

class _NewCampaignSheetState extends State<_NewCampaignSheet> {
  final _nameCtrl = TextEditingController(text: 'Outbound Campaign');
  final _recipientsCtrl = TextEditingController();
  dynamic _selectedAgentId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.eligibleAgents.isNotEmpty) {
      _selectedAgentId = widget.eligibleAgents[0]['id'];
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _recipientsCtrl.dispose();
    super.dispose();
  }

  Future<void> _createCampaign() async {
    final name = _nameCtrl.text.trim();
    final rec = _recipientsCtrl.text.trim();
    if (name.isEmpty || rec.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr('Campaign name and recipients are required.'))),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await widget.service.mutate(
        kind: 'campaign',
        operation: 'save_campaign',
        requestId: 'camp-${DateTime.now().millisecondsSinceEpoch}',
        inputs: {
          'agent_id': _selectedAgentId,
          'name': name,
          'recipients': rec,
        },
      );
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appTr(e.toString())),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                appTr('New Outbound Campaign'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: appTr('Campaign Name'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),

          DropdownButtonFormField<dynamic>(
            value: _selectedAgentId,
            decoration: InputDecoration(
              labelText: appTr('From Agent'),
              border: const OutlineInputBorder(),
            ),
            items: widget.eligibleAgents.map((a) {
              final title = '${a['title']} (${a['phone_number']})';
              return DropdownMenuItem(value: a['id'], child: Text(title));
            }).toList(),
            onChanged: (val) => setState(() => _selectedAgentId = val),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _recipientsCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: appTr('Recipient Phone Numbers'),
              hintText: '+14155552671\n+14155552672\n+14155552673',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),

          FilledButton.icon(
            onPressed: _busy ? null : _createCampaign,
            icon: const Icon(Icons.campaign),
            label: Text(appTr('Launch Campaign')),
            style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          ),
        ],
      ),
    );
  }
}
