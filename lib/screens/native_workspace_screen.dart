import '../services/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/mobile_api.dart';
import '../services/native_workspace_service.dart';
import '../services/social_post_service.dart';
import '../services/workspace_catalog.dart';
import 'native_module_screen.dart' show NativeSchemaScreen;
import 'native_settings_screen.dart';
import 'native_parity_screen.dart';
import 'server_screen.dart' show RetryPanel;
import 'workspace_screen.dart' show openModule, workspaceIcon;

class WorkspaceEmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const WorkspaceEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .12),
              child: Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              appTr(title),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              appTr(message),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                child: Text(appTr(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NativeWorkspaceScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const NativeWorkspaceScreen({
    super.key,
    required this.module,
    required this.api,
  });
  @override
  State<NativeWorkspaceScreen> createState() => _NativeWorkspaceScreenState();
}

class _NativeWorkspaceScreenState extends State<NativeWorkspaceScreen> {
  late final _service = NativeWorkspaceService(
    widget.api,
    '${widget.module['id']}',
  );
  Map<String, dynamic>? _workspace;
  final _search = TextEditingController();
  List<Map> _records = [];
  String? _error, _currency;
  String _status = 'all';
  DateTime? _day;
  bool _loading = false;
  int _generation = 0;
  Timer? _debounce;
  final _deleteRequests = <int, String>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load(
        query: _search.text,
        status: _status,
        currency: _currency,
        day: _day,
        page: more ? (_workspace?['current_page'] as int? ?? 1) + 1 : 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _workspace = data;
        _records = more
            ? [..._records, ...(data['data'] as List? ?? []).whereType<Map>()]
            : (data['data'] as List? ?? []).whereType<Map>().toList();
        _currency = data['currency'] as String?;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit(String kind, [Map? record]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return WorkspaceRecordEditor(
            service: _service,
            kind: kind,
            record: record,
          );
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(String kind, Map record) async {
    final id = int.tryParse('${record['id']}');
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppLocalizations.watch(context);
        return AlertDialog(
          title: Text(appTr("Delete :value?", {"value": record['name']})),
          content: Text(appTr('This removes the record from your workspace.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(appTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(appTr('Delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _service.delete(
        kind: kind,
        id: id,
        requestId: _deleteRequests.putIfAbsent(id, SocialPostService.requestId),
      );
      _deleteRequests.remove(id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(dynamic value, String? currency) {
    final amount = num.tryParse('$value') ?? 0;
    return NumberFormat.simpleCurrency(name: currency ?? 'USD').format(amount);
  }

  String _date(dynamic value, {bool time = false}) {
    final date = DateTime.tryParse('$value');
    return date == null
        ? 'Not scheduled'
        : (time ? DateFormat.yMMMd().add_jm() : DateFormat.yMMMd()).format(
            date.toLocal(),
          );
  }

  Widget _badge(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(value, style: Theme.of(context).textTheme.labelMedium),
  );
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(appTr(title), style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _metrics(List items) => LayoutBuilder(
    builder: (context, constraints) {
      AppLocalizations.watch(context);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final metric in items.whereType<Map>())
            SizedBox(
              width: (constraints.maxWidth - 12) / 2,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(switch (metric['icon']) {
                        'paid' => Icons.check_circle_outline,
                        'overdue' => Icons.schedule,
                        'balance' => Icons.account_balance_wallet_outlined,
                        _ => Icons.receipt_long_outlined,
                      }, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 14),
                      Text(
                        appTr((metric['label']).toString()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _money(
                            metric['value'],
                            metric['currency'] as String?,
                          ),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _invoice(Map record) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          AppLocalizations.watch(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${record['number']}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                _badge('${record['status']}'),
                const SizedBox(height: 20),
                Text(
                  '${record['customer'] ?? ''}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  appTr("Total: :value", {
                    "value": _money(
                      record['total'],
                      record['currency'] as String?,
                    ),
                  }),
                ),
                Text(
                  appTr("Balance due: :value", {
                    "value": _money(
                      record['balance'],
                      record['currency'] as String?,
                    ),
                  }),
                ),
                const SizedBox(height: 16),
                Text(
                  appTr("Issued :value", {
                    "value": _date(record['issue_date']),
                  }),
                ),
                if (record['due_date'] != null)
                  Text(
                    appTr("Due :value", {"value": _date(record['due_date'])}),
                  ),
                if ('${record['notes'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('${record['notes']}'),
                ],
              ],
            ),
          );
        },
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${record['number']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                _badge('${record['status']}'),
              ],
            ),
            if ('${record['customer'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${record['customer']}'),
            ],
            const SizedBox(height: 18),
            Text(
              _money(record['total'], record['currency'] as String?),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (record['due_date'] != null) ...[
              const SizedBox(height: 8),
              Text(
                appTr("Due :value", {"value": _date(record['due_date'])}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _company(Map record) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(child: Icon(Icons.business_outlined)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record['name']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if ('${record['industry'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${record['industry']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_loading,
                onSelected: (action) => action == 'edit'
                    ? _edit('company', record)
                    : _delete('company', record),
                itemBuilder: (localizationContext) {
                  AppLocalizations.watch(localizationContext);
                  return [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(appTr('Edit company')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(appTr('Delete company')),
                    ),
                  ];
                },
              ),
            ],
          ),
          if ([
            record['address'],
            record['city'],
            record['state'],
            record['country'],
          ].any((value) => value != null && '$value'.trim().isNotEmpty)) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                          record['address'],
                          record['city'],
                          record['state'],
                          record['country'],
                        ]
                        .where(
                          (value) =>
                              value != null && '$value'.trim().isNotEmpty,
                        )
                        .join(', '),
                  ),
                ),
              ],
            ),
          ],
          if ('${record['email'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${record['email']}'),
          ],
        ],
      ),
    ),
  );

  Widget _campaign(Map record) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(child: Icon(Icons.campaign_outlined)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record['name']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _badge('${record['target_audience']}'),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: appTr('Delete campaign'),
            onPressed: _loading ? null : () => _delete('campaign', record),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );

  Widget _agenda(Map post) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.article_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${post['title']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (post['agent'] != null) Text('${post['agent']}'),
                const SizedBox(height: 8),
                Text(
                  _date(
                    post['published_at'] ?? post['scheduled_at'],
                    time: true,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                _badge('${post['status']}'),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _photo(Map record) {
    final image = Uri.tryParse('${record['image_url'] ?? ''}');
    final url = image == null ? null : widget.api.origin.resolveUri(image);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url != null &&
              url.scheme == 'https' &&
              url.userInfo.isEmpty &&
              url.path.isNotEmpty)
            Image.network(
              '$url',
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (localizationContext, error, stack) {
                AppLocalizations.watch(localizationContext);
                return const SizedBox(
                  height: 120,
                  child: Icon(Icons.image_outlined, size: 36),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record['title']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _badge('${record['status']}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tools(List<Map> tools) => [
    for (final tool in tools)
      Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openModule(
            context,
            Map<String, dynamic>.from(tool),
            api: widget.api,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .12),
                  child: Icon(
                    workspaceIcon('${tool['id']} ${tool['title']}'),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    appTr(workspaceTitle(tool)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  tool['available'] == true
                      ? Icons.chevron_right
                      : Icons.lock_outline,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_workspace == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : RetryPanel(message: appTr(_error!), retry: _load),
      );
    }
    final kind = '${_workspace!['kind']}';
    if (kind == 'fashion_settings') {
      return NativeParityScreen(
        module: {...widget.module, 'route_type': kind},
        api: widget.api,
      );
    }
    if (kind == 'form' || kind == 'overview') {
      return NativeSchemaScreen(module: widget.module, api: widget.api);
    }
    if (kind == 'settings') return NativeSettingsScreen(api: widget.api);
    final tools = (_workspace!['modules'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final isBlog = kind == 'blog';
    final isCalendar = isBlog && _workspace!['calendar'] == true;
    final summary = switch (kind) {
      'invoices' =>
        'Stay on top of invoices, payments and outstanding balances.',
      'companies' => 'Keep your business relationships in one place.',
      'campaigns' => 'Shape your message around the right audience.',
      'blog' => 'Plan your articles and see what’s coming next.',
      'photoshoot' => 'Create product images and explore your recent work.',
      _ =>
        'Discover the tools in ${widget.module['category'] ?? 'your workspace'}.',
    };
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  appTr(workspaceTitle(widget.module)),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  summary,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(appTr(_error!)),
                          TextButton(
                            onPressed: _loading ? null : _load,
                            child: Text(appTr('Retry')),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (kind == 'invoices') ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 20),
                  if ((_workspace!['currencies'] as List? ?? []).length > 1)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(_currency),
                      initialValue: _currency,
                      decoration: InputDecoration(labelText: appTr('Currency')),
                      items: [
                        for (final currency
                            in _workspace!['currencies'] as List)
                          DropdownMenuItem(
                            value: '$currency',
                            child: Text('$currency'),
                          ),
                      ],
                      onChanged: _loading
                          ? null
                          : (currency) {
                              setState(() => _currency = currency);
                              _load();
                            },
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final status in const {
                        'all': 'All invoices',
                        'draft': 'Draft',
                        'sent': 'Sent',
                        'paid': 'Paid',
                        'overdue': 'Overdue',
                      }.entries)
                        ChoiceChip(
                          label: Text(appTr(status.value)),
                          selected: _status == status.key,
                          onSelected: (_) {
                            setState(() => _status = status.key);
                            _load();
                          },
                        ),
                    ],
                  ),
                ],
                if (kind == 'companies' ||
                    kind == 'campaigns' ||
                    kind == 'invoices') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: appTr("Search :kind", {"kind": kind}),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        _load,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                if (kind == 'companies' || kind == 'campaigns')
                  FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _edit(
                            kind == 'companies' ? 'company' : 'campaign',
                          ),
                    icon: const Icon(Icons.add),
                    label: Text(
                      appTr(
                        kind == 'companies' ? 'New company' : 'New campaign',
                      ),
                    ),
                  ),
                if (kind == 'photoshoot') ...[
                  _section('Create a photoshoot'),
                  ..._tools(
                    tools
                        .where(
                          (tool) => tool['route_type'] == 'extension_workflow',
                        )
                        .toList(),
                  ),
                  _section('Your gallery'),
                ],
                if (isCalendar) ...[
                  CalendarDatePicker(
                    initialDate: _day ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    onDateChanged: (day) {
                      setState(() => _day = day);
                      _load();
                    },
                  ),
                  if (_day != null)
                    TextButton(
                      onPressed: () {
                        setState(() => _day = null);
                        _load();
                      },
                      child: Text(appTr('Show all dates')),
                    ),
                  _section(_day == null ? 'Publishing agenda' : _date(_day)),
                ],
                if (isBlog && _workspace!['show_agents'] == true) ...[
                  _section('Your agents'),
                  if ((_workspace!['agents'] as List? ?? []).isEmpty)
                    WorkspaceEmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: appTr('Your publishing workspace'),
                      message: appTr(
                        'Your agents and their publishing schedules will appear here.',
                      ),
                    ),
                  for (final agent
                      in (_workspace!['agents'] as List? ?? [])
                          .whereType<Map>())
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${agent['name']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            _badge(
                              agent['is_active'] == true ? 'Active' : 'Paused',
                            ),
                            if ((agent['schedule_days'] as List? ?? [])
                                .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                (agent['schedule_days'] as List).join(' · '),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  _section('Recent articles'),
                ],
                if (const [
                      'invoices',
                      'companies',
                      'campaigns',
                      'photoshoot',
                      'blog',
                    ].contains(kind) &&
                    _records.isEmpty)
                  WorkspaceEmptyState(
                    icon: switch (kind) {
                      'invoices' => Icons.receipt_long_outlined,
                      'companies' => Icons.business_outlined,
                      'campaigns' => Icons.campaign_outlined,
                      'photoshoot' => Icons.camera_alt_outlined,
                      _ => Icons.event_note_outlined,
                    },
                    title: appTr(
                      _search.text.isNotEmpty
                          ? 'No matching results'
                          : switch (kind) {
                              'invoices' => 'No invoices yet',
                              'companies' => 'No companies yet',
                              'campaigns' => 'No campaigns yet',
                              'photoshoot' => 'No photoshoots yet',
                              _ => 'A clear calendar, a fresh start',
                            },
                    ),
                    message: appTr(
                      _search.text.isNotEmpty
                          ? 'Try another search or clear your filters.'
                          : switch (kind) {
                              'invoices' => 'Your invoices will appear here, with their totals, due dates and payment status.',
                              'companies' => 'Add your first company to start building your network.',
                              'campaigns' => 'Create a campaign to bring your audience and message together.',
                              'photoshoot' =>
                                'Create a photoshoot to see your images here.',
                              _ => 'Your planned articles will appear in the agenda. Select a day to explore your publishing schedule.',
                            },
                    ),
                    actionLabel: kind == 'photoshoot'
                        ? appTr('Create photoshoot')
                        : null,
                    onAction:
                        kind == 'photoshoot' &&
                            tools.any(
                              (tool) =>
                                  tool['route_type'] == 'extension_workflow' &&
                                  tool['available'] == true,
                            )
                        ? () => openModule(
                            context,
                            Map<String, dynamic>.from(
                              tools.firstWhere(
                                (tool) =>
                                    tool['route_type'] ==
                                        'extension_workflow' &&
                                    tool['available'] == true,
                              ),
                            ),
                            api: widget.api,
                          )
                        : null,
                  ),
                for (final record in _records)
                  switch (kind) {
                    'invoices' => _invoice(record),
                    'companies' => _company(record),
                    'campaigns' => _campaign(record),
                    'blog' => _agenda(record),
                    'photoshoot' => _photo(record),
                    _ => const SizedBox.shrink(),
                  },
                if ((_workspace!['current_page'] as int? ?? 1) <
                    (_workspace!['last_page'] as int? ?? 1))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => _load(more: true),
                      child: Text(appTr('Load more')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class WorkspaceRecordEditor extends StatefulWidget {
  final NativeWorkspaceService service;
  final String kind;
  final Map? record;
  const WorkspaceRecordEditor({
    super.key,
    required this.service,
    required this.kind,
    this.record,
  });
  @override
  State<WorkspaceRecordEditor> createState() => _WorkspaceRecordEditorState();
}

class _WorkspaceRecordEditorState extends State<WorkspaceRecordEditor> {
  final _form = GlobalKey<FormState>();
  late final _controllers = <String, TextEditingController>{
    for (final name in _fields.keys)
      name: TextEditingController(text: '${widget.record?[name] ?? ''}'),
  };
  String? _error;
  bool _saving = false;
  String _requestId = SocialPostService.requestId();
  Map<String, String> get _fields => widget.kind == 'campaign'
      ? {'name': 'Campaign name', 'target_audience': 'Target audience'}
      : {
          'name': 'Company name',
          'industry': 'Industry',
          'website': 'Website',
          'email': 'Email',
          'phone': 'Phone',
          'address': 'Address',
          'city': 'City',
          'state': 'State / region',
          'country': 'Country',
          'notes': 'Notes',
        };
  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.save(
        kind: widget.kind,
        requestId: _requestId,
        id: int.tryParse('${widget.record?['id']}'),
        inputs: {
          for (final entry in _controllers.entries)
            entry.key: entry.value.text.trim(),
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          '${appTr(widget.record == null ? 'New' : 'Edit')} ${appTr(widget.kind)}',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            children: [
              for (final entry in _fields.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: TextFormField(
                    controller: _controllers[entry.key],
                    enabled: !_saving,
                    minLines:
                        entry.key == 'target_audience' || entry.key == 'notes'
                        ? 3
                        : 1,
                    maxLines:
                        entry.key == 'target_audience' || entry.key == 'notes'
                        ? 5
                        : 1,
                    keyboardType: entry.key == 'email'
                        ? TextInputType.emailAddress
                        : entry.key == 'phone'
                        ? TextInputType.phone
                        : entry.key == 'website'
                        ? TextInputType.url
                        : TextInputType.text,
                    decoration: InputDecoration(labelText: entry.value),
                    onChanged: (_) =>
                        _requestId = SocialPostService.requestId(),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if ([
                            appTr('name'),
                            appTr('target_audience'),
                          ].contains(entry.key) &&
                          text.isEmpty) {
                        return 'Enter ${entry.value.toLowerCase()}.';
                      }
                      if (entry.key == appTr('email') &&
                          text.isNotEmpty &&
                          !text.contains('@')) {
                        return appTr('Enter a valid email.');
                      }
                      return null;
                    },
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    appTr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(appTr(_saving ? 'Saving…' : 'Save ${widget.kind}')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
