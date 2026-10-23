import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/chat_tools_service.dart';
import '../services/mobile_api.dart';
import '../services/extension_workflow_service.dart';
import '../services/social_post_service.dart';
import 'server_screen.dart';

class NativeChatToolsScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const NativeChatToolsScreen({
    super.key,
    required this.module,
    required this.api,
  });
  @override
  State<NativeChatToolsScreen> createState() => _NativeChatToolsScreenState();
}

class _NativeChatToolsScreenState extends State<NativeChatToolsScreen> {
  late final _service = ChatToolsService(widget.api, '${widget.module['id']}');
  final _search = TextEditingController();
  Map<String, dynamic>? _data;
  int? _bot;
  String? _error;
  bool _busy = false;
  String? _requestId, _lastAction;
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

  Future<void> _load() async {
    try {
      final data = await _service.execute(
        'list',
        id: _bot,
        query: _search.text,
      );
      if (mounted) {
        setState(() {
          _data = data;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _action(
    String operation, {
    int? id,
    int? source,
    Map<String, dynamic> inputs = const {},
    WorkflowFile? file,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final signature = jsonEncode([
      operation,
      id,
      source,
      inputs,
      file?.name,
      file?.bytes.length,
    ]);
    if (_lastAction != signature) {
      _requestId = null;
      _lastAction = signature;
    }
    _requestId ??= SocialPostService.requestId();
    try {
      final data = await _service.execute(
        operation,
        id: operation == 'save' ? id : (id ?? _bot),
        sourceId: source,
        inputs: inputs,
        file: file,
        requestId: _requestId,
      );
      _requestId = null;
      if (mounted) {
        setState(() => _data = data);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Changes saved.')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _form(
    String operation,
    List<(String, String, int)> fields, {
    Map? record,
  }) async {
    final controllers = {
      for (final field in fields)
        field.$1: TextEditingController(text: '${record?[field.$1] ?? ''}'),
    };
    final key = GlobalKey<FormState>();
    final values = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Text(
              operation == 'save'
                  ? 'Save ${_data!['kind'] == 'categories'
                        ? 'category'
                        : _data!['kind'] == 'training'
                        ? 'chatbot'
                        : 'template'}'
                  : 'Add training source',
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: key,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: TextFormField(
                        controller: controllers[field.$1],
                        maxLines: field.$3,
                        decoration: InputDecoration(
                          labelText: field.$2,
                          filled: true,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter ${field.$2.toLowerCase()}.'
                            : null,
                      ),
                    ),
                  FilledButton(
                    onPressed: () {
                      if (key.currentState!.validate()) {
                        Navigator.pop(context, {
                          for (final entry in controllers.entries)
                            entry.key: entry.value.text.trim(),
                        });
                      }
                    },
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Route transitions can retain text fields until their animation completes.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (values != null && mounted) {
      await _action(
        operation,
        id: record?['id'] as int?,
        inputs: operation == 'url' ? {...values, 'type': 'single'} : values,
      );
    }
  }

  Future<void> _upload() async {
    try {
      final result = await SecureStore.invokeMapMethod<String, dynamic>(
        'pickFile',
        {
          'accept': 'application/pdf,text/csv,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        },
      );
      if (result != null) {
        await _action(
          'file',
          file: WorkflowFile(
            '${result['name']}',
            (result['bytes'] as List).cast<int>(),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _confirmDelete(int id, {bool source = false}) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this item?'),
        content: const Text('This removes it from your workspace.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _action(
        'delete',
        id: source ? _bot : id,
        source: source ? id : null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : RetryPanel(message: _error!, retry: _load);
    }
    final kind = '${_data!['kind']}';
    final records = (_data!['data'] as List).whereType<Map>().toList();
    final sources = (_data!['sources'] as List).whereType<Map>().toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              hintText: 'Search ${kind == 'training' ? 'chatbots' : kind}',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: _load,
                icon: const Icon(Icons.arrow_forward),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _form(
                    'save',
                    kind == 'categories'
                        ? [('name', 'Name', 1)]
                        : kind == 'training'
                        ? [('title', 'Chatbot name', 1)]
                        : [
                            ('name', 'Template name', 1),
                            ('role', 'Role', 1),
                            ('description', 'Description', 2),
                            ('instructions', 'Instructions', 5),
                            ('first_message', 'First message', 2),
                          ],
                  ),
            icon: const Icon(Icons.add),
            label: Text(
              'Create ${kind == 'categories'
                  ? 'category'
                  : kind == 'training'
                  ? 'chatbot'
                  : 'template'}',
            ),
          ),
          const SizedBox(height: 16),
          if (records.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.chat_bubble_outline, size: 42),
                    SizedBox(height: 12),
                    Text('Your library is ready for its first item.'),
                  ],
                ),
              ),
            ),
          for (final record in records)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        kind == 'training'
                            ? Icons.psychology_outlined
                            : Icons.chat_outlined,
                      ),
                      title: Text('${record['name'] ?? record['title']}'),
                      subtitle: record['description'] != null
                          ? Text(
                              '${record['description']}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            )
                          : kind == 'training'
                          ? Text('${record['status'] ?? 'Ready'}')
                          : null,
                      trailing: IconButton(
                        tooltip: 'Delete',
                        onPressed: _busy
                            ? null
                            : () => _confirmDelete(record['id'] as int),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                    if (kind == 'categories')
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _form('save', [
                                ('name', 'Name', 1),
                              ], record: record),
                        child: const Text('Edit category'),
                      ),
                    if (kind == 'templates')
                      FilledButton.tonal(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => Scaffold(
                              resizeToAvoidBottomInset: true,
                              appBar: AppBar(title: Text('${record['name']}')),
                              body: ServerChatScreen(
                                api: widget.api,
                                initialPersona: '${record['id']}',
                                initialPrompt:
                                    '${record['first_message'] ?? ''}',
                              ),
                            ),
                          ),
                        ),
                        child: const Text('Use template'),
                      ),
                    if (kind == 'training')
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () {
                                setState(() => _bot = record['id'] as int);
                                _load();
                              },
                        child: Text(
                          _bot == record['id']
                              ? 'Selected for training'
                              : 'Manage knowledge',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (kind == 'training' && _bot != null) ...[
            const SizedBox(height: 24),
            const Text(
              'Knowledge sources',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Text snippet'),
                  onPressed: _busy
                      ? null
                      : () => _form('text', [
                          ('title', 'Title', 1),
                          ('text', 'Text', 6),
                        ]),
                ),
                ActionChip(
                  label: const Text('Question & answer'),
                  onPressed: _busy
                      ? null
                      : () => _form('qa', [
                          ('question', 'Question', 2),
                          ('answer', 'Answer', 5),
                        ]),
                ),
                ActionChip(
                  label: const Text('Website URL'),
                  onPressed: _busy
                      ? null
                      : () => _form('url', [('url', 'Public website URL', 1)]),
                ),
                ActionChip(
                  label: const Text('PDF / spreadsheet'),
                  onPressed: _busy ? null : _upload,
                ),
              ],
            ),
            if (sources.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Add a source, then train your chatbot.'),
              ),
            for (final source in sources)
              Card(
                child: ListTile(
                  title: Text(
                    '${source['type_value']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${source['type']} · ${source['status']}'),
                  trailing: IconButton(
                    tooltip: 'Delete source',
                    onPressed: _busy
                        ? null
                        : () =>
                              _confirmDelete(source['id'] as int, source: true),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ),
            for (final type in ['text', 'qa', 'url', 'pdf'])
              if (sources.any((s) => s['type'] == type))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _action(
                            'train',
                            inputs: {
                              'type': type,
                              'chatbot_data': sources
                                  .where((s) => s['type'] == type)
                                  .map((s) => s['id'])
                                  .toList(),
                            },
                          ),
                    child: Text('Train ${type == 'qa' ? 'Q&A' : type} sources'),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}
