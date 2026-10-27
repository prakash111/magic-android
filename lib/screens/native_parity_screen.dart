import '../services/app_localizations.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/mobile_api.dart';
import '../services/native_extension_service.dart';
import '../services/social_post_service.dart';
import 'native_module_screen.dart' show NativeSchemaForm;
import 'native_workspace_screen.dart' show WorkspaceEmptyState;
import 'server_screen.dart' show RetryPanel;

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : [];
Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};
String _label(String value) => value
    .replaceAll('_', ' ')
    .replaceAllMapped(RegExp(r'(^|\s)\w'), (match) => match[0]!.toUpperCase());

dynamic _schemaDefault(Map schema) =>
    schema['default'] ??
    switch (schema['type']) {
      'object' => {
        for (final entry in _map(schema['properties']).entries)
          entry.key: _schemaDefault(_map(entry.value)),
      },
      'array' => <dynamic>[],
      'boolean' => false,
      'integer' || 'number' => 0,
      _ =>
        (schema['enum'] is List && (schema['enum'] as List).isNotEmpty)
            ? (schema['enum'] as List).first
            : '',
    };

class NativeParityScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const NativeParityScreen({
    super.key,
    required this.module,
    required this.api,
  });
  @override
  State<NativeParityScreen> createState() => _NativeParityScreenState();
}

class _NativeParityScreenState extends State<NativeParityScreen> {
  late final _service = NativeExtensionService(
    widget.api,
    '${widget.module['id']}',
  );
  final _search = TextEditingController();
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _rows = [];
  String? _error;
  String _status = 'all';
  DateTime _date = DateTime.now();
  bool _busy = false;
  int _generation = 0;
  Timer? _debounce;
  String get _kind => '${widget.module['route_type']}';
  bool get _calendar =>
      _data?['calendar'] == true ||
      (_kind == 'agent_posts' && '${widget.module['id']}'.contains('calendar'));

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
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.call(
        'load',
        values: {
          'query': _search.text.trim(),
          'status': _status,
          'page': more
              ? (int.tryParse('${_data?['current_page']}') ?? 1) + 1
              : 1,
          if (_calendar) ...{
            'from': DateTime(_date.year, _date.month).toUtc().toIso8601String(),
            'until': DateTime(
              _date.year,
              _date.month + 1,
            ).toUtc().toIso8601String(),
          },
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = result;
        _rows = more
            ? [..._rows, ..._maps(result['data'])]
            : _maps(result['data']);
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _edit(
    String operation,
    String title,
    List<Map<String, dynamic>> fields, {
    Map? record,
    DateTime? scheduledAt,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return NativeRecordForm(
            service: _service,
            operation: operation,
            title: appTr(title),
            fields: fields,
            recordId: int.tryParse('${record?['id']}'),
            dateField: operation == 'save_task'
                ? 'due_date'
                : operation == 'save_agent_post'
                ? 'scheduled_at'
                : null,
            scheduledAt: scheduledAt,
          );
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _action(
    String operation,
    Map row, {
    Map<String, dynamic> inputs = const {},
    bool confirm = false,
  }) async {
    if (_busy) return;
    if (confirm) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) {
          AppLocalizations.watch(context);
          return AlertDialog(
            title: Text(appTr('Delete this item?')),
            content: Text(appTr('This change cannot be undone.')),
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
      if (accepted != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.call(
        operation,
        values: {'record_id': row['id']},
        inputs: inputs,
      );
      if (!mounted) return;
      if (operation == 'agent_runs') {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (context) {
            AppLocalizations.watch(context);
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .7,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      appTr('Run history'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_maps(result['data']).isEmpty)
                      WorkspaceEmptyState(
                        icon: Icons.history,
                        title: appTr('No runs yet'),
                        message: appTr(
                          'Agent activity appears here after a trigger runs.',
                        ),
                      ),
                    for (final run in _maps(result['data']))
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.history),
                          title: Text(appTr(_label('${run['status']}'))),
                          subtitle: Text(
                            [
                              _time(run['started_at']),
                              if (run['error_message'] != null)
                                '${run['error_message']}',
                            ].join('\n'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      } else {
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _field(
    String name,
    String label, {
    String type = 'text',
    dynamic value,
    List options = const [],
    bool required = false,
  }) => {
    'name': name,
    'label': label,
    'type': type,
    'value': value,
    'options': options,
    'required': required,
  };
  List<Map<String, String>> _options(List<String> values) => [
    for (final value in values) {'value': value, 'label': _label(value)},
  ];
  String _time(dynamic value) {
    final date = DateTime.tryParse('$value')?.toLocal();
    return date == null
        ? 'Not scheduled'
        : DateFormat.yMMMd().add_jm().format(date);
  }

  Future<void> _agent([Map? record]) async {
    Map<String, dynamic>? config;
    if (record == null) {
      config = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          AppLocalizations.watch(context);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: AgentTemplateSelector(
              templates: _maps(_data?['templates']),
              api: widget.api,
            ),
          );
        },
      );
      if (config == null || !mounted) return;
    } else {
      config = _map(record);
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return AgentSetupScreen(
            service: _service,
            config: config!,
            actions: _map(_data?['actions']),
            channels: _maps(_data?['channels']),
          );
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _task([Map? row]) => _edit(
    'save_task',
    row == null ? 'New task' : 'Edit task',
    [
      _field('title', 'Task title', value: row?['title'], required: true),
      _field(
        'description',
        'Description',
        type: 'textarea',
        value: row?['description'],
      ),
      _field(
        'type',
        'Type',
        type: 'select',
        value: row?['type'] ?? 'task',
        options: _options(['task', 'call', 'meeting', 'email', 'follow_up']),
      ),
      _field(
        'priority',
        'Priority',
        type: 'select',
        value: row?['priority'] ?? 'medium',
        options: _options(['low', 'medium', 'high']),
      ),
      _field(
        'status',
        'Status',
        type: 'select',
        value: row?['status'] ?? 'pending',
        options: _options(['pending', 'completed', 'cancelled']),
      ),
      _field(
        'crm_contact_id',
        'Contact',
        type: 'select',
        value: row?['crm_contact_id'],
        options: _maps(_data?['contacts']),
      ),
      _field(
        'crm_deal_id',
        'Deal',
        type: 'select',
        value: row?['crm_deal_id'],
        options: _maps(_data?['deals']),
      ),
    ],
    record: row,
    scheduledAt: DateTime.tryParse('${row?['due_date']}')?.toLocal(),
  );

  Future<void> _post([Map? row]) => _edit(
    'save_agent_post',
    row == null ? 'Schedule agent post' : 'Edit agent post',
    [
      if (row == null)
        _field(
          'agent_id',
          'Agent',
          type: 'select',
          options: [
            for (final agent in _maps(_data?['agents']))
              {'value': agent['id'], 'label': agent['name']},
          ],
          required: true,
        ),
      _field(
        'content',
        'Post content',
        type: 'textarea',
        value: row?['content'],
        required: true,
      ),
      _field(
        'platform_id',
        'Connected account',
        type: 'select',
        value: row?['platform_id'],
        options: _maps(_data?['platforms']),
        required: true,
      ),
      _field(
        'post_type',
        'Post type',
        type: 'select',
        value: row?['post_type'] ?? 'text',
        options: _options(['text', 'single_image', 'carousel', 'video']),
      ),
    ],
    record: row,
    scheduledAt: DateTime.tryParse('${row?['scheduled_at']}')?.toLocal(),
  );

  Widget _badge(String text) => Chip(
    label: Text(appTr(_label(text))),
    visualDensity: VisualDensity.compact,
  );
  List<Widget> _content() {
    if (_kind == 'fashion_settings') {
      final values = _map(_data?['settings']);
      return [
        Text(
          appTr('Generation settings'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          appTr('Choose the defaults used by your Fashion Studio photoshoots.'),
        ),
        const SizedBox(height: 16),
        NativeSchemaForm(
          key: ValueKey(jsonEncode(values)),
          definition: {
            'title': 'Save settings',
            'fields': [
              _field(
                'num_images',
                'Number of generated images',
                type: 'select',
                value: values['num_images'],
                required: true,
                options: [
                  for (
                    var i = 1;
                    i <= (int.tryParse('${_data?['max_images']}') ?? 4);
                    i++
                  )
                    {
                      'value': '$i',
                      'label': '$i ${i == 1 ? 'image' : 'images'}',
                    },
                ],
              ),
              _field(
                'resolution',
                'Resolution',
                type: 'select',
                value: values['resolution'],
                options: _options(
                  (_data?['resolutions'] as List? ?? [])
                      .map((v) => '$v')
                      .toList(),
                ),
                required: true,
              ),
              _field(
                'ratio',
                'Aspect ratio',
                type: 'select',
                value: values['ratio'],
                options: _options(
                  (_data?['ratios'] as List? ?? []).map((v) => '$v').toList(),
                ),
                required: true,
              ),
            ],
          },
          busy: _busy,
          submit: (inputs, _) async {
            setState(() => _busy = true);
            try {
              final result = await _service.call(
                'save_fashion',
                inputs: inputs,
              );
              if (!mounted) return;
              setState(() {
                _data = result;
                _error = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(appTr('Photoshoot settings saved.'))),
              );
            } catch (error) {
              if (mounted) setState(() => _error = error.toString());
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
      ];
    }
    final metrics = _maps(_data?['metrics']);
    return [
      Row(
        children: [
          Expanded(
            child: Text(
              appTr(
                _kind == 'ai_agents'
                    ? 'Your agents'
                    : _kind == 'crm_tasks'
                    ? 'Tasks'
                    : _calendar
                    ? 'Content calendar'
                    : 'Agent posts',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (['ai_agents', 'crm_tasks', 'agent_posts'].contains(_kind))
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _kind == 'ai_agents'
                        ? _agent()
                        : _kind == 'crm_tasks'
                        ? _task()
                        : _post(),
              icon: const Icon(Icons.add),
              label: Text(
                appTr(
                  _kind == 'ai_agents'
                      ? 'New Agent'
                      : _kind == 'crm_tasks'
                      ? 'New task'
                      : 'New post',
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 16),
      if (metrics.isNotEmpty)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final metric in metrics)
              SizedBox(
                width: (MediaQuery.sizeOf(context).width - 52) / 2,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${metric['value'] ?? 0}',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(appTr((metric['label']).toString())),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      if (_calendar)
        Card(
          child: CalendarDatePicker(
            initialDate: _date,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            onDateChanged: (date) {
              setState(() => _date = date);
              _load();
            },
            onDisplayedMonthChanged: (date) {
              setState(() => _date = date);
              _load();
            },
          ),
        ),
      const SizedBox(height: 12),
      TextField(
        controller: _search,
        decoration: InputDecoration(
          labelText: appTr('Search'),
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 300), _load);
        },
      ),
      if (_kind != 'ai_agents')
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final status
                  in _kind == 'crm_tasks'
                      ? ['all', 'pending', 'completed', 'cancelled']
                      : _calendar
                      ? ['all', 'scheduled', 'published']
                      : ['all', 'draft', 'scheduled', 'published', 'failed'])
                Padding(
                  padding: const EdgeInsets.only(right: 8, top: 12, bottom: 12),
                  child: ChoiceChip(
                    label: Text(appTr(_label(status))),
                    selected: _status == status,
                    onSelected: _busy
                        ? null
                        : (_) {
                            setState(() => _status = status);
                            _load();
                          },
                  ),
                ),
            ],
          ),
        ),
      if (_rows.isEmpty && !_busy) ...[
        WorkspaceEmptyState(
          icon: _kind == 'ai_agents'
              ? Icons.smart_toy_outlined
              : _kind == 'crm_tasks'
              ? Icons.task_alt
              : Icons.event_note,
          title: appTr(
            _search.text.isNotEmpty
                ? 'No matching results'
                : _kind == 'ai_agents'
                ? 'Create your first agent'
                : _kind == 'crm_tasks'
                ? 'No tasks yet'
                : 'No posts in this view',
          ),
          message: appTr(
            _kind == 'ai_agents'
                ? 'Start with a workflow template or build your own.'
                : _kind == 'crm_tasks'
                ? 'Add a task to track your next action.'
                : 'Try another month or status to see your posts.',
          ),
        ),
        if (_kind == 'ai_agents' || _kind == 'crm_tasks')
          TextButton.icon(
            onPressed: () => _kind == 'ai_agents' ? _agent() : _task(),
            icon: const Icon(Icons.add),
            label: Text(
              appTr(_kind == 'ai_agents' ? 'Add Agent' : 'Create task'),
            ),
          ),
      ],
      for (final row in _rows)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_kind == 'ai_agents') ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.smart_toy_outlined),
                      title: Text('${row['name'] ?? 'Agent'}'),
                      subtitle: Text(
                        appTr((row['description'] ?? '').toString()),
                      ),
                      onTap: () => _agent(row),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        _badge('${row['status'] ?? 'paused'}'),
                        _badge('${row['trigger_type'] ?? 'schedule'}'),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : () => _agent(row),
                          child: Text(appTr('Configure')),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _action('toggle_agent', row),
                          child: Text(
                            appTr(
                              row['status'] == 'active' ? 'Pause' : 'Activate',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _action('agent_runs', row),
                          child: Text(appTr('Run history')),
                        ),
                        IconButton(
                          tooltip: appTr('Delete agent'),
                          onPressed: _busy
                              ? null
                              : () =>
                                    _action('delete_agent', row, confirm: true),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ] else if (_kind == 'crm_tasks') ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${row['title'] ?? 'Task'}'),
                      subtitle: Text(
                        appTr(
                          [
                            if ('${row['description'] ?? ''}'.isNotEmpty)
                              '${row['description']}',
                            if ('${row['contact'] ?? ''}'.isNotEmpty)
                              '${row['contact']}',
                            if (row['due_date'] != null) _time(row['due_date']),
                          ].join('\n'),
                        ),
                      ),
                      onTap: () => _task(row),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        _badge('${row['status'] ?? 'pending'}'),
                        _badge('${row['priority'] ?? 'medium'}'),
                      ],
                    ),
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _action(
                                  'task_status',
                                  row,
                                  inputs: {
                                    'status': row['status'] == 'completed'
                                        ? 'pending'
                                        : 'completed',
                                  },
                                ),
                          child: Text(
                            appTr(
                              row['status'] == 'completed'
                                  ? 'Reopen'
                                  : 'Complete',
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _task(row),
                          child: Text(appTr('Edit')),
                        ),
                        IconButton(
                          tooltip: appTr('Delete task'),
                          onPressed: _busy
                              ? null
                              : () =>
                                    _action('delete_task', row, confirm: true),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ] else ...[
                    Wrap(
                      spacing: 8,
                      children: [
                        _badge('${row['status'] ?? 'draft'}'),
                        _badge('${row['platform'] ?? 'Disconnected account'}'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text('${row['content'] ?? ''}'),
                    const SizedBox(height: 12),
                    Text(
                      '${row['agent'] ?? 'Agent'} · ${_time(row['published_at'] ?? row['scheduled_at'])}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    for (final url in (row['media_urls'] as List? ?? []).take(
                      1,
                    ))
                      if (Uri.tryParse('$url')?.scheme == 'https')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              '$url',
                              height: 180,
                              fit: BoxFit.cover,
                              errorBuilder:
                                  (localizationContext, error, stack) {
                                    AppLocalizations.watch(localizationContext);
                                    return const Icon(
                                      Icons.broken_image_outlined,
                                    );
                                  },
                            ),
                          ),
                        ),
                    Wrap(
                      children: [
                        if (row['status'] != 'published')
                          TextButton(
                            onPressed: _busy ? null : () => _post(row),
                            child: Text(appTr('Edit / schedule')),
                          ),
                        if (row['status'] == 'draft')
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _action('approve_agent_post', row),
                            child: Text(appTr('Approve')),
                          ),
                        IconButton(
                          tooltip: appTr('Delete post'),
                          onPressed: _busy
                              ? null
                              : () => _action(
                                  'delete_agent_post',
                                  row,
                                  confirm: true,
                                ),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      if ((int.tryParse('${_data?['current_page']}') ?? 1) <
          (int.tryParse('${_data?['last_page']}') ?? 1))
        TextButton(
          onPressed: _busy ? null : () => _load(more: true),
          child: Text(appTr('Load more')),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : RetryPanel(message: appTr(_error!), retry: _load);
    }
    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          MaterialBanner(
            content: Text(appTr(_error!)),
            actions: [
              TextButton(
                onPressed: _busy ? null : _load,
                child: Text(appTr('Retry')),
              ),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(20),
              children: _content(),
            ),
          ),
        ),
      ],
    );
  }
}

class NativeRecordForm extends StatefulWidget {
  final NativeExtensionService service;
  final String operation, title;
  final List<Map<String, dynamic>> fields;
  final int? recordId;
  final String? dateField;
  final DateTime? scheduledAt;
  const NativeRecordForm({
    super.key,
    required this.service,
    required this.operation,
    required this.title,
    required this.fields,
    this.recordId,
    this.dateField,
    this.scheduledAt,
  });
  @override
  State<NativeRecordForm> createState() => _NativeRecordFormState();
}

class _NativeRecordFormState extends State<NativeRecordForm> {
  bool _busy = false;
  String? _error;
  String _request = SocialPostService.requestId();
  late DateTime? _date = widget.scheduledAt;
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(appTr(widget.title))),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                appTr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (widget.dateField != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.event),
                title: Text(
                  appTr(
                    _date == null
                        ? 'Choose date and time'
                        : DateFormat.yMMMd().add_jm().format(_date!),
                  ),
                ),
                subtitle: Text(
                  appTr(
                    widget.dateField == 'due_date'
                        ? 'Due date (optional)'
                        : 'Schedule in your local timezone',
                  ),
                ),
                trailing: _date == null
                    ? null
                    : IconButton(
                        tooltip: appTr('Clear date'),
                        onPressed: _busy
                            ? null
                            : () => setState(() => _date = null),
                        icon: const Icon(Icons.close),
                      ),
                onTap: _busy
                    ? null
                    : () async {
                        final day = await showDatePicker(
                          context: context,
                          initialDate: _date ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (day == null || !context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.fromDateTime(
                            _date ?? DateTime.now(),
                          ),
                        );
                        if (time != null && mounted) {
                          setState(
                            () => _date = DateTime(
                              day.year,
                              day.month,
                              day.day,
                              time.hour,
                              time.minute,
                            ),
                          );
                        }
                      },
              ),
            ),
          NativeSchemaForm(
            definition: {
              'title':
                  widget.operation == 'save_agent_post' &&
                      widget.recordId == null
                  ? 'Schedule post'
                  : 'Save',
              'fields': widget.fields,
            },
            busy: _busy,
            submit: (inputs, _) async {
              if (widget.operation == 'save_agent_post' &&
                  widget.recordId == null &&
                  _date == null) {
                setState(
                  () => _error = 'Choose a future date and time for your post.',
                );
                return;
              }
              setState(() {
                _busy = true;
                _error = null;
              });
              try {
                await widget.service.call(
                  widget.operation,
                  requestId: _request,
                  values: {'record_id': ?widget.recordId},
                  inputs: {
                    for (final entry in inputs.entries)
                      entry.key: entry.value.isEmpty ? null : entry.value,
                    if (widget.dateField != null)
                      widget.dateField!: _date?.toUtc().toIso8601String(),
                  },
                );
                if (context.mounted) Navigator.pop(context, true);
              } catch (error) {
                if (error is ApiFailure &&
                    error.status >= 400 &&
                    error.status < 500 &&
                    ![408, 409, 429].contains(error.status)) {
                  _request = SocialPostService.requestId();
                }
                if (mounted) setState(() => _error = error.toString());
              } finally {
                if (mounted) setState(() => _busy = false);
              }
            },
          ),
        ],
      ),
    );
  }
}

class AgentTemplateSelector extends StatefulWidget {
  final List<Map<String, dynamic>> templates;
  final MobileApi api;
  const AgentTemplateSelector({
    super.key,
    required this.templates,
    required this.api,
  });
  @override
  State<AgentTemplateSelector> createState() => _AgentTemplateSelectorState();
}

class _AgentTemplateSelectorState extends State<AgentTemplateSelector> {
  String _query = '', _category = 'All';
  final _favorites = <String>{};
  static const _categories = [
    'All',
    'Favorite',
    'CRM',
    'Email',
    'Outlook',
    'Social Media',
    'Marketing',
    'Chatbot',
    'Reports',
    'AI & Web',
  ];
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    try {
      final saved = await widget.api.store.read('agent_template_favorites');
      if (saved != null && mounted) {
        setState(
          () => _favorites.addAll(
            (jsonDecode(saved) as List).whereType<String>(),
          ),
        );
      }
    } catch (_) {
      /* Favorites are optional; the template library remains available. */
    }
  }

  bool _matches(Map row) {
    final tags = (row['tags'] as List? ?? [])
        .map((e) => '$e'.toLowerCase())
        .toSet();
    final category = switch (_category) {
      'CRM' => 'crm',
      'Email' => 'gmail',
      'Social Media' => 'social_media',
      'AI & Web' => 'ai',
      _ => _category.toLowerCase(),
    };
    return (_category == 'All' ||
            (_category == 'Favorite'
                ? _favorites.contains(row['key'])
                : tags.contains(category) ||
                      (_category == 'AI & Web' && tags.contains('web')) ||
                      (_category == 'Reports' && tags.contains('report')) ||
                      (_category == 'Social Media' &&
                          tags.contains('social')))) &&
        '${row['label']} ${row['description']}'.toLowerCase().contains(
          _query.toLowerCase().trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .9,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appTr('Add Agent'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: appTr('Close'),
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: InputDecoration(
                labelText: appTr('Search templates'),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final category in _categories)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 12,
                        bottom: 12,
                        right: 8,
                      ),
                      child: ChoiceChip(
                        label: Text(appTr(category)),
                        selected: _category == category,
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  AppLocalizations.watch(context);
                  final rows = [
                    if (_category == 'All' &&
                        'start from scratch'.contains(
                          _query.toLowerCase().trim(),
                        ))
                      <String, dynamic>{
                        'key': 'scratch',
                        'label': 'Start From Scratch',
                        'description': 'Create a custom workflow with your own trigger and actions.',
                        'config': {
                          'name': '',
                          'trigger_type': 'schedule',
                          'trigger_config': {'cron': '0 9 * * *'},
                          'steps': [],
                        },
                      },
                    ...widget.templates.where(_matches),
                  ];
                  if (rows.isEmpty) {
                    return WorkspaceEmptyState(
                      icon: Icons.search_off,
                      title: appTr('No templates found'),
                      message: appTr('Try another category or search term.'),
                    );
                  }
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: constraints.maxWidth >= 620
                          ? 3
                          : constraints.maxWidth >= 420
                          ? 2
                          : 1,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      mainAxisExtent: MediaQuery.textScalerOf(context)
                          .scale(190),
                    ),
                    itemCount: rows.length,
                    itemBuilder: (context, index) {
                      AppLocalizations.watch(context);
                      final row = rows[index];
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.pop(
                            context,
                            _map(jsonDecode(jsonEncode(row['config']))),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      row['key'] == 'scratch'
                                          ? Icons.add_circle_outline
                                          : Icons.auto_awesome_outlined,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                    const Spacer(),
                                    if (row['key'] != 'scratch')
                                      IconButton(
                                        tooltip: appTr('Favorite template'),
                                        isSelected: _favorites.contains(
                                          row['key'],
                                        ),
                                        selectedIcon: const Icon(Icons.star),
                                        icon: const Icon(Icons.star_border),
                                        onPressed: () async {
                                          final key = '${row['key']}';
                                          setState(
                                            () => _favorites.contains(key)
                                                ? _favorites.remove(key)
                                                : _favorites.add(key),
                                          );
                                          try {
                                            await widget.api.store.write(
                                              'agent_template_favorites',
                                              jsonEncode(_favorites.toList()),
                                            );
                                          } catch (_) {
                                            /* The current selection is retained for this session. */
                                          }
                                        },
                                      ),
                                  ],
                                ),
                                Text(
                                  appTr((row['label']).toString()),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Text(
                                    appTr(
                                      (row['description'] ?? '').toString(),
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AgentSetupScreen extends StatefulWidget {
  final NativeExtensionService service;
  final Map<String, dynamic> config, actions;
  final List<Map<String, dynamic>> channels;
  const AgentSetupScreen({
    super.key,
    required this.service,
    required this.config,
    required this.actions,
    required this.channels,
  });
  @override
  State<AgentSetupScreen> createState() => _AgentSetupScreenState();
}

class _AgentSetupScreenState extends State<AgentSetupScreen> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _values = _map(
    jsonDecode(jsonEncode(widget.config)),
  );
  late final List<Map<String, dynamic>> _steps = _maps(_values['steps']);
  late Map<String, dynamic> _trigger = _map(_values['trigger_config']);
  String? _error;
  String _request = SocialPostService.requestId();
  bool _busy = false;
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.call(
        'save_agent',
        requestId: _request,
        values: {'record_id': ?_values['id']},
        inputs: {
          'name': _values['name'],
          'description': _values['description'],
          'trigger_type': _values['trigger_type'] ?? 'schedule',
          'trigger_config': _trigger,
          'steps': _steps,
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (error is ApiFailure &&
          error.status >= 400 &&
          error.status < 500 &&
          ![408, 409, 429].contains(error.status)) {
        _request = SocialPostService.requestId();
      }
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
      appBar: AppBar(
        title: Text(
          appTr(_values['id'] == null ? 'Set up agent' : 'Configure agent'),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(20),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  appTr(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextFormField(
                      initialValue: '${_values['name'] ?? ''}',
                      decoration: InputDecoration(
                        labelText: appTr('Agent name'),
                      ),
                      maxLength: 255,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? appTr('Enter an agent name.')
                          : null,
                      onSaved: (value) => _values['name'] = value!.trim(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      initialValue: '${_values['description'] ?? ''}',
                      decoration: InputDecoration(
                        labelText: appTr('Description'),
                      ),
                      maxLines: 3,
                      onSaved: (value) => _values['description'] = value,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: '${_values['trigger_type'] ?? 'schedule'}',
                      isExpanded: true,
                      decoration: InputDecoration(labelText: appTr('Trigger')),
                      items: [
                        for (final value in [
                          'schedule',
                          'channel_message',
                          'webhook',
                        ])
                          DropdownMenuItem(
                            value: value,
                            child: Text(appTr(_label(value))),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                              _values['trigger_type'] = value;
                              _trigger = value == 'schedule'
                                  ? {'cron': '0 9 * * *'}
                                  : value == 'channel_message'
                                  ? {'channel_id': null, 'keyword_pattern': ''}
                                  : {};
                            }),
                    ),
                    const SizedBox(height: 16),
                    if ((_values['trigger_type'] ?? 'schedule') == 'schedule')
                      TextFormField(
                        key: const ValueKey('cron'),
                        initialValue: '${_trigger['cron'] ?? '0 9 * * *'}',
                        decoration: InputDecoration(
                          labelText: appTr('Schedule (cron)'),
                          helperText: appTr(
                            'Example: 0 9 * * * runs every day at 09:00 server time.',
                          ),
                        ),
                        validator: (value) =>
                            (value ?? '').trim().split(RegExp(r'\s+')).length !=
                                5
                            ? appTr('Enter a five-part cron schedule.')
                            : null,
                        onChanged: (value) => _trigger['cron'] = value,
                      ),
                    if (_values['trigger_type'] == 'channel_message') ...[
                      DropdownButtonFormField<String>(
                        initialValue:
                            widget.channels.any(
                              (row) =>
                                  '${row['id']}' == '${_trigger['channel_id']}',
                            )
                            ? '${_trigger['channel_id']}'
                            : '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: appTr('Channel'),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(appTr('Any connected channel')),
                          ),
                          for (final row in widget.channels)
                            DropdownMenuItem(
                              value: '${row['id']}',
                              child: Text(
                                '${row['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) =>
                            _trigger['channel_id'] = int.tryParse('$value'),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        initialValue: '${_trigger['keyword_pattern'] ?? ''}',
                        decoration: InputDecoration(
                          labelText: appTr('Keyword pattern (optional)'),
                        ),
                        onChanged: (value) =>
                            _trigger['keyword_pattern'] = value,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              appTr('Workflow steps'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            for (final (index, step) in _steps.indexed)
              Card(
                key: ObjectKey(step),
                child: ExpansionTile(
                  title: Text(
                    '${index + 1}. ${_label('${step['action'] ?? step['type'] ?? 'Action'}')}',
                  ),
                  trailing: IconButton(
                    tooltip: appTr('Remove step'),
                    onPressed: _busy
                        ? null
                        : () => setState(() => _steps.removeAt(index)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: NativeConfigFields(
                        value: _map(step['config']),
                        schema: _map(
                          [
                                for (final group in widget.actions.values)
                                  ..._maps(group),
                              ]
                              .where((action) => action['key'] == step['type'])
                              .firstOrNull?['config_schema'],
                        ),
                        onChanged: (value) => step['config'] = value,
                      ),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final actions = [
                        for (final list in widget.actions.values)
                          ..._maps(list),
                      ];
                      final selected =
                          await showModalBottomSheet<Map<String, dynamic>>(
                            context: context,
                            isScrollControlled: true,
                            builder: (context) {
                              AppLocalizations.watch(context);
                              return SafeArea(
                                child: SizedBox(
                                  height:
                                      MediaQuery.sizeOf(context).height * .65,
                                  child: ListView(
                                    padding: const EdgeInsets.all(20),
                                    children: [
                                      Text(
                                        appTr('Add action'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge,
                                      ),
                                      for (final action in actions)
                                        ListTile(
                                          title: Text(
                                            appTr((action['label']).toString()),
                                          ),
                                          subtitle: Text(
                                            appTr(
                                              (action['description'] ?? '')
                                                  .toString(),
                                            ),
                                          ),
                                          onTap: () =>
                                              Navigator.pop(context, action),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                      if (selected != null && mounted) {
                        setState(
                          () => _steps.add({
                            'type': selected['key'],
                            'app': selected['category'],
                            'action': selected['key'],
                            'config': _schemaDefault(
                              _map(selected['config_schema']),
                            ),
                            'order': _steps.length,
                          }),
                        );
                      }
                    },
              icon: const Icon(Icons.add),
              label: Text(appTr('Add step')),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(appTr('Save agent')),
            ),
          ],
        ),
      ),
    );
  }
}

class NativeConfigFields extends StatefulWidget {
  final Map<String, dynamic> value, schema;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const NativeConfigFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.schema = const {},
  });
  @override
  State<NativeConfigFields> createState() => _NativeConfigFieldsState();
}

class _NativeConfigFieldsState extends State<NativeConfigFields> {
  late final Map<String, dynamic> _values = widget.value;
  Widget _editor(
    String name,
    dynamic current,
    Map<String, dynamic> schema,
    ValueChanged<dynamic> change,
  ) {
    if (current is Map) {
      return ExpansionTile(
        title: Text(appTr(_label(name))),
        children: [
          NativeConfigFields(
            value: _map(current),
            schema: schema,
            onChanged: change,
          ),
        ],
      );
    }
    if (current is List) {
      return ExpansionTile(
        title: Text(appTr(_label(name))),
        children: [
          for (var i = 0; i < current.length; i++)
            Padding(
              key: ValueKey('$name-$i-${identityHashCode(current[i])}'),
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _editor(
                    '${name}_${i + 1}',
                    current[i],
                    _map(schema['items']),
                    (value) {
                      current[i] = value;
                      change(current);
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: appTr('Remove item'),
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        setState(() => current.removeAt(i));
                        change(current);
                      },
                    ),
                  ),
                ],
              ),
            ),
          TextButton.icon(
            onPressed: () {
              setState(
                () => current.add(
                  schema['items'] is Map
                      ? _schemaDefault(_map(schema['items']))
                      : current.isNotEmpty && current.first is Map
                      ? jsonDecode(jsonEncode(current.first))
                      : '',
                ),
              );
              change(current);
            },
            icon: const Icon(Icons.add),
            label: Text(appTr('Add item')),
          ),
        ],
      );
    }
    if (current is bool) {
      return SwitchListTile(
        title: Text(appTr(_label(name))),
        value: current,
        onChanged: (next) {
          change(next);
          setState(() {});
        },
      );
    }
    final choices = schema['enum'] as List? ?? [];
    if (choices.isNotEmpty && choices.contains(current)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: DropdownButtonFormField<String>(
          initialValue: '$current',
          isExpanded: true,
          decoration: InputDecoration(labelText: appTr(_label(name))),
          items: [
            for (final choice in choices)
              DropdownMenuItem(
                value: '$choice',
                child: Text(appTr(_label('$choice'))),
              ),
          ],
          onChanged: change,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        initialValue: current == null ? '' : '$current',
        decoration: InputDecoration(
          labelText: appTr(_label(name)),
          alignLabelWithHint: true,
          helperText: schema['description'] == null
              ? null
              : appTr(schema['description'].toString()),
        ),
        minLines: 1,
        maxLines: current is num ? 1 : 5,
        keyboardType: current is num
            ? TextInputType.number
            : TextInputType.multiline,
        onChanged: (text) =>
            change(current is num ? num.tryParse(text) ?? text : text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in _values.entries)
          _editor(
            entry.key,
            entry.value,
            _map(_map(widget.schema['properties'])[entry.key]),
            (next) {
              _values[entry.key] = next;
              widget.onChanged(_values);
            },
          ),
      ],
    );
  }
}
