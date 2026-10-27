import '../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../services/mobile_api.dart';
import '../services/native_extension_service.dart';
import 'native_module_screen.dart';
import 'server_screen.dart';

class NativeProjectsScreen extends StatefulWidget {
  final MobileApi api;
  final Map<String, dynamic> module;
  const NativeProjectsScreen({
    super.key,
    required this.api,
    required this.module,
  });
  @override
  State<NativeProjectsScreen> createState() => _NativeProjectsScreenState();
}

class _NativeProjectsScreenState extends State<NativeProjectsScreen> {
  late final _service = NativeExtensionService(
    widget.api,
    '${widget.module['id']}',
  );
  Map? _data;
  String? _error;
  bool _busy = false;
  int _epoch = 0;
  final _search = TextEditingController();
  List<Map> get _records =>
      (_data?['data'] as List? ?? []).whereType<Map>().toList();
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _service.call(
        'load',
        values: {
          'query': _search.text.trim(),
          'page': more
              ? (int.tryParse('${_data?['current_page']}') ?? 1) + 1
              : 1,
        },
      );
      if (!mounted || epoch != _epoch) return;
      setState(() {
        if (more) {
          data['data'] = [..._records, ...((data['data'] as List?) ?? [])];
        }
        _data = data;
      });
    } catch (error) {
      if (mounted && epoch == _epoch) setState(() => _error = error.toString());
    } finally {
      if (mounted && epoch == _epoch) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final fields = <Map<String, dynamic>>[
      {'name': 'name', 'label': 'Project name', 'required': true},
      {'name': 'description', 'label': 'Description', 'type': 'textarea'},
      {
        'name': 'status',
        'label': 'Status',
        'type': 'select',
        'value': 'not_started',
        'options': [
          for (final entry in {
            'not_started': 'Not Started',
            'in_progress': 'In Progress',
            'on_hold': 'On Hold',
            'completed': 'Completed',
            'cancelled': 'Cancelled',
          }.entries)
            {'value': entry.key, 'label': entry.value},
        ],
      },
      {
        'name': 'priority',
        'label': 'Priority',
        'type': 'select',
        'value': 'medium',
        'options': [
          for (final value in ['low', 'medium', 'high', 'urgent'])
            {'value': value, 'label': value},
        ],
      },
      {'name': 'due_date', 'label': 'Due date', 'type': 'date'},
      {'name': 'budget', 'label': 'Budget', 'type': 'number'},
      {'name': 'currency', 'label': 'Currency', 'value': 'USD'},
      {
        'name': 'crm_contact_id',
        'label': 'Contact',
        'type': 'select',
        'options': _data?['contacts'] ?? [],
      },
      {
        'name': 'crm_company_id',
        'label': 'Company',
        'type': 'select',
        'options': _data?['companies'] ?? [],
      },
    ];
    final saved = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return _ProjectForm(service: _service, fields: fields);
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(Map record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppLocalizations.watch(context);
        return AlertDialog(
          title: Text(appTr('Delete project?')),
          content: Text('${record['name']}'),
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
    setState(() => _busy = true);
    try {
      await _service.call(
        'delete_project',
        values: {'record_id': record['id']},
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : RetryPanel(message: appTr(_error!), retry: _load);
    }
    final metrics = (_data!['metrics'] as List? ?? [])
        .whereType<Map>()
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              AppLocalizations.watch(context);
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final metric in metrics)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${metric['value'] ?? 0}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(appTr((metric['label']).toString())),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.add),
            label: Text(appTr('New Project')),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: appTr('Search projects'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.search),
                tooltip: appTr('Search projects'),
              ),
            ),
            onSubmitted: (_) => _load(),
          ),
          const SizedBox(height: 16),
          Text(
            appTr('Projects List'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) RetryPanel(message: appTr(_error!), retry: _load),
          if (_records.isEmpty && !_busy)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    const Icon(Icons.folder_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(appTr('No projects yet')),
                    TextButton(
                      onPressed: _create,
                      child: Text(appTr('Create your first project')),
                    ),
                  ],
                ),
              ),
            ),
          for (final record in _records)
            Card(
              child: ListTile(
                isThreeLine: true,
                title: Text('${record['name']}'),
                subtitle: Text(
                  appTr(
                    '${record['company'] ?? record['contact'] ?? ''}\n${'${record['status'] ?? 'not_started'}'.replaceAll('_', ' ')}${record['due_date'] == null ? '' : ' • Due ${record['due_date']}'}',
                  ),
                ),
                trailing: IconButton(
                  tooltip: appTr('Delete project'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _busy ? null : () => _delete(record),
                ),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  useSafeArea: true,
                  isScrollControlled: true,
                  builder: (context) {
                    AppLocalizations.watch(context);
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${record['name']}',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            appTr(
                              (record['description'] ?? 'No description')
                                  .toString(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${record['currency'] ?? 'USD'} ${record['budget'] ?? 0}',
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          if ((int.tryParse('${_data!['current_page']}') ?? 1) <
              (int.tryParse('${_data!['last_page']}') ?? 1))
            TextButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: Text(appTr('Load more projects')),
            ),
        ],
      ),
    );
  }
}

class _ProjectForm extends StatefulWidget {
  final NativeExtensionService service;
  final List<Map<String, dynamic>> fields;
  const _ProjectForm({required this.service, required this.fields});
  @override
  State<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<_ProjectForm> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(appTr('New Project'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_error != null)
            Text(
              appTr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          NativeSchemaForm(
            definition: {'title': 'Save project', 'fields': widget.fields},
            busy: _busy,
            submit: (inputs, files) async {
              setState(() => _busy = true);
              try {
                await widget.service.call(
                  'save_project',
                  inputs: {
                    for (final entry in inputs.entries)
                      if (entry.value.isNotEmpty) entry.key: entry.value,
                  },
                );
                if (mounted) Navigator.pop(this.context, true);
              } catch (error) {
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
