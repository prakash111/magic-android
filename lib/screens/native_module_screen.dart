import '../services/app_localizations.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../services/mobile_api.dart';
import '../services/image_attachment_picker.dart';
import '../theme/app_theme.dart';
import '../theme/design.dart';
import '../services/workspace_catalog.dart';
import 'native_contacts_screen.dart';
import 'native_extension_screen.dart';
import 'native_chat_tools_screen.dart';
import 'native_automation_screen.dart';
import 'native_creative_screen.dart';
import 'native_projects_screen.dart';
import 'server_screen.dart';
import 'workspace_screen.dart';
import 'extension_workflow_screen.dart';
import 'native_visual_editor.dart';
import 'native_workspace_screen.dart';
import 'native_parity_screen.dart';
import 'schema_components.dart';

class NativeModuleRegistry {
  static Widget build(Map<String, dynamic> module, {MobileApi? api}) {
    final client = api ?? MobileApi.instance;
    return switch (module['route_type']) {
      'ai_agents' ||
      'crm_tasks' ||
      'agent_posts' ||
      'fashion_settings' => NativeParityScreen(module: module, api: client),
      'marketing_settings' ||
      'marketing_dashboard' ||
      'marketing_inbox' ||
      'marketing_campaigns' ||
      'deal_pipeline' ||
      'agent_analytics' ||
      'ugc_studio' ||
      'ugc_creator' => NativeExtensionScreen(module: module, api: client),
      'chat_tools' => NativeChatToolsScreen(module: module, api: client),
      'native_media' || 'extension_workflow' => ExtensionWorkflowScreen(
        module: module,
        api: client,
        endpoint: module['route_type'] == 'native_media'
            ? '/native/media'
            : '/native/workflow',
      ),
      'visual_tool' => NativeVisualEditor(
        api: client,
        moduleId: '${module['id']}',
        kind: '${module['visual_kind']}',
      ),
      'crm_chat' => ServerChatScreen(crm: true, api: client),
      'chat' => ServerChatScreen(api: client),
      'web_chat' => ServerChatScreen(api: client, web: true),
      'contacts' => NativeContactsScreen(api: client),
      'social_automation' => NativeAutomationScreen(api: client),
      'creative_suite' => NativeCreativeScreen(api: client),
      'crm_projects' => NativeProjectsScreen(module: module, api: client),
      'dashboard' => NativeDashboard(module: module, api: client),
      'social_calendar' => ServerSocialScreen(
        api: client,
        calendarInitiallyVisible: '${module['id']}'.contains('calendar'),
      ),
      'social_accounts' => SocialAccountsScreen(api: client, embedded: true),
      'documents' => ServerListScreen(
        path: '/documents',
        title: appTr('Documents'),
        api: client,
      ),
      'tool_directory' => NativeToolDirectory(api: client),
      'server_form' => NativeSchemaScreen(module: module, api: client),
      _ => NativeWorkspaceScreen(module: module, api: client),
    };
  }
}

class NativeModuleScreen extends StatelessWidget {
  final Map<String, dynamic> module;
  final MobileApi? api;
  const NativeModuleScreen({super.key, required this.module, this.api});
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(appTr(workspaceTitle(module)))),
      body: NativeModuleRegistry.build(module, api: api),
    );
  }
}

class NativeDashboard extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const NativeDashboard({super.key, required this.module, required this.api});
  @override
  State<NativeDashboard> createState() => _NativeDashboardState();
}

class _NativeDashboardState extends State<NativeDashboard> {
  Map? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.request(
        '/native/dashboard?module_id=${Uri.encodeQueryComponent(widget.module['id'].toString())}',
      ) as Map;
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

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : RetryPanel(message: appTr(_error!), retry: _load);
    }
    final stats = (_data!['stats'] as List? ?? []).whereType<Map>();
    final chart = (_data!['chart'] as List? ?? []).whereType<Map>().toList();
    double amount(Map point) {
      final value = num.tryParse('${point['value']}') ?? 0;
      return value.isFinite && value > 0 ? value.toDouble() : 0;
    }

    final maxValue = chart.fold<double>(
      1,
      (previous, item) => amount(item) > previous ? amount(item) : previous,
    );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            appTr('Your work, at a glance'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final stat in stats)
                SizedBox(
                  width: (MediaQuery.sizeOf(context).width - 52) / 2,
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${stat['value'] ?? 0}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(appTr((stat['label']).toString())),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            '${_data!['chart_title'] ?? 'Recent activity'}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in chart)
                  Expanded(
                    child: Semantics(
                      label: appTr(":value: :value2", {
                        "value": point['label'],
                        "value2": point['value'],
                      }),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(compactNumber(amount(point))),
                          const SizedBox(height: 6),
                          Container(
                            height: 8 + 105 * amount(point) / maxValue,
                            margin: const EdgeInsets.symmetric(horizontal: 7),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(appTr((point['label']).toString())),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          Text(
            appTr('Quick actions'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          for (final shortcut
              in (_data!['shortcuts'] as List? ?? []).whereType<Map>())
            Card(
              child: ListTile(
                leading: Icon(workspaceIcon('${shortcut['id']}')),
                title: Text(appTr((shortcut['title']).toString())),
                trailing: const Icon(Icons.chevron_right),
                onTap: () =>
                    openModule(context, Map<String, dynamic>.from(shortcut)),
              ),
            ),
          if (_error != null) Text(appTr(_error!)),
        ],
      ),
    );
  }
}

class NativeToolDirectory extends StatefulWidget {
  final MobileApi api;
  const NativeToolDirectory({super.key, required this.api});
  @override
  State<NativeToolDirectory> createState() => _NativeToolDirectoryState();
}

class _NativeToolDirectoryState extends State<NativeToolDirectory> {
  Map? _data;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.request('/config') as Map;
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

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return _data == null
        ? (_error == null
              ? const Center(child: CircularProgressIndicator())
              : RetryPanel(message: appTr(_error!), retry: _load))
        : ToolDirectory(
            tools: (_data!['tools'] as List? ?? [])
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList(),
            credits: Map<String, dynamic>.from(_data!['credits'] as Map? ?? {}),
            dashboard: false,
            refresh: _load,
          );
  }
}

class NativeSchemaScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const NativeSchemaScreen({
    super.key,
    required this.module,
    required this.api,
  });
  @override
  State<NativeSchemaScreen> createState() => _NativeSchemaScreenState();
}

class _NativeSchemaScreenState extends State<NativeSchemaScreen> {
  Map? _data;
  String? _error;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({
    String? action,
    Map<String, String>? inputs,
    Map<String, dynamic>? attachments,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api
          .request(
            '/native/screen',
            method: 'POST',
            body: {
              'module_id': widget.module['id'],
              'action': ?action,
              'inputs': ?inputs,
              'attachments': ?attachments,
            },
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw const ApiFailure(
              'This workspace is taking too long to load. Please retry.',
            ),
          );
      if (data is! Map ||
          data['schema_version'] != 2 ||
          data['components'] is! List) {
        throw const ApiFailure('Update the app to display this screen.');
      }
      if (mounted) {
        setState(() => _data = data);
        if (data['message'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appTr((data['message']).toString()))),
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _follow(Map item) async {
    if (item['confirm'] == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          AppLocalizations.watch(context);
          return AlertDialog(
            title: Text('${item['title']}?'),
            content: Text(appTr('This action will update your account data.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(appTr('Cancel')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(appTr('Continue')),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
    }
    await _load(action: '${item['action']}');
  }

  Widget _component(Map item) => switch (item['type']) {
    'heading' => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        '${item['text']}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
    ),
    'text' => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SelectableText('${item['text']}'),
    ),
    'link' => Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.arrow_outward,
            size: 18,
            color: AppTheme.primary,
          ),
        ),
        title: Text(
          '${item['title']}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: _busy ? null : () => _follow(item),
      ),
    ),
    'form' => NativeSchemaForm(
      key: ValueKey(item['action']),
      definition: item,
      busy: _busy,
      submit: (inputs, attachments) => _load(
        action: '${item['action']}',
        inputs: inputs,
        attachments: attachments,
      ),
    ),
    'table' => Column(
      children: [
        for (final row
            in (item['rows'] is List ? item['rows'] as List : const [])
                .whereType<List>())
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final cell in row.whereType<Map>())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              appTr((cell['label']).toString()),
                              style: const TextStyle(
                                color: AppTheme.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 3,
                            child: Text(
                              '${cell['value']}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    ),
    'stat' => Card(
      child: ListTile(
        title: Text('${item['value']}'),
        subtitle: Text(appTr((item['label']).toString())),
      ),
    ),
    'image' => Image.network(
      '${item['url']}',
      errorBuilder: (localizationContext, error, stack) {
        AppLocalizations.watch(localizationContext);
        return const Icon(Icons.broken_image_outlined);
      },
    ),
    'group' => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final child in (item['children'] as List? ?? []).whereType<Map>())
          _component(child),
      ],
    ),
    _ => Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(appTr('This tool will be available soon.')),
      ),
    ),
  };
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
                onPressed: _busy ? null : () => _load(),
                child: Text(appTr('Reload')),
              ),
            ],
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                if ((_data!['components'] as List? ?? []).isEmpty)
                  const SchemaEmptyState(),
                ...buildStyledComponents(
                  context,
                  (_data!['components'] as List? ?? [])
                      .whereType<Map>()
                      .toList(),
                  _component,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class NativeSchemaForm extends StatefulWidget {
  final Map definition;
  final bool busy;
  final Future<void> Function(Map<String, String>, Map<String, dynamic>) submit;
  const NativeSchemaForm({
    super.key,
    required this.definition,
    required this.busy,
    required this.submit,
  });
  @override
  State<NativeSchemaForm> createState() => _NativeSchemaFormState();
}

class _NativeSchemaFormState extends State<NativeSchemaForm> {
  final _form = GlobalKey<FormState>();
  final _values = <String, String>{};
  final _files = <String, dynamic>{};
  final _visibleSecrets = <String>{};
  String? _error;
  @override
  void initState() {
    super.initState();
    for (final field
        in (widget.definition['fields'] as List? ?? []).whereType<Map>()) {
      if (field['value'] != null) {
        _values['${field['name']}'] = '${field['value']}';
      }
    }
  }

  Future<void> _pick(Map field) async {
    final name = '${field['name']}';
    final accept = '${field['accept'] ?? 'image/*'}';
    try {
      if (accept != 'image/*' && accept != 'video/*') {
        final file = await SecureStore.invokeMapMethod<String, dynamic>(
          'pickFile',
          {'accept': accept},
        );
        if (file != null && mounted) {
          final bytes = (file['bytes'] as List).cast<int>();
          if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
            throw const ApiFailure(
              'Choose a readable file no larger than 10 MB.',
            );
          }
          setState(() {
            _files[name] = {'name': file['name'], 'bytes': base64Encode(bytes)};
            _error = null;
          });
        }
        return;
      }
      final data = await ImageAttachmentPicker().pick(
        moduleId: 'schema',
        field: name,
        video: accept == 'video/*',
        maxBytes: 10 * 1024 * 1024,
      );
      if (data != null && mounted) {
        setState(
          () => _files[name] = {
            'name': data.name,
            'bytes': base64Encode(data.bytes),
          },
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field
                  in (widget.definition['fields'] as List? ?? [])
                      .whereType<Map>())
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: switch (field['type']) {
                    'file' => FormField<void>(
                      validator: (_) =>
                          field[appTr('required')] == true &&
                              !_files.containsKey(field[appTr('name')])
                          ? 'Choose ${field[appTr('label')]}'
                          : null,
                      builder: (state) {
                        AppLocalizations.watch(state.context);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_files[field['name']] != null)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading:
                                    '${field['accept']}'.startsWith('image/')
                                    ? Image.memory(
                                        Uint8List.fromList(
                                          base64Decode(
                                            _files[field['name']]['bytes'],
                                          ),
                                        ),
                                        width: 48,
                                        height: 48,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (localizationContext, e, s) {
                                              AppLocalizations.watch(
                                                localizationContext,
                                              );
                                              return const Icon(
                                                Icons.image_outlined,
                                              );
                                            },
                                      )
                                    : const Icon(Icons.attach_file),
                                title: Text(
                                  '${_files[field['name']]['name']}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: IconButton(
                                  tooltip: appTr('Remove attachment'),
                                  onPressed: widget.busy
                                      ? null
                                      : () => setState(
                                          () => _files.remove(field['name']),
                                        ),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            OutlinedButton.icon(
                              onPressed: widget.busy
                                  ? null
                                  : () => _pick(field),
                              icon: const Icon(Icons.attach_file),
                              label: Text(
                                appTr(
                                  _files.containsKey(field['name'])
                                      ? 'Replace ${field['label']}'
                                      : '${field['label']}',
                                ),
                              ),
                            ),
                            if (state.hasError)
                              Text(
                                appTr(state.errorText!),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    'select' => DropdownButtonFormField<String>(
                      initialValue:
                          (field['options'] as List? ?? [])
                              .whereType<Map>()
                              .any(
                                (option) =>
                                    '${option['value']}' ==
                                    _values[field['name']],
                              )
                          ? _values[field['name']]
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: appTr((field['label']).toString()),
                      ),
                      items: (field['options'] as List? ?? [])
                          .whereType<Map>()
                          .map(
                            (option) => DropdownMenuItem(
                              value: '${option['value']}',
                              child: Text(
                                appTr((option['label']).toString()),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: widget.busy
                          ? null
                          : (value) {
                              if (value != null) {
                                _values['${field['name']}'] = value;
                              }
                            },
                      validator: (value) =>
                          field[appTr('required')] == true &&
                              (value == null || value.isEmpty)
                          ? appTr('Required')
                          : null,
                    ),
                    'date' => FormField<String>(
                      initialValue:
                          _values['${field['name']}'] ??
                          '${field['value'] ?? ''}',
                      validator: (value) =>
                          field[appTr('required')] == true &&
                              (value?.isEmpty ?? true)
                          ? appTr('Required')
                          : null,
                      onSaved: (value) =>
                          _values['${field['name']}'] = value ?? '',
                      builder: (state) {
                        AppLocalizations.watch(state.context);
                        return InkWell(
                          onTap: widget.busy
                              ? null
                              : () async {
                                  final current =
                                      DateTime.tryParse(state.value ?? '') ??
                                      DateTime.now();
                                  final date = await showDatePicker(
                                    context: context,
                                    initialDate: current,
                                    firstDate: DateTime(1900),
                                    lastDate: DateTime(2200),
                                  );
                                  if (date == null || !mounted) return;
                                  final value =
                                      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                                  state.didChange(value);
                                  _values['${field['name']}'] = value;
                                },
                          child: InputDecorator(
                            decoration: InputDecoration(
                              labelText: appTr((field['label']).toString()),
                              errorText: state.errorText == null
                                  ? null
                                  : appTr(state.errorText!),
                              suffixIcon: const Icon(
                                Icons.calendar_today_outlined,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                appTr(
                                  state.value?.isNotEmpty == true
                                      ? state.value!
                                      : 'Choose date',
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    'checkbox' => CheckboxListTile(
                      title: Text(appTr((field['label']).toString())),
                      value: _values[field['name']] == '1',
                      onChanged: widget.busy
                          ? null
                          : (value) => setState(
                              () => _values['${field['name']}'] = value == true
                                  ? '1'
                                  : '0',
                            ),
                    ),
                    _ => TextFormField(
                      initialValue: '${field['value'] ?? ''}',
                      enabled: !widget.busy,
                      maxLines: field['type'] == 'textarea' ? 4 : 1,
                      obscureText:
                          field['type'] == 'secret' &&
                          !_visibleSecrets.contains('${field['name']}'),
                      keyboardType: switch (field['type']) {
                        'email' => TextInputType.emailAddress,
                        'number' => TextInputType.number,
                        _ => TextInputType.text,
                      },
                      decoration: InputDecoration(
                        labelText: appTr((field['label']).toString()),
                        suffixIcon: field['type'] == 'secret'
                            ? IconButton(
                                tooltip: appTr('Show or hide token'),
                                onPressed: () => setState(() {
                                  final name = '${field['name']}';
                                  if (!_visibleSecrets.remove(name)) {
                                    _visibleSecrets.add(name);
                                  }
                                }),
                                icon: Icon(
                                  _visibleSecrets.contains('${field['name']}')
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                              )
                            : null,
                      ),
                      validator: (value) =>
                          field[appTr('required')] == true &&
                              (value?.trim().isEmpty ?? true)
                          ? appTr('Required')
                          : null,
                      onSaved: (value) =>
                          _values['${field['name']}'] = value ?? '',
                    ),
                  },
                ),
              if (_error != null) Text(appTr(_error!)),
              FilledButton(
                onPressed: widget.busy
                    ? null
                    : () async {
                        if (_form.currentState!.validate()) {
                          _form.currentState!.save();
                          await widget.submit(_values, _files);
                        }
                      },
                child: Text(
                  appTr((widget.definition['title'] ?? 'Save').toString()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
