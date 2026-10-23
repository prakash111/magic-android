import 'package:flutter/material.dart';

import '../services/mobile_api.dart';
import 'server_screen.dart';
import 'workspace_screen.dart' show SocialAccountsScreen;

class NativeAutomationScreen extends StatefulWidget {
  final MobileApi api;
  const NativeAutomationScreen({super.key, required this.api});
  @override
  State<NativeAutomationScreen> createState() => _NativeAutomationScreenState();
}

class _NativeAutomationScreenState extends State<NativeAutomationScreen> {
  List<Map>? _items;
  List<Map> _accounts = [];
  String? _error;
  bool _busy = false;
  int _page = 1, _lastPage = 1;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    try {
      final data = await widget.api.request(
        '/native/automations?page=${more ? _page + 1 : 1}',
      ) as Map;
      if (mounted) {
        setState(() {
          final rows = (data['data'] as List).whereType<Map>().toList();
          _items = more ? [...?_items, ...rows] : rows;
          _accounts = (data['accounts'] as List).whereType<Map>().toList();
          _page = data['current_page'] as int;
          _lastPage = data['last_page'] as int;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _edit([Map? item]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AutomationEditor(
          api: widget.api,
          accounts: _accounts,
          automation: item,
        ),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _action(Map item, {bool delete = false}) async {
    final enabling = item['status'] != 'live';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          delete
              ? 'Delete automation?'
              : enabling
              ? 'Activate automation?'
              : 'Pause automation?',
        ),
        content: Text(
          delete
              ? 'This workflow will be removed.'
              : enabling
              ? 'Matching social comments can trigger messages and public replies using this workflow.'
              : 'New comments will no longer trigger this workflow.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.api.request(
        '/native/automations/${item['id']}${delete ? '' : '/status'}',
        method: delete ? 'DELETE' : 'PATCH',
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
    if (_items == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : RetryPanel(message: _error!, retry: _load);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Conversations that keep moving.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Create comment triggers, direct messages and public replies. New workflows start as drafts.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || _accounts.isEmpty ? null : () => _edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Create automation'),
                ),
              ),
              IconButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SocialAccountsScreen(),
                    ),
                  );
                  await _load();
                },
                icon: const Icon(Icons.hub_outlined),
                tooltip: 'Connect accounts',
              ),
            ],
          ),
          if (_accounts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Connect a supported social account to create an automation.',
              ),
            ),
          if (_error != null) Text(_error!),
          if (_busy) const LinearProgressIndicator(),
          for (final item in _items!)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.bolt_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '${item['name']}',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Chip(label: Text('${item['status']}')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${item['trigger_target'] == 'all_posts' ? 'All posts' : 'Selected post'} · ${item['keyword_mode'] == 'any' ? 'Any comment' : (item['include_keywords'] as List? ?? []).join(', ')}',
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final action
                            in (item['actions'] as List? ?? [])
                                .whereType<Map>())
                          Chip(label: Text('${action['type']}')),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _busy ? null : () => _edit(item),
                          child: const Text('Edit'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _action(item),
                          child: Text(
                            item['status'] == 'live' ? 'Pause' : 'Activate',
                          ),
                        ),
                        IconButton(
                          onPressed: _busy
                              ? null
                              : () => _action(item, delete: true),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          if (_items!.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text('Your automations will appear here.'),
            ),
          if (_page < _lastPage)
            TextButton(
              onPressed: () => _load(more: true),
              child: const Text('Load more'),
            ),
        ],
      ),
    );
  }
}

class _AutomationEditor extends StatefulWidget {
  final MobileApi api;
  final List<Map> accounts;
  final Map? automation;
  const _AutomationEditor({
    required this.api,
    required this.accounts,
    this.automation,
  });
  @override
  State<_AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<_AutomationEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _keywords,
      _excluded,
      _post,
      _reply,
      _delay;
  late String? _account;
  late String _target, _keywordMode;
  late bool _publicReplies;
  late List<Map<String, dynamic>> _actions;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final item = widget.automation;
    _name = TextEditingController(text: '${item?['name'] ?? ''}');
    _keywords = TextEditingController(
      text: (item?['include_keywords'] as List? ?? []).join(', '),
    );
    _excluded = TextEditingController(
      text: (item?['exclude_keywords'] as List? ?? []).join(', '),
    );
    _post = TextEditingController(text: '${item?['trigger_post_id'] ?? ''}');
    _reply = TextEditingController(
      text: (item?['replies'] as List? ?? [])
          .whereType<Map>()
          .map((reply) => '${reply['content']}')
          .join('\n'),
    );
    _delay = TextEditingController(text: '${item?['delay_seconds'] ?? 0}');
    final account =
        '${item?['social_media_platform_id'] ?? widget.accounts.firstOrNull?['id'] ?? ''}';
    _account = widget.accounts.any((a) => '${a['id']}' == account)
        ? account
        : null;
    _target = '${item?['trigger_target'] ?? 'all_posts'}';
    _keywordMode = '${item?['keyword_mode'] ?? 'any'}';
    _publicReplies = item?['enable_public_replies'] == true;
    _actions =
        (item?['actions'] as List? ??
                [
                  {
                    'type': 'text',
                    'content': {'text': ''},
                  },
                ])
            .whereType<Map>()
            .map(
              (action) => {
                'type': action['type'],
                'content': Map<String, dynamic>.from(action['content'] as Map),
              },
            )
            .toList();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _keywords,
      _excluded,
      _post,
      _reply,
      _delay,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _split(String text) => text
      .split(',')
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.request(
        '/native/automations${widget.automation == null ? '' : '/${widget.automation!['id']}'}',
        method: widget.automation == null ? 'POST' : 'PUT',
        body: {
          'name': _name.text.trim(),
          'social_media_platform_id': int.parse(_account!),
          'trigger_target': _target,
          'trigger_post_id': _target == 'specific_post'
              ? _post.text.trim()
              : null,
          'keyword_mode': _keywordMode,
          'include_keywords': _split(_keywords.text),
          'exclude_keywords': _split(_excluded.text),
          'enable_public_replies': _publicReplies,
          'delay_seconds': int.parse(_delay.text),
          'actions': _actions,
          'replies': _publicReplies
              ? _reply.text
                    .split('\n')
                    .where((line) => line.trim().isNotEmpty)
                    .map((line) => {'content': line.trim()})
                    .toList()
              : [],
        },
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error.toString();
        });
      }
    }
  }

  Widget _actionField(
    Map<String, dynamic> action,
    String field,
    String label, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      key: ValueKey('${identityHashCode(action)}:$field'),
      initialValue: '${action['content'][field] ?? ''}',
      maxLines: number ? 1 : 3,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label),
      validator: (value) => value == null || value.trim().isEmpty
          ? 'Required'
          : number &&
                (int.tryParse(value) == null ||
                    int.parse(value) < 0 ||
                    int.parse(value) > 300)
          ? 'Use 0–300 seconds'
          : null,
      onSaved: (value) =>
          action['content'][field] = number ? int.parse(value!) : value!.trim(),
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.automation == null ? 'New automation' : 'Edit automation',
      ),
    ),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Workflow name'),
            validator: (value) =>
                value?.trim().isEmpty ?? true ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _account,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Connected account'),
            items: widget.accounts
                .map(
                  (account) => DropdownMenuItem(
                    value: '${account['id']}',
                    child: Text(
                      '${account['platform']} · ${account['name']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _account = value),
            validator: (value) =>
                value == null ? 'Connect and select an account' : null,
          ),
          const SizedBox(height: 14),
          if (_account != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Text(
                '${widget.accounts.firstWhere((a) => '${a['id']}' == _account)['permissions']?['notes'] ?? ''}',
              ),
            ),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _target,
            decoration: const InputDecoration(labelText: 'Trigger'),
            items: const [
              DropdownMenuItem(
                value: 'all_posts',
                child: Text('Comments on all posts'),
              ),
              DropdownMenuItem(
                value: 'specific_post',
                child: Text('Comments on a specific post'),
              ),
            ],
            onChanged: (value) => setState(() => _target = value!),
          ),
          const SizedBox(height: 14),
          if (_target == 'specific_post')
            TextFormField(
              controller: _post,
              decoration: const InputDecoration(labelText: 'Platform post ID'),
              validator: (value) => value?.trim().isEmpty ?? true
                  ? 'Enter the platform post ID'
                  : null,
            ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _keywordMode,
            decoration: const InputDecoration(labelText: 'Comment matching'),
            items: const [
              DropdownMenuItem(value: 'any', child: Text('Any comment')),
              DropdownMenuItem(
                value: 'specific',
                child: Text('Specific keywords'),
              ),
            ],
            onChanged: (value) => setState(() => _keywordMode = value!),
          ),
          const SizedBox(height: 14),
          if (_keywordMode == 'specific')
            TextFormField(
              controller: _keywords,
              decoration: const InputDecoration(
                labelText: 'Keywords, separated by commas',
              ),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Add a keyword' : null,
            ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _excluded,
            decoration: const InputDecoration(
              labelText: 'Exclude keywords (optional)',
            ),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _delay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Initial delay (seconds)',
            ),
            validator: (value) =>
                int.tryParse(value ?? '') == null ||
                    int.parse(value!) < 0 ||
                    int.parse(value) > 300
                ? 'Use 0–300 seconds'
                : null,
          ),
          const SizedBox(height: 20),
          Text(
            'Message sequence',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          for (var i = 0; i < _actions.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Step ${i + 1} · ${_actions[i]['type']}'),
                        ),
                        if (i > 0)
                          IconButton(
                            onPressed: () => setState(() {
                              final action = _actions.removeAt(i);
                              _actions.insert(i - 1, action);
                            }),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                        IconButton(
                          onPressed: () => setState(() => _actions.removeAt(i)),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    if (_actions[i]['type'] == 'text')
                      _actionField(
                        _actions[i],
                        'text',
                        'Message · supports {first_name}',
                      ),
                    if (_actions[i]['type'] == 'button') ...[
                      _actionField(_actions[i], 'label', 'Button label'),
                      _actionField(_actions[i], 'url', 'HTTPS URL'),
                    ],
                    if (_actions[i]['type'] == 'image')
                      _actionField(_actions[i], 'url', 'Image HTTPS URL'),
                    if (_actions[i]['type'] == 'delay')
                      _actionField(
                        _actions[i],
                        'seconds',
                        'Wait seconds',
                        number: true,
                      ),
                    if (_actions[i]['type'] == 'quick_replies')
                      TextFormField(
                        key: ValueKey('quick:$i'),
                        initialValue:
                            (_actions[i]['content']['items'] as List? ?? [])
                                .join(', '),
                        decoration: const InputDecoration(
                          labelText: 'Reply choices, separated by commas',
                        ),
                        onSaved: (value) => _actions[i]['content']['items'] =
                            _split(value ?? ''),
                      ),
                  ],
                ),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              for (final type in [
                'text',
                'button',
                'image',
                'delay',
                'quick_replies',
              ])
                ActionChip(
                  label: Text('+ $type'),
                  onPressed: _actions.length >= 20
                      ? null
                      : () => setState(
                          () => _actions.add({
                            'type': type,
                            'content': <String, dynamic>{},
                          }),
                        ),
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('Public comment replies'),
            value: _publicReplies,
            onChanged: (value) => setState(() => _publicReplies = value),
          ),
          if (_publicReplies)
            TextFormField(
              controller: _reply,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reply variations · one per line',
              ),
              validator: (value) =>
                  value?.trim().isEmpty ?? true ? 'Add a reply' : null,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(_error!),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving || _actions.isEmpty ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save workflow'),
          ),
        ],
      ),
    ),
  );
}
