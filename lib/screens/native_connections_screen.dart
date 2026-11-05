import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import 'native_parity_screen.dart' show NativeConfigFields;
import '../services/mobile_api.dart';
import '../services/social_post_service.dart';
import '../services/workspace_service.dart';

class NativeConnectionsScreen extends StatefulWidget {
  final MobileApi api;
  final String moduleId;
  const NativeConnectionsScreen({
    super.key,
    required this.api,
    required this.moduleId,
  });

  @override
  State<NativeConnectionsScreen> createState() =>
      _NativeConnectionsScreenState();
}

class _NativeConnectionsScreenState extends State<NativeConnectionsScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _data;
  int? _chatbotId;
  String? _error;
  bool _loading = true, _busy = false;
  int _generation = 0;
  final Map<String, String> _pendingRequests = {};

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
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  Future<Map<String, dynamic>> _call(
    String operation, [
    Map<String, dynamic> values = const {},
  ]) async {
    final key = jsonEncode([operation, _chatbotId, values]);
    final requestId = operation == 'load'
        ? null
        : _pendingRequests.putIfAbsent(key, SocialPostService.requestId);
    final result = await widget.api
        .request(
          '/native/connections',
          method: 'POST',
          body: {
            'module_id': widget.moduleId,
            'operation': operation,
            'chatbot_id': ?_chatbotId,
            if (operation != 'load') 'request_id': requestId,
            ...values,
          },
        )
        .timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw const ApiFailure(
            'Connection timed out. Refresh the list before retrying.',
          ),
        );
    _pendingRequests.remove(key);
    return Map<String, dynamic>.from(result as Map);
  }

  List<Map> _rows(String key) =>
      (_data?[key] as List? ?? []).whereType<Map>().toList();

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      var data = await _call('load', {'chatbot_id': null});
      if (!mounted || generation != _generation) return;
      final bots = (data['chatbots'] as List? ?? []).whereType<Map>().toList();
      if (data['kind'] == 'chatbot') {
        if (!bots.any((bot) => bot['id'] == _chatbotId)) {
          _chatbotId = bots.isEmpty ? null : bots.first['id'] as int;
        }
        if (_chatbotId != null) {
          data = await _call('load');
        }
      }
      if (mounted && generation == _generation) setState(() => _data = data);
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

  Future<void> _action(String operation, Map<String, dynamic> values) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _call(operation, values);
      if (operation == 'oauth') {
        await WorkspaceService(api: widget.api)
            .openTicket(result, title: appTr('Connect account'));
        if (mounted) await _load();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appTr('${result['message'] ?? 'Saved'}'))),
          );
        }
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect(Map row, {bool connector = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appTr('Disconnect channel?')),
        content: Text(
          appTr('New messages will no longer use this connection.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(appTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(appTr('Disconnect')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _action(connector ? 'disconnect_connector' : 'disconnect', {
        'record_id': row['id'],
      });
    }
  }

  Future<void> _connect(Map provider) async {
    final values = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ChannelConnectionForm(
          provider: Map<String, dynamic>.from(provider),
          requiresName: _data?['kind'] == 'agent',
        ),
      ),
    );
    if (values != null && mounted) {
      await _action('connect', {'provider': provider['id'], ...values});
    }
  }

  Future<void> _editBot({bool create = false}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NativeChatbotEditor(
          api: widget.api,
          moduleId: widget.moduleId,
          chatbotId: create ? null : _chatbotId,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final isChatbot = _data?['kind'] == 'chatbot';
    return Scaffold(
      appBar: AppBar(
        title: Text(appTr('Channels and connectors')),
        actions: [
          IconButton(
            tooltip: appTr('Refresh'),
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading || _busy) const LinearProgressIndicator(),
            if (_error != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(appTr(_error!)),
                      TextButton(
                        onPressed: _busy ? null : _load,
                        child: Text(appTr('Retry')),
                      ),
                    ],
                  ),
                ),
              ),
            if (isChatbot && _rows('chatbots').isNotEmpty)
              DropdownButtonFormField<int>(
                key: ValueKey(_chatbotId),
                initialValue: _chatbotId,
                isExpanded: true,
                decoration: InputDecoration(labelText: appTr('Chatbot')),
                items: [
                  for (final bot in _rows('chatbots'))
                    DropdownMenuItem(
                      value: bot['id'] as int,
                      child: Text('${bot['title']}'),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        _chatbotId = value;
                        _load();
                      },
              ),
            if (isChatbot)
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: _busy || _loading
                        ? null
                        : () => _editBot(create: true),
                    icon: const Icon(Icons.add),
                    label: Text(appTr('Create chatbot')),
                  ),
                  if (_chatbotId != null)
                    TextButton.icon(
                      onPressed: _busy || _loading ? null : _editBot,
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(appTr('Edit chatbot')),
                    ),
                ],
              ),
            const SizedBox(height: 16),
            Text(
              appTr('Connected channels'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (!_loading && _rows('channels').isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  appTr(
                    isChatbot && _rows('chatbots').isEmpty
                        ? 'Create a chatbot before connecting channels.'
                        : 'No connected channels yet.',
                  ),
                ),
              ),
            for (final channel in _rows('channels'))
              Card(
                child: ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: Text('${channel['name']}'),
                  subtitle: Text(
                    '${appTr('${channel['provider']}')} · ${appTr('Configured')}',
                  ),
                  trailing: IconButton(
                    tooltip: appTr('Disconnect'),
                    onPressed: _busy ? null : () => _disconnect(channel),
                    icon: const Icon(Icons.link_off),
                  ),
                  onTap: !isChatbot && !_busy
                      ? () => _action('check', {'record_id': channel['id']})
                      : null,
                ),
              ),
            const SizedBox(height: 16),
            Text(
              appTr('Connect a channel'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (!_loading && _rows('providers').isEmpty)
              Text(
                appTr(
                  'No channel integrations are available in your current plan.',
                ),
              ),
            for (final provider in _rows('providers'))
              Card(
                child: ListTile(
                  leading: const Icon(Icons.add_link),
                  title: Text(_providerName('${provider['id']}')),
                  trailing: const Icon(Icons.chevron_right),
                  enabled:
                      !_busy && !_loading && (!isChatbot || _chatbotId != null),
                  onTap: () => _connect(provider),
                ),
              ),
            if (_data?['kind'] == 'agent') ...[
              const SizedBox(height: 24),
              Text(
                appTr('Manage Connectors'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              for (final connector in _rows('connectors'))
                Card(
                  child: ListTile(
                    title: Text(
                      '${_providerName('${connector['type']}')} #${connector['id']}',
                    ),
                    subtitle: Text(
                      appTr(
                        connector['is_active'] == true
                            ? 'Connected'
                            : 'Reconnect required',
                      ),
                    ),
                    trailing: IconButton(
                      tooltip: appTr('Disconnect'),
                      onPressed: _busy
                          ? null
                          : () => _disconnect(connector, connector: true),
                      icon: const Icon(Icons.link_off),
                    ),
                  ),
                ),
              for (final provider in _data?['oauth_providers'] as List? ?? [])
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _action('oauth', {'provider': provider}),
                    icon: const Icon(Icons.login),
                    label: Text(
                      '${appTr('Connect')} ${_providerName('$provider')}',
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

String _providerName(String name) => switch (name) {
  'telegram' => 'Telegram',
  'whatsapp' => 'WhatsApp',
  'messenger' => 'Messenger',
  'instagram' => 'Instagram',
  'slack' => 'Slack',
  'gmail' => 'Gmail',
  'outlook' => 'Outlook',
  _ => name,
};

class ChannelConnectionForm extends StatefulWidget {
  final Map<String, dynamic> provider;
  final bool requiresName;
  const ChannelConnectionForm({
    super.key,
    required this.provider,
    required this.requiresName,
  });
  @override
  State<ChannelConnectionForm> createState() => _ChannelConnectionFormState();
}

class _ChannelConnectionFormState extends State<ChannelConnectionForm> {
  final _form = GlobalKey<FormState>();
  final Map<String, String> _credentials = {};
  String _name = '';
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${appTr('Connect')} ${_providerName('${widget.provider['id']}')}',
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.requiresName)
              TextFormField(
                decoration: InputDecoration(labelText: appTr('Channel name')),
                maxLength: 255,
                validator: (value) => value == null || value.trim().isEmpty
                    ? appTr('Enter a channel name.')
                    : null,
                onSaved: (value) => _name = value!.trim(),
              ),
            for (final field
                in (widget.provider['fields'] as List? ?? []).whereType<Map>())
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: (field['options'] as List? ?? []).isNotEmpty
                    ? DropdownButtonFormField<String>(
                        decoration: InputDecoration(
                          labelText: appTr('${field['label']}'),
                        ),
                        initialValue: '${(field['options'] as List).first}',
                        isExpanded: true,
                        items: [
                          for (final value in field['options'] as List)
                            DropdownMenuItem(
                              value: '$value',
                              child: Text(appTr('$value')),
                            ),
                        ],
                        onChanged: (value) =>
                            _credentials['${field['name']}'] = value!,
                        onSaved: (value) =>
                            _credentials['${field['name']}'] = value!,
                      )
                    : TextFormField(
                        decoration: InputDecoration(
                          labelText: appTr('${field['label']}'),
                        ),
                        obscureText: field['secret'] == true,
                        autocorrect: false,
                        enableSuggestions: field['secret'] != true,
                        validator: (value) =>
                            field['required'] == true &&
                                (value == null || value.trim().isEmpty)
                            ? appTr('This field is required.')
                            : null,
                        onSaved: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            _credentials['${field['name']}'] = value.trim();
                          }
                        },
                      ),
              ),
            FilledButton(
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                _form.currentState!.save();
                Navigator.pop(context, <String, dynamic>{
                  if (widget.requiresName) 'name': _name,
                  'credentials': _credentials,
                });
              },
              child: Text(appTr('Connect')),
            ),
          ],
        ),
      ),
    );
  }
}

class NativeChatbotEditor extends StatefulWidget {
  final MobileApi api;
  final String moduleId;
  final int? chatbotId;
  const NativeChatbotEditor({
    super.key,
    required this.api,
    required this.moduleId,
    this.chatbotId,
  });
  @override
  State<NativeChatbotEditor> createState() => _NativeChatbotEditorState();
}

class _NativeChatbotEditorState extends State<NativeChatbotEditor> {
  Map<String, dynamic>? _values;
  Map<String, dynamic> _schema = {};
  String? _error;
  bool _busy = false;
  String _requestId = SocialPostService.requestId();
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<dynamic> _call(
    String operation, [
    Map<String, dynamic> extra = const {},
  ]) => widget.api
      .request(
        '/native/connections',
        method: 'POST',
        body: {
          'module_id': widget.moduleId,
          'operation': operation,
          'chatbot_id': ?widget.chatbotId,
          ...extra,
        },
      )
      .timeout(const Duration(seconds: 30));
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _call('bot_form') as Map;
      if (mounted) {
        setState(() {
          _values = Map<String, dynamic>.from(data['values'] as Map);
          _schema = Map<String, dynamic>.from(data['schema'] as Map);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _call('save_bot', {'inputs': _values, 'request_id': _requestId});
      if (mounted) Navigator.pop(context, true);
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
      appBar: AppBar(
        title: Text(
          appTr(widget.chatbotId == null ? 'Create chatbot' : 'Edit chatbot'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(appTr(_error!)),
          if (_values == null && !_busy)
            TextButton(onPressed: _load, child: Text(appTr('Retry'))),
          if (_values != null)
            AbsorbPointer(
              absorbing: _busy,
              child: NativeConfigFields(
                value: _values!,
                schema: _schema,
                onChanged: (values) {
                  _values = values;
                  _requestId = SocialPostService.requestId();
                },
              ),
            ),
          if (_values != null)
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(appTr('Save')),
            ),
        ],
      ),
    );
  }
}
