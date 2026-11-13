import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/image_attachment_picker.dart';
import '../services/mobile_api.dart';
import '../services/native_extension_service.dart';

List<Map<String, dynamic>> _rows(dynamic value) => value is List
    ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
    : [];

class BoundToolWorkspaceScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const BoundToolWorkspaceScreen({
    super.key,
    required this.module,
    required this.api,
  });

  static bool supports(Map<String, dynamic> module) {
    final kind = '${module['route_type']}';
    final id = '${module['id']}'.replaceFirst('web:', '');
    final route = '${module['route']}';
    return [
          'marketing_contacts',
          'marketing_contact_lists',
          'marketing_segments',
          'marketing_campaigns',
          'ai_music',
        ].contains(kind) ||
        [
          'marketing_bot_whatsapp',
          'marketing_bot_whatsapp_contact',
          'marketing_bot_whatsapp_contact_list',
          'marketing_bot_whatsapp_segment',
          'marketing_bot_campaigns',
          'marketing_bot_campaigns_whatsapp',
          'marketing_bot_campaigns_telegram',
          'ai_music',
          'ext_ai_music_pro',
        ].contains(id) ||
        RegExp(
          r'^dashboard\.user\.(ai-music(-pro)?\.|marketing-bot\.(contact|contact-list|segment|whatsapp-campaign|telegram-campaign)\.)',
        ).hasMatch(route);
  }

  @override
  State<BoundToolWorkspaceScreen> createState() =>
      _BoundToolWorkspaceScreenState();
}

class _BoundToolWorkspaceScreenState extends State<BoundToolWorkspaceScreen> {
  late final service = NativeExtensionService(
    widget.api,
    '${widget.module['id']}',
  );
  final search = TextEditingController();
  Map<String, dynamic>? data;
  bool loading = true;
  String? error;
  int generation = 0;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({int page = 1}) async {
    final request = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await service.call(
        'load',
        values: {'page': page, 'query': search.text},
      );
      if (mounted && generation == request) setState(() => data = result);
    } catch (e) {
      if (mounted && generation == request) setState(() => error = '$e');
    } finally {
      if (mounted && generation == request) setState(() => loading = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _WorkspaceForm(
          service: service,
          fields: _rows(data?['fields']),
          workspace: '${data?['workspace']}',
          row: row,
        ),
        fullscreenDialog: true,
      ),
    );
    if (changed == true && mounted) await load();
  }

  Future<void> delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appTr('Delete')),
        content: Text('${row['title']}'),
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
      ),
    );
    if (confirmed != true) return;
    try {
      await service.call('bound_delete', values: {'record_id': row['id']});
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final music = '${data?['workspace']}'.startsWith('music');
    final items = _rows(data?['data']);
    return Column(
      children: [
        if (loading) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: search,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        labelText: appTr('Search'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onSubmitted: (_) => load(),
                    ),
                  ),
                  IconButton(
                    tooltip: appTr('Refresh'),
                    onPressed: loading ? null : load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: data == null || loading ? null : edit,
                  icon: Icon(music ? Icons.music_note : Icons.add),
                  label: Text(appTr(music ? 'Generate Music' : 'Create')),
                ),
              ),
            ],
          ),
        ),
        if (data?['import_supported'] == true)
          TextButton.icon(
            onPressed: loading
                ? null
                : () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => _ContactImport(
                          service: service,
                          contacts: _rows(data?['import_contacts']),
                          segments: _rows(data?['import_segments']),
                        ),
                      ),
                    );
                    if (changed == true && mounted) await load();
                  },
            icon: const Icon(Icons.upload_file),
            label: Text(appTr('Import CSV')),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  appTr(error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                TextButton(onPressed: load, child: Text(appTr('Retry'))),
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (!loading && data != null && items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(appTr('No records yet.')),
                  ),
                for (final row in items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${row['title']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                              ),
                              if (!music)
                                IconButton(
                                  tooltip: appTr('Edit'),
                                  onPressed: () => edit(row),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                              IconButton(
                                tooltip: appTr('Delete'),
                                onPressed: () => delete(row),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                          if (row['content'] != null)
                            Text(
                              '${row['content']}',
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (row['status'] != null)
                            Text(appTr('${row['status']}')),
                          if ('${row['audio_url'] ?? ''}'.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => SecureStore.invokeMethod<void>(
                                'openUrl',
                                {'url': row['audio_url']},
                              ),
                              icon: const Icon(Icons.play_arrow),
                              label: Text(appTr('Play audio')),
                            ),
                        ],
                      ),
                    ),
                  ),
                if ((int.tryParse('${data?['last_page']}') ?? 1) > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: loading || (data?['current_page'] ?? 1) <= 1
                            ? null
                            : () => load(page: data!['current_page'] - 1),
                        child: Text(appTr('Previous')),
                      ),
                      Text('${data?['current_page']} / ${data?['last_page']}'),
                      TextButton(
                        onPressed:
                            loading ||
                                data!['current_page'] >= data!['last_page']
                            ? null
                            : () => load(page: data!['current_page'] + 1),
                        child: Text(appTr('Next')),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkspaceForm extends StatefulWidget {
  final NativeExtensionService service;
  final List<Map<String, dynamic>> fields;
  final String workspace;
  final Map<String, dynamic>? row;
  const _WorkspaceForm({
    required this.service,
    required this.fields,
    required this.workspace,
    this.row,
  });
  @override
  State<_WorkspaceForm> createState() => _WorkspaceFormState();
}

class _WorkspaceFormState extends State<_WorkspaceForm> {
  final form = GlobalKey<FormState>();
  final values = <String, dynamic>{};
  final controllers = <String, TextEditingController>{};
  final files = <String, dynamic>{};
  bool busy = false;
  String? error;
  bool get music => widget.workspace.startsWith('music');

  @override
  void initState() {
    super.initState();
    final saved = widget.row?['values'] is Map
        ? Map<String, dynamic>.from(widget.row!['values'])
        : <String, dynamic>{};
    for (final field in widget.fields) {
      final name = '${field['name']}';
      final value = saved[name] ?? field['default'];
      if (field['type'] == 'checkbox') {
        values[name] = value == true || value == 1 || value == '1';
      } else if (field['type'] == 'multiselect') {
        values[name] = value is List ? List<dynamic>.from(value) : <dynamic>[];
      } else if (![
        'audio',
        'images',
        'campaign_image',
        'select',
      ].contains(field['type'])) {
        controllers[name] = TextEditingController(
          text: value is List ? value.join('\n') : '${value ?? ''}',
        );
      } else if (value != null) {
        values[name] = value;
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> perform(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick(Map<String, dynamic> field) => perform(() async {
    final name = '${field['name']}';
    final type = field['type'];
    Map<String, dynamic>? selected;
    if (type == 'audio') {
      selected = await SecureStore.invokeMapMethod<String, dynamic>(
        'pickFile',
        {'accept': 'audio/*'},
      );
    } else {
      final file = await ImageAttachmentPicker().pick(
        moduleId: widget.service.moduleId,
        field: name,
        maxBytes: type == 'images' ? 25 * 1024 * 1024 : 8 * 1024 * 1024,
      );
      if (file != null) {
        selected = {'name': file.name, 'bytes': base64Encode(file.bytes)};
      }
    }
    if (selected == null || !mounted) return;
    if (type == 'campaign_image') {
      final result = await widget.service.call(
        'upload_image',
        files: {'upload_image': selected},
      );
      if (mounted) setState(() => values[name] = result['image_path']);
    } else if (type == 'images') {
      final index = List.generate(
        10,
        (i) => i,
      ).firstWhere((i) => !files.containsKey('images_$i'), orElse: () => -1);
      if (index < 0) {
        throw const ApiFailure('Choose up to 10 reference images.');
      }
      setState(() => files['images_$index'] = selected);
    } else {
      setState(() => files[name] = selected);
    }
  });

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    await perform(() async {
      final inputs = <String, dynamic>{...values};
      for (final entry in controllers.entries) {
        final type = widget.fields.firstWhere(
          (f) => f['name'] == entry.key,
        )['type'];
        final text = entry.value.text.trim();
        if (text.isEmpty) {
          inputs.remove(entry.key);
          continue;
        }
        inputs[entry.key] = type == 'lines' ? text.split('\n') : text;
      }
      if (inputs['is_scheduled'] != true) inputs.remove('scheduled_at');
      await widget.service.call(
        'bound_save',
        inputs: inputs,
        files: files,
        values: {if (widget.row != null) 'record_id': widget.row!['id']},
      );
      if (mounted) Navigator.pop(context, true);
    });
  }

  Future<void> templates() => perform(() async {
    final result = await widget.service.call('bound_templates');
    final options = _rows(result['templates']);
    if (!mounted) return;
    if (options.isEmpty) {
      throw const ApiFailure('No approved templates are available.');
    }
    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(appTr('Approved templates')),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option),
              child: Text(
                '${option['name']} (${option['language']})\n${option['body_text']}',
              ),
            ),
        ],
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        controllers['meta_template_name']?.text = '${selected['name']}';
        controllers['meta_template_language']?.text = '${selected['language']}';
      });
    }
  });

  Future<void> generateContent() => perform(() async {
    final prompt = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appTr('Write with AI')),
        content: TextField(
          controller: prompt,
          maxLines: 4,
          decoration: InputDecoration(labelText: appTr('Prompt')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(appTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, prompt.text),
            child: Text(appTr('Generate')),
          ),
        ],
      ),
    );
    if (text == null || text.trim().isEmpty) return;
    final result = await widget.service.call(
      'generate_content',
      inputs: {'prompt': text},
    );
    if (mounted) {
      setState(
        () => controllers['content']?.text = '${result['content'] ?? ''}',
      );
    }
  });

  Widget field(Map<String, dynamic> field) {
    final name = '${field['name']}';
    final label = appTr('${field['label']}');
    final type = field['type'];
    final condition = field['visible_when'];
    if (condition != null && values[condition] != true) {
      return const SizedBox.shrink();
    }
    if (type == 'checkbox') {
      return CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: values[name] == true,
        onChanged: busy
            ? null
            : (v) => setState(() => values[name] = v == true),
      );
    }
    if (type == 'multiselect') {
      final options = _rows(field['options']);
      final selected = values[name] as List;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          if (options.isEmpty) Text(appTr('No records yet.')),
          for (final option in options)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${option['label']}'),
              value: selected.any((v) => '$v' == '${option['value']}'),
              onChanged: busy
                  ? null
                  : (checked) => setState(() {
                      selected.removeWhere((v) => '$v' == '${option['value']}');
                      if (checked == true) selected.add(option['value']);
                    }),
            ),
          FormField<bool>(
            validator: (_) => field['required'] == true && selected.isEmpty
                ? appTr('Choose at least one contact list.')
                : null,
            builder: (state) => state.hasError
                ? Text(
                    state.errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }
    if (type == 'select') {
      return DropdownButtonFormField<String>(
        initialValue: '${values[name] ?? field['default'] ?? ''}',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: _rows(field['options'])
            .map(
              (o) => DropdownMenuItem(
                value: '${o['value']}',
                child: Text(appTr('${o['label']}')),
              ),
            )
            .toList(),
        onChanged: busy ? null : (v) => setState(() => values[name] = v),
      );
    }
    if (['audio', 'images', 'campaign_image'].contains(type)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : () => pick(field),
            icon: const Icon(Icons.upload_file),
            label: Text(label),
          ),
          if (type == 'campaign_image' && values[name] != null)
            InputChip(
              label: Text(appTr('Image attached')),
              onDeleted: busy
                  ? null
                  : () => setState(() => values.remove(name)),
            ),
          for (final entry in files.entries.where(
            (e) =>
                e.key == name ||
                (type == 'images' && e.key.startsWith('images_')),
          ))
            InputChip(
              label: Text(
                '${entry.value['name']}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onDeleted: busy
                  ? null
                  : () => setState(() => files.remove(entry.key)),
            ),
        ],
      );
    }
    final controller = controllers[name]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          enabled: !busy,
          readOnly: type == 'datetime',
          maxLines: ['textarea', 'lines'].contains(type) ? 4 : 1,
          keyboardType: type == 'number'
              ? TextInputType.number
              : TextInputType.text,
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: type == 'datetime' ? const Icon(Icons.schedule) : null,
          ),
          validator: (v) =>
              field['required'] == true && (v ?? '').trim().isEmpty
              ? appTr('This field is required.')
              : null,
          onTap: type == 'datetime'
              ? () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: context,
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 365 * 3)),
                    initialDate: now,
                  );
                  if (date == null || !mounted) return;
                  if (!context.mounted) return;
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (time != null && mounted) {
                    setState(
                      () => controller.text = DateTime(
                        date.year,
                        date.month,
                        date.day,
                        time.hour,
                        time.minute,
                      ).toUtc().toIso8601String(),
                    );
                  }
                }
              : null,
        ),
        if (type == 'template')
          TextButton(
            onPressed: busy ? null : templates,
            child: Text(appTr('Choose approved template')),
          ),
        if (name == 'content')
          TextButton.icon(
            onPressed: busy ? null : generateContent,
            icon: const Icon(Icons.auto_awesome),
            label: Text(appTr('Write with AI')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            appTr(
              music
                  ? 'Generate Music'
                  : widget.row == null
                  ? 'Create'
                  : 'Edit',
            ),
          ),
        ),
        body: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final definition in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: field(definition),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    appTr(error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                ),
                onPressed: busy ? null : save,
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(music ? Icons.music_note : Icons.check),
                label: Text(appTr(music ? 'Generate Music' : 'Save')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactImport extends StatefulWidget {
  final NativeExtensionService service;
  final List<Map<String, dynamic>> contacts, segments;
  const _ContactImport({
    required this.service,
    required this.contacts,
    required this.segments,
  });
  @override
  State<_ContactImport> createState() => _ContactImportState();
}

class _ContactImportState extends State<_ContactImport> {
  Map<String, dynamic>? file, preview;
  List<String> headers = [];
  final mapping = <String, String>{};
  final selected = <String>{};
  String? contact, segment, error;
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pick() => run(() async {
    final selectedFile = await SecureStore.invokeMapMethod<String, dynamic>(
      'pickFile',
      {'accept': '.csv,text/csv,text/plain,application/vnd.ms-excel'},
    );
    if (selectedFile == null) return;
    final result = await widget.service.call(
      'bound_csv_headers',
      files: {'file': selectedFile},
    );
    if (!mounted) return;
    setState(() {
      file = selectedFile;
      headers = (result['headers'] as List).map((v) => '$v').toList();
      preview = null;
      mapping.clear();
      selected.clear();
    });
  });
  Map<String, dynamic> get inputs => {
    'mapping': mapping,
    if (contact != null && contact!.isNotEmpty) 'contact_id': contact,
    if (segment != null && segment!.isNotEmpty) 'segment_id': segment,
  };
  Future<void> review() => run(() async {
    final result = await widget.service.call(
      'bound_csv_preview',
      inputs: inputs,
      files: {'file': file},
    );
    if (mounted) {
      setState(() {
        preview = result;
        selected.clear();
        selected.addAll(_rows(result['valid']).map((v) => '${v['phone']}'));
      });
    }
  });
  Future<void> save() => run(() async {
    await widget.service.call(
      'bound_csv_import',
      inputs: {...inputs, 'include_phones': selected.toList()},
      files: {'file': file},
    );
    if (mounted) Navigator.pop(context, true);
  });
  Widget choice(
    String label,
    String? value,
    List<Map<String, dynamic>> choices,
    ValueChanged<String?> onChanged,
  ) => DropdownButtonFormField<String>(
    key: ValueKey('$label:$value'),
    initialValue: value ?? '',
    isExpanded: true,
    decoration: InputDecoration(labelText: appTr(label)),
    items: [
      DropdownMenuItem(value: '', child: Text(appTr('None'))),
      for (final option in choices)
        DropdownMenuItem(
          value: '${option['value']}',
          child: Text('${option['label']}', overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: busy ? null : onChanged,
  );
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final valid = _rows(preview?['valid']);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(appTr('Import CSV'))),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (busy) const LinearProgressIndicator(),
            OutlinedButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.upload_file),
              label: Text(
                file == null ? appTr('Choose CSV file') : '${file!['name']}',
              ),
            ),
            if (file != null) ...[
              for (final name in ['name', 'phone', 'country_code'])
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: choice(
                    name == 'country_code'
                        ? 'Country calling code column'
                        : name == 'phone'
                        ? 'Phone column'
                        : 'Name column',
                    mapping[name],
                    headers.map((h) => {'value': h, 'label': h}).toList(),
                    (v) => setState(() {
                      if (v == null || v.isEmpty) {
                        mapping.remove(name);
                      } else {
                        mapping[name] = v;
                      }
                      preview = null;
                    }),
                  ),
                ),
              const SizedBox(height: 16),
              choice(
                'Contact list',
                contact,
                widget.contacts,
                (v) => setState(() => contact = v),
              ),
              const SizedBox(height: 16),
              choice(
                'Segment',
                segment,
                widget.segments,
                (v) => setState(() => segment = v),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy ? null : review,
                child: Text(appTr('Preview import')),
              ),
            ],
            if (preview != null) ...[
              for (final row in valid)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${row['name']}'),
                  subtitle: Text('${row['phone']}'),
                  value: selected.contains('${row['phone']}'),
                  onChanged: busy
                      ? null
                      : (checked) => setState(() {
                          if (checked == true) {
                            selected.add('${row['phone']}');
                          } else {
                            selected.remove('${row['phone']}');
                          }
                        }),
                ),
              for (final row in _rows(preview?['invalid']))
                ListTile(
                  leading: const Icon(Icons.warning_amber),
                  title: Text(appTr('${row['reason']}')),
                ),
              FilledButton(
                onPressed: busy || selected.isEmpty ? null : save,
                child: Text('${appTr('Import contacts')} (${selected.length})'),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  appTr(error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
