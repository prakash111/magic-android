import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/image_attachment_picker.dart';
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
  Map<String, dynamic>? _values, _original;
  Map<String, dynamic> _schema = {};
  String? _error;
  bool _busy = false, _dirty = false;
  int _tab = 0, _revision = 0;
  String _requestId = SocialPostService.requestId();
  static const _tabs = ['Basics', 'Look', 'Behavior', 'More'];
  static const _basics = [
    'title',
    'welcome_message',
    'bubble_message',
    'ai_model',
    'language',
    'instructions',
  ];
  static const _look = [
    'logo',
    'avatar',
    'trigger_avatar_size',
    'trigger_background',
    'trigger_foreground',
    'color',
    'color_mode',
    'position',
    'show_logo',
    'show_date_and_time',
    'show_average_response_time',
    'header_bg_type',
    'header_bg_color',
    'header_bg_gradient',
    'welcome_bg_image',
    'bubble_design',
  ];
  static const _behavior = [
    'interaction_type',
    'do_not_go_beyond_instructions',
    'suggested_prompts_enabled',
    'suggested_prompts',
    'connect_message',
    'human_agent_conditions',
    'is_attachment',
    'is_emoji',
    'is_articles',
    'is_links',
    'is_email_collect',
    'is_contact',
    'active',
    'is_gdpr',
  ];
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
      .timeout(Duration(seconds: operation == 'bot_form' ? 10 : 30));
  Map<String, dynamic> _copy(Map value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);
  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await _call('bot_form') as Map;
      if (mounted) {
        setState(() {
          _values = _copy(data['values'] as Map);
          _original = _copy(_values!);
          _schema = Map<String, dynamic>.from(data['schema'] as Map);
          _dirty = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _change(Map<String, dynamic> values) {
    setState(() {
      _values!.addAll(values);
      _dirty = jsonEncode(_values) != jsonEncode(_original);
      _requestId = SocialPostService.requestId();
    });
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

  Future<bool> _confirmExit() async {
    if (!_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(appTr('Discard changes?')),
            content: Text(appTr('Your unsaved changes will be lost.')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(appTr('Keep editing')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(appTr('Discard')),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _picture(String name) async {
    try {
      final file = await ImageAttachmentPicker().pick(
        moduleId: widget.moduleId,
        field: name,
        maxBytes: 2 * 1024 * 1024,
      );
      if (file == null || !mounted) return;
      setState(() => _busy = true);
      final data = await _call('upload_picture', {
        'picture': base64Encode(file.bytes),
        'request_id': SocialPostService.requestId(),
      }) as Map;
      if (mounted) _change({name: data['url']});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickColor(String name) async {
    final controller = TextEditingController(
      text: '${_values?[name] ?? '#6366F1'}',
    );
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appTr('Choose color')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in [
                  '#6366F1',
                  '#A855F7',
                  '#22D3EE',
                  '#10B981',
                  '#F59E0B',
                  '#F43F5E',
                  '#FFFFFF',
                  '#131620',
                ])
                  IconButton(
                    tooltip: hex,
                    onPressed: () => Navigator.pop(context, hex),
                    icon: Icon(
                      Icons.circle,
                      color: Color(
                        int.parse('ff${hex.substring(1)}', radix: 16),
                      ),
                      size: 36,
                    ),
                  ),
              ],
            ),
            TextField(
              controller: controller,
              decoration: InputDecoration(labelText: appTr('Hex color')),
              maxLength: 7,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              final value = controller.text.trim();
              if (RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(value)) {
                Navigator.pop(context, value);
              }
            },
            child: Text(appTr('Apply')),
          ),
        ],
      ),
    );
    if (selected != null && mounted) _change({name: selected});
  }

  Future<void> _choose(String name) async {
    final options = ((_schema['properties']?[name]?['options'] as List?) ?? [])
        .whereType<Map>()
        .toList();
    var query = '';
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    appTr(
                      name == 'ai_model'
                          ? 'Choose AI model'
                          : 'Choose language',
                    ),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      labelText: appTr('Search'),
                    ),
                    onChanged: (value) =>
                        update(() => query = value.toLowerCase()),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: options.isEmpty
                        ? Center(
                            child: Text(
                              appTr(
                                'No available options. Refresh and try again.',
                              ),
                            ),
                          )
                        : ListView(
                            children: [
                              for (final option in options.where(
                                (option) => '${option['label']}'
                                    .toLowerCase()
                                    .contains(query),
                              ))
                                ListTile(
                                  minVerticalPadding: 12,
                                  title: Text('${option['label']}'),
                                  trailing: _values?[name] == option['value']
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Color(0xff6366f1),
                                        )
                                      : const Icon(Icons.circle_outlined),
                                  onTap: () => Navigator.pop(
                                    context,
                                    '${option['value']}',
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (value != null && mounted) _change({name: value});
  }

  Widget _visualField(String name) {
    final label = appTr(
      name == 'logo'
          ? 'Logo'
          : name == 'avatar'
          ? 'Chat button picture'
          : name.replaceAll('_', ' '),
    );
    if (['ai_model', 'language'].contains(name)) {
      final options =
          ((_schema['properties']?[name]?['options'] as List?) ?? [])
              .whereType<Map>();
      final current = options
          .where((option) => option['value'] == _values?[name])
          .firstOrNull;
      return Card(
        child: ListTile(
          leading: Icon(
            name == 'ai_model' ? Icons.auto_awesome : Icons.language,
          ),
          title: Text(appTr(name == 'ai_model' ? 'AI model' : 'Language')),
          subtitle: Text('${current?['label'] ?? _values?[name] ?? ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _choose(name),
        ),
      );
    }
    if (['logo', 'avatar', 'welcome_bg_image'].contains(name)) {
      final url = '${_values?[name] ?? ''}';
      return Card(
        child: ListTile(
          contentPadding: const EdgeInsets.all(12),
          leading: SizedBox(
            width: 48,
            height: 48,
            child: url.isEmpty
                ? const Icon(Icons.add_photo_alternate_outlined)
                : Image.network(
                    widget.api.origin.resolve(url).toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.image_not_supported_outlined),
                  ),
          ),
          title: Text(label),
          subtitle: Text(appTr('PNG, JPEG or WebP · up to 2 MB')),
          onTap: _busy ? null : () => _picture(name),
          trailing: url.isEmpty
              ? const Icon(Icons.upload)
              : IconButton(
                  tooltip: appTr('Remove picture'),
                  onPressed: () => _change({name: ''}),
                  icon: const Icon(Icons.close),
                ),
        ),
      );
    }
    if (name == 'trigger_avatar_size') {
      final size =
          double.tryParse('${_values?[name] ?? '60'}'.replaceAll('px', '')) ??
          60;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${appTr('Chat button size')} · ${size.round()} px'),
          Slider(
            min: 40,
            max: 96,
            divisions: 28,
            value: size.clamp(40, 96),
            label: '${size.round()} px',
            onChanged: (value) => _change({name: '${value.round()}px'}),
          ),
        ],
      );
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text('${_values?[name] ?? ''}'),
      trailing: Icon(
        Icons.circle,
        color: _color(name, const Color(0xff6366f1)),
        size: 36,
      ),
      onTap: () => _pickColor(name),
    );
  }

  Widget _fields(List<String> names) {
    const visual = [
      'ai_model',
      'language',
      'logo',
      'avatar',
      'welcome_bg_image',
      'trigger_avatar_size',
      'color',
      'header_bg_color',
      'trigger_background',
      'trigger_foreground',
    ];
    final values = <String, dynamic>{
      for (final name in names)
        if (_values!.containsKey(name) && !visual.contains(name))
          name: _values![name],
    };
    return Column(
      children: [
        for (final name in names)
          if (visual.contains(name) && _values!.containsKey(name))
            _visualField(name),
        NativeConfigFields(
          key: ValueKey('$_tab-$_revision-${names.join()}'),
          value: values,
          schema: {
            'type': 'object',
            'properties': {
              for (final name in names)
                if ((_schema['properties'] as Map?)?.containsKey(name) ?? false)
                  name: _schema['properties'][name],
            },
          },
          onChanged: _change,
        ),
      ],
    );
  }

  Widget _card(String title, String description, List<String> names) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appTr(title),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 14),
              child: Text(
                appTr(description),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
          _fields(names),
        ],
      ),
    ),
  );
  Color _color(String name, Color fallback) {
    final raw = '${_values?[name] ?? ''}'.replaceFirst('#', '');
    return RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(raw)
        ? Color(int.parse('ff$raw', radix: 16))
        : fallback;
  }

  Widget _preview() => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: _color('header_bg_color', const Color(0xff6366f1)),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(Icons.chat_bubble_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${_values?['title'] ?? ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_values?['welcome_message'] ?? ''}'),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _color(
                    'color',
                    const Color(0xff6366f1),
                  ).withValues(alpha: .18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text('${_values?['bubble_message'] ?? ''}'),
              ),
              const SizedBox(height: 12),
              Text(
                appTr('Appearance preview'),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _advanced(String title, List<String> names) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: ExpansionTile(
      title: Text(appTr(title)),
      childrenPadding: const EdgeInsets.all(16),
      children: [_fields(names)],
    ),
  );
  List<Widget> _content() {
    switch (_tab) {
      case 0:
        return [
          _card(
            'Name and messages',
            'What visitors see when they open the chat.',
            _basics.take(3).toList(),
          ),
          _card('AI', 'Choose the brain and the language of this chatbot.', [
            'ai_model',
            'language',
          ]),
          _card(
            'Instructions for the AI',
            'Tell the AI who it is and what it should do.',
            ['instructions'],
          ),
        ];
      case 1:
        return [
          _preview(),
          _card('Theme', 'Customize the chatbot colors.', [
            'color',
            'color_mode',
          ]),
          _advanced('Customize colors', [
            'header_bg_type',
            'header_bg_color',
            'header_bg_gradient',
            'trigger_background',
            'trigger_foreground',
          ]),
          _card('Pictures', 'Use your chatbot logo and chat button picture.', [
            'logo',
            'avatar',
            'trigger_avatar_size',
            'welcome_bg_image',
          ]),
          _card('Layout', '', [
            'position',
            'show_logo',
            'show_date_and_time',
            'show_average_response_time',
            'bubble_design',
          ]),
        ];
      case 2:
        return [
          _card('Conversation', '', _behavior.take(7).toList()),
          _card('Visitors can', '', [
            'is_attachment',
            'is_emoji',
            'is_articles',
            'is_links',
            'is_email_collect',
            'is_contact',
          ]),
          _card('Status and privacy', '', ['active', 'is_gdpr']),
        ];
      default:
        const domains = ['trusted_domains'];
        const links = [
          'privacy_policy_link',
          'terms_of_service_link',
          'footer_link',
          'whatsapp_link',
          'telegram_link',
          'facebook_link',
          'instagram_link',
          'watch_product_tour_link',
          'show_social_links_in_first_message',
        ];
        const voice = ['voice_call_enabled', 'voice_call_first_message'];
        const shop = [
          'is_shop',
          'shop_source',
          'shop_features',
          'shopify_domain',
          'shopify_access_token',
          'woocommerce_domain',
          'woocommerce_consumer_key',
          'woocommerce_consumer_secret',
          'is_booking_assistant',
          'booking_assistant_conditions',
          'booking_assistant_iframe',
        ];
        final known = {
          ..._basics,
          ..._look,
          ..._behavior,
          ...domains,
          ...links,
          ...voice,
          ...shop,
        };
        return [
          _advanced('Websites that can use this chatbot', domains),
          _advanced('Links and social', links),
          _advanced('Voice calls', voice),
          _advanced('Shop and booking', shop),
          _advanced(
            'Additional settings',
            _values!.keys.where((name) => !known.contains(name)).toList(),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _busy) return;
        if (await _confirmExit() && mounted) {
          setState(() => _dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                appTr(
                  widget.chatbotId == null ? 'Create chatbot' : 'Edit chatbot',
                ),
                style: const TextStyle(fontSize: 19),
              ),
              Text(
                appTr(
                  _busy
                      ? 'Loading…'
                      : _dirty
                      ? 'Unsaved changes'
                      : 'All changes saved',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: _dirty ? Colors.amber : Colors.green,
                ),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: _values == null
                  ? null
                  : () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      builder: (context) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: SingleChildScrollView(child: _preview()),
                        ),
                      ),
                    ),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(appTr('Preview')),
            ),
          ],
        ),
        body: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_values != null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          selectedColor: const Color(0xff6366f1),
                          label: Text(appTr(_tabs[i])),
                          selected: _tab == i,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _tab = i),
                        ),
                      ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  appTr(_error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Expanded(
              child: _values == null
                  ? Center(
                      child: _busy
                          ? const SizedBox.shrink()
                          : TextButton(
                              onPressed: _load,
                              child: Text(appTr('Retry')),
                            ),
                    )
                  : AbsorbPointer(
                      absorbing: _busy,
                      child: ListView(
                        padding: const EdgeInsets.all(14),
                        children: _content(),
                      ),
                    ),
            ),
          ],
        ),
        bottomNavigationBar: _values == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      OutlinedButton(
                        onPressed: _busy || !_dirty
                            ? null
                            : () => setState(() {
                                _values = _copy(_original!);
                                _revision++;
                                _dirty = false;
                                _requestId = SocialPostService.requestId();
                              }),
                        child: Text(appTr('Reset')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy || !_dirty ? null : _save,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(appTr('Save changes')),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
