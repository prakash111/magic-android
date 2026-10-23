import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/mobile_api.dart';
import '../services/image_attachment_picker.dart';
import '../services/native_extension_service.dart';
import '../services/social_post_service.dart';
import 'native_module_screen.dart' show NativeModuleScreen, NativeSchemaForm;
import 'native_workspace_screen.dart' show WorkspaceEmptyState;
import 'server_screen.dart' show RetryPanel;

class NativeExtensionScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  final int? conversationId;
  const NativeExtensionScreen({
    super.key,
    required this.module,
    required this.api,
    this.conversationId,
  });
  @override
  State<NativeExtensionScreen> createState() => _NativeExtensionScreenState();
}

class _NativeExtensionScreenState extends State<NativeExtensionScreen> {
  late final _service = NativeExtensionService(
    widget.api,
    '${widget.module['id']}',
  );
  final _search = TextEditingController(), _message = TextEditingController();
  final _submissions = <String, String>{};
  Map<String, dynamic>? _data;
  List<Map> _records = [];
  String? _error, _currency, _provider, _source;
  String _period = 'today';
  int? _stage;
  int _generation = 0;
  bool _loading = false, _busy = false;
  Timer? _debounce;
  String get _kind => '${widget.module['route_type']}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.call(
        'load',
        values: {
          'query': _search.text.trim(),
          'page': more ? (_data?['current_page'] as int? ?? 1) + 1 : 1,
          if (widget.conversationId != null) 'record_id': widget.conversationId,
          if (_currency != null) 'currency': _currency,
          if (_stage != null) 'stage_id': _stage,
          if (_source != null) 'source': _source,
        },
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = result;
        final rows = (result['data'] as List? ?? []).whereType<Map>().toList();
        _records = more
            ? (widget.conversationId == null
                  ? [..._records, ...rows]
                  : [...rows, ..._records])
            : rows;
        _currency = result['currency']?.toString() ?? _currency;
        final providers = (result['providers'] as List? ?? [])
            .whereType<String>()
            .toList();
        if (providers.isNotEmpty && !providers.contains(_provider)) {
          final selected = result['whatsapp']?['whatsapp_provider'];
          _provider = providers.contains(selected)
              ? selected as String
              : providers.first;
        }
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

  Future<Map<String, dynamic>?> _act(
    String operation, {
    Map<String, dynamic> inputs = const {},
    Map<String, dynamic> files = const {},
    int? recordId,
    String? source,
    bool reload = true,
  }) async {
    if (_busy) return null;
    final fingerprint = jsonEncode([
      operation,
      inputs,
      recordId,
      source,
      files,
    ]);
    final requestId = _submissions.putIfAbsent(
      fingerprint,
      SocialPostService.requestId,
    );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _service.call(
        operation,
        requestId: requestId,
        inputs: inputs,
        files: files,
        values: {'record_id': ?recordId, 'source': ?source},
      );
      if (!mounted) return null;
      if (reload) await _load();
      if (mounted && result['message'] != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${result['message']}')));
      }
      _submissions.remove(fingerprint);
      return result;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _field(
    String name,
    String label, {
    String type = 'text',
    bool required = true,
    dynamic value,
    List options = const [],
  }) => {
    'name': name,
    'label': label,
    'type': type,
    'required': required,
    'value': value,
    'options': options,
  };

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Text(title, style: Theme.of(context).textTheme.titleLarge),
  );
  List<Map> get _metrics =>
      ((_data?['periods']?[_period] ?? _data?['metrics']) as List? ?? [])
          .whereType<Map>()
          .toList();
  Widget _empty(String title, String message, IconData icon) =>
      WorkspaceEmptyState(icon: icon, title: title, message: message);

  List<Widget> _settings() {
    final whatsapp = _data!['whatsapp'] as Map? ?? {};
    final providers = (_data!['providers'] as List? ?? []).whereType<String>();
    final fields = <Map<String, dynamic>>[
      if (_provider == 'twilio') ...[
        _field('whatsapp_sid', 'Account SID', value: whatsapp['whatsapp_sid']),
        _field(
          'whatsapp_token',
          'Auth Token',
          type: 'secret',
          required: whatsapp['token_configured'] != true,
        ),
        _field(
          'whatsapp_phone',
          'Phone Number',
          value: whatsapp['whatsapp_phone'],
        ),
        _field(
          'whatsapp_sandbox_phone',
          'Sandbox Phone Number',
          required: false,
          value: whatsapp['whatsapp_sandbox_phone'],
        ),
        _field(
          'whatsapp_environment',
          'Environment',
          type: 'select',
          value: whatsapp['whatsapp_environment'] ?? 'sandbox',
          options: const [
            {'value': 'sandbox', 'label': 'SANDBOX'},
            {'value': 'production', 'label': 'LIVE'},
          ],
        ),
      ] else ...[
        _field(
          'meta_access_token',
          'Access Token',
          type: 'secret',
          required: whatsapp['meta_token_configured'] != true,
        ),
        _field(
          'meta_phone_number_id',
          'Phone Number ID',
          value: whatsapp['meta_phone_number_id'],
        ),
        _field(
          'meta_waba_id',
          'WhatsApp Business Account ID',
          value: whatsapp['meta_waba_id'],
        ),
        _field(
          'meta_verify_token',
          'Verify Token',
          type: 'secret',
          required: false,
        ),
      ],
    ];
    return [
      _heading('Marketing Bot Telegram'),
      if (_data!['telegram']?['configured'] == true)
        const Text('A token is saved. Enter a new token to replace it.'),
      NativeSchemaForm(
        key: const ValueKey('telegram'),
        definition: {
          'title': 'Save Telegram settings',
          'fields': [_field('access_token', 'Access Token *', type: 'secret')],
        },
        busy: _busy,
        submit: (values, files) async {
          await _act(
            'save_telegram',
            inputs: Map<String, dynamic>.from(values),
          );
        },
      ),
      _heading('Marketing Bot Whatsapp Settings'),
      if (providers.isEmpty)
        const Text('Your administrator has disabled WhatsApp providers.')
      else ...[
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(_provider),
          initialValue: _provider,
          decoration: const InputDecoration(labelText: 'WhatsApp Provider'),
          items: providers
              .map(
                (provider) => DropdownMenuItem(
                  value: provider,
                  child: Text(
                    provider == 'twilio' ? 'Twilio' : 'Meta (Official API)',
                  ),
                ),
              )
              .toList(),
          onChanged: _busy
              ? null
              : (value) => setState(() => _provider = value),
        ),
        const SizedBox(height: 12),
        if (whatsapp['token_configured'] == true ||
            whatsapp['meta_token_configured'] == true)
          const Text('Saved tokens are kept when their fields are left empty.'),
        NativeSchemaForm(
          key: ValueKey('whatsapp-$_provider'),
          definition: {'title': 'Save WhatsApp settings', 'fields': fields},
          busy: _busy,
          submit: (values, files) async {
            await _act(
              'save_whatsapp',
              inputs: {...values, 'whatsapp_provider': _provider},
            );
          },
        ),
      ],
    ];
  }

  Widget _searchBar(String hint) => TextField(
    controller: _search,
    decoration: InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
    ),
    onChanged: (_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () => _load());
    },
  );
  String _date(dynamic date) {
    final value = DateTime.tryParse('$date');
    return value == null
        ? ''
        : DateFormat.MMMd().add_jm().format(value.toLocal());
  }

  String _money(dynamic value, dynamic currency) =>
      NumberFormat.simpleCurrency(name: '$currency')
          .format(num.tryParse('$value') ?? 0);

  List<Widget> _inbox() => [
    _searchBar('Search for chats...'),
    const SizedBox(height: 16),
    if (_records.isEmpty)
      _empty(
        'No conversations yet',
        'Messages from your connected WhatsApp and Telegram accounts will appear here.',
        Icons.forum_outlined,
      ),
    for (final chat in _records)
      Card(
        child: ListTile(
          leading: CircleAvatar(
            child: Text(
              ('${chat['name']}'.trim().isEmpty
                      ? '?'
                      : '${chat['name']}'.trim().substring(0, 1))
                  .toUpperCase(),
            ),
          ),
          title: Text(
            '${chat['name']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${chat['last_message'] ?? 'No messages yet'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 95),
            child: Text(
              _date(chat['updated_at']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => Scaffold(
                resizeToAvoidBottomInset: true,
                appBar: AppBar(title: Text('${chat['name']}')),
                body: NativeExtensionScreen(
                  module: widget.module,
                  api: widget.api,
                  conversationId: int.parse('${chat['id']}'),
                ),
              ),
            ),
          ),
        ),
      ),
  ];

  Widget _thread() => Column(
    children: [
      if (_loading || _busy) const LinearProgressIndicator(),
      if (_error != null) _errorPanel(),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if ((_data!['current_page'] as int? ?? 1) <
                (_data!['last_page'] as int? ?? 1))
              TextButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: const Text('Earlier messages'),
              ),
            for (final message in _records)
              Align(
                alignment: message['role'] == 'assistant'
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Card(
                  color: message['role'] == 'assistant'
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText('${message['message'] ?? ''}'),
                        const SizedBox(height: 6),
                        Text(
                          _date(message['created_at']),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _message,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: 'Write a message',
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Send reply',
                onPressed: _busy
                    ? null
                    : () async {
                        if (_message.text.trim().isEmpty) return;
                        final result = await _act(
                          'send_message',
                          recordId: widget.conversationId,
                          inputs: {'message': _message.text.trim()},
                        );
                        if (result != null && mounted) _message.clear();
                      },
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _newDeal() async {
    final stages = (_data!['stages'] as List)
        .whereType<Map>()
        .map((stage) => {'value': '${stage['id']}', 'label': stage['name']})
        .toList();
    final fields = [
      _field('title', 'Deal Name'),
      _field(
        'crm_deal_stage_id',
        'Stage',
        type: 'select',
        value: _stage?.toString() ?? stages.firstOrNull?['value'],
        options: stages,
      ),
      _field(
        'crm_contact_id',
        'Contact',
        type: 'select',
        required: false,
        options: _data!['contacts'] as List? ?? [],
      ),
      _field(
        'crm_company_id',
        'Company',
        type: 'select',
        required: false,
        options: _data!['companies'] as List? ?? [],
      ),
      _field('value', 'Deal Value', type: 'number', value: '0'),
      _field('currency', 'Currency', value: _currency ?? 'USD'),
      _field(
        'expected_close_date',
        'Expected Close Date',
        type: 'date',
        required: false,
      ),
      _field('description', 'Description', type: 'textarea', required: false),
    ];
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _NativeRecordForm(
          title: 'New deal',
          fields: fields,
          save: (inputs, files) async =>
              await _act('save_deal', inputs: inputs, reload: false) != null,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  List<Widget> _deals() => [
    NativeMetricGrid(metrics: _metrics),
    const SizedBox(height: 12),
    Row(
      children: [
        Expanded(
          child: Text(
            'Deal pipeline',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _newDeal,
          icon: const Icon(Icons.add),
          label: const Text('New deal'),
        ),
      ],
    ),
    const SizedBox(height: 12),
    _searchBar('Search deals...'),
    if ((_data!['currencies'] as List? ?? []).length > 1)
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _currency,
        decoration: const InputDecoration(labelText: 'Currency'),
        items: (_data!['currencies'] as List)
            .map(
              (currency) => DropdownMenuItem(
                value: '$currency',
                child: Text('$currency'),
              ),
            )
            .toList(),
        onChanged: (value) {
          setState(() => _currency = value);
          _load();
        },
      ),
    const SizedBox(height: 12),
    SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All deals'),
              selected: _stage == null,
              onSelected: (_) {
                setState(() => _stage = null);
                _load();
              },
            ),
          ),
          for (final stage
              in (_data!['stages'] as List? ?? []).whereType<Map>())
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${stage['name']} (${stage['count']})'),
                selected: _stage == stage['id'],
                onSelected: (_) {
                  setState(() => _stage = stage['id'] as int);
                  _load();
                },
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: 12),
    if (_records.isEmpty)
      _empty(
        'No deals in this stage',
        'Add a deal or choose another stage to explore your pipeline.',
        Icons.handshake_outlined,
      ),
    for (final deal in _records)
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
                      '${deal['title']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  PopupMenuButton<int>(
                    tooltip: 'Move deal',
                    enabled: !_busy,
                    itemBuilder: (_) => (_data!['stages'] as List)
                        .whereType<Map>()
                        .map(
                          (stage) => PopupMenuItem(
                            value: stage['id'] as int,
                            child: Text('${stage['name']}'),
                          ),
                        )
                        .toList(),
                    onSelected: (stage) => _act(
                      'move_deal',
                      recordId: int.parse('${deal['id']}'),
                      inputs: {'stage_id': stage},
                    ),
                  ),
                ],
              ),
              if ('${deal['contact'] ?? ''}${deal['company'] ?? ''}'.isNotEmpty)
                Text(
                  [deal['contact'], deal['company']]
                      .where((value) => value != null && '$value'.isNotEmpty)
                      .join(' · '),
                ),
              const SizedBox(height: 10),
              Text(
                _money(deal['value'], deal['currency']),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (deal['close_date'] != null)
                Text('Expected close: ${deal['close_date']}'),
            ],
          ),
        ),
      ),
  ];

  Future<void> _newCampaign() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _CampaignComposer(
          module: widget.module,
          api: widget.api,
          data: _data!,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  List<Widget> _campaigns() => [
    Row(
      children: [
        Expanded(
          child: Text(
            '${_data!['channel'] == 'telegram' ? 'Telegram' : 'WhatsApp'} campaigns',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _newCampaign,
          icon: const Icon(Icons.add),
          label: const Text('Create'),
        ),
      ],
    ),
    const SizedBox(height: 16),
    if (_records.isEmpty)
      _empty(
        'Your next campaign starts here',
        'Create a campaign and choose your audience and schedule.',
        Icons.campaign_outlined,
      ),
    for (final campaign in _records)
      Card(
        child: ListTile(
          title: Text('${campaign['title']}'),
          subtitle: Text(
            '${campaign['content']}\n${_date(campaign['scheduled_at'])}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: Chip(label: Text(_status('${campaign['status']}'))),
        ),
      ),
  ];
  String _status(String value) => switch (value.toLowerCase()) {
    'completed' || 'ready' || 'done' => 'Ready',
    'failed' || 'error' => 'Failed',
    'processing' || 'in_progress' || 'rendering' => 'Generating',
    _ =>
      value.isEmpty
          ? 'Saved'
          : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}',
  };

  List<Widget> _studio() => [
    _heading('Create a video project'),
    for (final source in (_data!['sources'] as List? ?? []).whereType<Map>())
      Card(
        child: ListTile(
          leading: const Icon(Icons.movie_creation_outlined),
          title: Text('${source['label']}'),
          subtitle: Text('${source['description'] ?? ''}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => NativeModuleScreen(
                  module: Map<String, dynamic>.from(source['module'] as Map),
                  api: widget.api,
                ),
              ),
            );
            if (mounted) await _load();
          },
        ),
      ),
    _heading('Project history'),
    if ((_data!['sources'] as List? ?? []).length > 1)
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _source ?? '',
        decoration: const InputDecoration(labelText: 'Project type'),
        items: [
          const DropdownMenuItem(value: '', child: Text('All projects')),
          for (final source in (_data!['sources'] as List).whereType<Map>())
            DropdownMenuItem(
              value: '${source['key']}',
              child: Text('${source['label']}'),
            ),
        ],
        onChanged: (value) {
          setState(() => _source = value);
          _load();
        },
      ),
    if (_records.isEmpty)
      _empty(
        'No projects yet',
        'Choose a creator above to start your first video.',
        Icons.video_library_outlined,
      ),
    for (final project in _records)
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (project['thumb_url'] is String)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    '${project['thumb_url']}',
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, error, stack) => const SizedBox(
                      height: 32,
                      child: Icon(Icons.movie_outlined),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${project['title'] ?? 'Video project'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Chip(label: Text(_status('${project['status'] ?? 'saved'}'))),
                ],
              ),
              Text(
                '${project['source_label'] ?? ''} · ${_date(project['created_at'])}',
              ),
              if ([
                'queued',
                'processing',
                'in_progress',
              ].contains(project['status']))
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _act(
                          'refresh_project',
                          recordId: int.parse('${project['id']}'),
                          source: '${project['source']}',
                        ),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh status'),
                ),
              if (project['video_url'] is String)
                TextButton.icon(
                  onPressed: () => SecureStore.invokeMethod<void>('openUrl', {
                    'url': project['video_url'],
                  }),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Open video'),
                ),
            ],
          ),
        ),
      ),
  ];

  List<Widget> _creator() => [
    _heading('Create your video'),
    const Text(
      'Choose your creative options. Your project will appear in Studio after submission.',
    ),
    NativeSchemaForm(
      definition: {'title': 'Create project', 'fields': _data!['fields'] ?? []},
      busy: _busy,
      submit: (inputs, files) async {
        final result = await _act(
          'create_video',
          inputs: Map<String, dynamic>.from(inputs),
          files: files,
          reload: false,
        );
        if (result != null && mounted) Navigator.pop(context);
      },
    ),
  ];

  Widget _errorPanel() => MaterialBanner(
    content: Text(_error!),
    actions: [
      TextButton(
        onPressed: _loading || _busy ? null : () => _load(),
        child: const Text('Retry'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    if (_data == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : RetryPanel(message: _error!, retry: _load);
    }
    if (widget.conversationId != null) return _thread();
    return Column(
      children: [
        if (_loading || _busy) const LinearProgressIndicator(),
        if (_error != null) _errorPanel(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ...switch (_kind) {
                  'marketing_dashboard' => [
                    _heading('Marketing overview'),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final period in const {
                          'today': 'Today',
                          'last_7_days': 'Last 7 Days',
                          'last_30_days': 'Last 30 Days',
                        }.entries)
                          ChoiceChip(
                            label: Text(period.value),
                            selected: _period == period.key,
                            onSelected: (_) =>
                                setState(() => _period = period.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    NativeMetricGrid(metrics: _metrics),
                    _heading('Recent campaigns'),
                    if (_records.isEmpty)
                      _empty(
                        'No campaigns yet',
                        'Your Telegram and WhatsApp campaigns will appear here.',
                        Icons.campaign_outlined,
                      ),
                    for (final campaign in _records)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.campaign_outlined),
                          title: Text('${campaign['name']}'),
                          subtitle: Text(
                            '${campaign['type']} · ${campaign['status']}',
                          ),
                        ),
                      ),
                  ],
                  'marketing_settings' => _settings(),
                  'marketing_inbox' => _inbox(),
                  'deal_pipeline' => _deals(),
                  'marketing_campaigns' => _campaigns(),
                  'agent_analytics' => [
                    _heading('Social media analytics'),
                    NativeMetricGrid(metrics: _metrics),
                  ],
                  'ugc_studio' => _studio(),
                  'ugc_creator' => _creator(),
                  _ => [],
                },
                if ((_data!['current_page'] as int? ?? 1) <
                    (_data!['last_page'] as int? ?? 1))
                  OutlinedButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: const Text('Load more'),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class NativeMetricGrid extends StatelessWidget {
  final List<Map> metrics;
  const NativeMetricGrid({super.key, required this.metrics});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final metric in metrics)
          SizedBox(
            width: (constraints.maxWidth - 10) / 2,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${metric['label']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      metric['currency'] != null
                          ? NumberFormat.simpleCurrency(
                              name: '${metric['currency']}',
                            ).format(num.tryParse('${metric['value']}') ?? 0)
                          : '${metric['value']}${metric['unit'] ?? ''}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (metric['change'] is num)
                      Row(
                        children: [
                          Icon(
                            (metric['change'] as num) > 0
                                ? Icons.trending_up
                                : (metric['change'] as num) < 0
                                ? Icons.trending_down
                                : Icons.trending_flat,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              '${(metric['change'] as num) > 0 ? '+' : ''}${metric['change']}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    if (metric['detail'] != null)
                      Text(
                        '${metric['detail']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _NativeRecordForm extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> fields;
  final Future<bool> Function(Map<String, dynamic>, Map<String, dynamic>) save;
  const _NativeRecordForm({
    required this.title,
    required this.fields,
    required this.save,
  });
  @override
  State<_NativeRecordForm> createState() => _NativeRecordFormState();
}

class _NativeRecordFormState extends State<_NativeRecordForm> {
  bool _busy = false;
  String? _error;
  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    appBar: AppBar(title: Text(widget.title)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) Text(_error!),
        NativeSchemaForm(
          definition: {'title': 'Save', 'fields': widget.fields},
          busy: _busy,
          submit: (inputs, files) async {
            setState(() => _busy = true);
            try {
              final saved = await widget.save(
                Map<String, dynamic>.from(inputs),
                files,
              );
              if (mounted) {
                if (saved) {
                  Navigator.pop(this.context, true);
                } else {
                  setState(
                    () => _error = 'The record could not be saved. Check the fields and try again.',
                  );
                }
              }
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
        ),
      ],
    ),
  );
}

class _CampaignComposer extends StatefulWidget {
  final Map<String, dynamic> module, data;
  final MobileApi api;
  const _CampaignComposer({
    required this.module,
    required this.api,
    required this.data,
  });
  @override
  State<_CampaignComposer> createState() => _CampaignComposerState();
}

class _CampaignComposerState extends State<_CampaignComposer> {
  late final _service = NativeExtensionService(
    widget.api,
    '${widget.module['id']}',
  );
  final _name = TextEditingController(),
      _content = TextEditingController(),
      _prompt = TextEditingController();
  final _contacts = <int>{};
  final _ids = <String, String>{};
  DateTime _scheduled = DateTime.now().add(const Duration(hours: 1));
  String? _image, _error;
  bool _busy = false;
  @override
  void dispose() {
    _name.dispose();
    _content.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _run(
    String operation, {
    Map<String, dynamic> inputs = const {},
    Map<String, dynamic> files = const {},
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = jsonEncode([operation, inputs, files]);
      final result = await _service.call(
        operation,
        inputs: inputs,
        files: files,
        requestId: _ids.putIfAbsent(key, SocialPostService.requestId),
      );
      if (!mounted) return;
      if (operation == 'save_campaign') {
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        if (operation == 'generate_content') {
          _content.text = '${result['content'] ?? ''}';
        }
        if (operation == 'upload_image') {
          _image = '${result['image_path'] ?? result['url']}';
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _imagePicker() async {
    try {
      final file = await ImageAttachmentPicker().pick(
        moduleId: 'marketing_campaign',
        field: 'upload_image',
        maxBytes: 10 * 1024 * 1024,
      );
      if (file != null) {
        await _run(
          'upload_image',
          files: {
            'upload_image': {
              'name': file.name,
              'bytes': base64Encode(file.bytes),
            },
          },
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _scheduled,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduled),
    );
    if (time != null && mounted) {
      setState(
        () => _scheduled = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    appBar: AppBar(title: const Text('Create campaign')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (_busy) const LinearProgressIndicator(),
        TextField(
          controller: _name,
          enabled: !_busy,
          decoration: const InputDecoration(labelText: 'Campaign title'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _prompt,
          enabled: !_busy,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Prompt'),
        ),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () {
                  if (_prompt.text.trim().isEmpty) {
                    setState(() => _error = 'Enter a prompt.');
                    return;
                  }
                  _run(
                    'generate_content',
                    inputs: {'prompt': _prompt.text.trim()},
                  );
                },
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Generate campaign content'),
        ),
        TextField(
          controller: _content,
          enabled: !_busy,
          minLines: 3,
          maxLines: 7,
          decoration: const InputDecoration(labelText: 'Message'),
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _busy ? null : _imagePicker,
          icon: const Icon(Icons.image_outlined),
          label: Text(_image == null ? 'Choose image' : 'Image attached'),
        ),
        const SizedBox(height: 14),
        Text(
          'Audience / contact lists',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if ((widget.data['contacts'] as List? ?? []).isEmpty)
          const Text(
            'Add contacts in your workspace before creating a campaign.',
          ),
        for (final contact
            in (widget.data['contacts'] as List? ?? []).whereType<Map>())
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${contact['name']}'),
            value: _contacts.contains(contact['id']),
            onChanged: _busy
                ? null
                : (selected) => setState(() {
                    if (selected == true) {
                      _contacts.add(contact['id'] as int);
                    } else {
                      _contacts.remove(contact['id']);
                    }
                  }),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickTime,
          icon: const Icon(Icons.schedule),
          label: Text(DateFormat.yMMMd().add_jm().format(_scheduled)),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _busy
              ? null
              : () {
                  if (_name.text.trim().isEmpty ||
                      _content.text.trim().isEmpty ||
                      _contacts.isEmpty ||
                      !_scheduled.isAfter(DateTime.now())) {
                    setState(
                      () => _error = 'Enter a title, message, audience and future schedule.',
                    );
                    return;
                  }
                  _run(
                    'save_campaign',
                    inputs: {
                      'name': _name.text.trim(),
                      'content': _content.text.trim(),
                      'contacts': _contacts.toList(),
                      'scheduled_at': _scheduled.toUtc().toIso8601String(),
                      if (_image != null) 'image': _image,
                    },
                  );
                },
          child: const Text('Schedule campaign'),
        ),
      ],
    ),
  );
}
