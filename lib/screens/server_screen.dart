import '../services/app_localizations.dart';

import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/ai_model_selection.dart';
import '../services/document_service.dart';
import '../services/image_generation_service.dart';
import '../widgets/chat_response.dart';
import '../widgets/generated_output_card.dart';
import 'documents_screen.dart';
import '../widgets/ai_model_selector.dart';
import '../theme/app_colors.dart';

import '../services/mobile_api.dart';
import '../theme/design.dart';
import '../services/chat_service.dart';
import 'workspace_screen.dart';

export '../widgets/chat_response.dart' show ChatResponse;
export 'native_social_screen.dart' show ServerSocialScreen;

class RetryPanel extends StatelessWidget {
  final String message;
  final Future<void> Function() retry;
  const RetryPanel({super.key, required this.message, required this.retry});
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(appTr(message), textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: retry, child: Text(appTr('Retry'))),
        ],
      ),
    );
  }
}

class ToolDirectory extends StatelessWidget {
  final List<Map<String, dynamic>> tools;
  final Map<String, dynamic> credits;
  final bool dashboard;
  final MobileApi? api;
  final Future<void> Function() refresh;
  const ToolDirectory({
    super.key,
    required this.tools,
    required this.credits,
    required this.dashboard,
    this.api,
    required this.refresh,
  });
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (dashboard) ...[
            Text(
              appTr('Your MagicAI workspace'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      appTr(":value plan", {
                        "value": credits['plan'] ?? 'Free',
                      }),
                    ),
                    Text(
                      appTr(":value words • :value2 images", {
                        "value": credits['words'] ?? '—',
                        "value2": credits['images'] ?? '—',
                      }),
                    ),
                    if (credits['shared'] != null)
                      Text(
                        appTr(":value shared credits", {
                          "value": credits['shared'],
                        }),
                      ),
                    if ((num.tryParse(
                              '${credits['shared'] ?? credits['words']}',
                            ) ??
                            1) <=
                        0)
                      Text(
                        appTr(
                          'No credits remaining. Upgrade to keep creating.',
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (localizationContext) {
                            AppLocalizations.watch(localizationContext);
                            return const PlansScreen();
                          },
                        ),
                      ),
                      child: Text(appTr('View upgrades')),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (tools.isEmpty)
            Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                appTr('No tools are enabled for your license and plan.'),
              ),
            ),
          for (final tool in tools.where((tool) => tool['component'] == 'form'))
            Card(
              child: ListTile(
                title: Text(
                  appTr(tool['title']?.toString() ?? tool['id'].toString()),
                ),
                subtitle: Text(
                  appTr(
                    tool['description']?.toString() ?? 'Create with MagicAI',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (localizationContext) {
                        AppLocalizations.watch(localizationContext);
                        return DynamicToolScreen(tool: tool, api: api);
                      },
                    ),
                  );
                  await refresh();
                },
              ),
            ),
        ],
      ),
    );
  }
}

class DynamicToolScreen extends StatefulWidget {
  final Map<String, dynamic> tool;
  final MobileApi? api;
  const DynamicToolScreen({super.key, required this.tool, this.api});
  @override
  State<DynamicToolScreen> createState() => _DynamicToolScreenState();
}

class _DynamicToolScreenState extends State<DynamicToolScreen> {
  final _form = GlobalKey<FormState>();
  final _inputs = <String, String>{};
  MobileApi get _api => widget.api ?? MobileApi.instance;
  late final _selection = AiModelSelection(_api);
  List<Map> _models = [];
  String? _model;
  bool _modelsLoading = false;

  int _tab = 0;
  int _historyCount = 0;
  int _historyVersion = 0;
  bool _generationCompleted = false;
  String? _outputTitle;
  String? _outputRevision;
  bool get _supportsHistory =>
      widget.tool['kind'] == 'writer' ||
      widget.tool['history_template_id'] is String;
  String get _historyTemplateId =>
      widget.tool['history_template_id']?.toString() ??
      widget.tool['id'].toString();

  void _historyUpdated(MobileDocument document) {
    if (_documentId == document.id) {
      setState(() {
        _text = document.content;
        _outputTitle = document.title;
        _outputRevision = document.revision;
      });
    }
  }

  void _historyDeleted(int id) {
    if (_documentId == id) {
      setState(() {
        _text = '';
        _documentId = null;
        _generationCompleted = false;
      });
    }
  }

  void _viewHistory() {
    FocusScope.of(context).unfocus();
    setState(() => _tab = 1);
  }

  @override
  void initState() {
    super.initState();
    if (['writer', 'image'].contains(widget.tool['kind'])) _loadModels();
  }

  Future<void> _loadModels() async {
    setState(() => _modelsLoading = true);
    try {
      final image = widget.tool['kind'] == 'image';
      final models = image
          ? ((await _api.request('/image-models'))['data'] as List)
                .whereType<Map>()
                .toList()
          : await _selection.models();
      final preferred =
          models.where((item) => item['is_default'] == true).firstOrNull ??
          models.firstOrNull;
      final selected = image
          ? (preferred?['id'] as String?)
          : await _selection.resolve(models);
      if (mounted) {
        setState(() {
          _models = models;
          _model = selected;
          _error = selected == null
              ? 'No enabled text models are available for your plan.'
              : null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _modelsLoading = false);
    }
  }

  Future<void> _selectModel(String id) async {
    try {
      if (widget.tool['kind'] != 'image') await _selection.select(id, _models);
      if (mounted) setState(() => _model = id);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  bool _busy = false;
  String? _error;
  String _text = '';
  int? _documentId;
  List<String> _images = [];
  String? _audio;
  Future<void> _generate() async {
    if (!_form.currentState!.validate()) return;
    _form.currentState!.save();
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _text = '';
      _documentId = null;
      _generationCompleted = false;
      _outputTitle = null;
      _outputRevision = null;
      _images = [];
      _audio = null;
    });
    try {
      final action =
          widget.tool['endpoint']?.toString() ??
          '/tools/${Uri.encodeComponent(widget.tool['id'].toString())}/run';
      if (widget.tool['kind'] == 'writer') {
        final models = await _selection.models();
        final selected = await _selection.resolve(models);
        if (selected == null) {
          throw const ApiFailure(
            'No enabled text models are available for your plan.',
          );
        }
        if (!mounted) return;
        setState(() {
          _models = models;
          _model = selected;
        });
      }
      if (widget.tool['kind'] == 'image') {
        if (_model == null) {
          throw const ApiFailure('Choose an enabled image model.');
        }
        final url = await ImageGenerationService(_api)
            .generate(prompt: _inputs['description'] ?? '', model: _model!);
        if (mounted) {
          setState(() {
            _images = [url];
            _generationCompleted = true;
            _historyVersion++;
          });
        }
        return;
      }
      final result = await _api.request(
        action,
        method: 'POST',
        body: {
          'inputs': _inputs,
          if (widget.tool['kind'] == 'writer') 'model': _model!,
        },
      );
      if (widget.tool['kind'] == 'writer') {
        if (result is! Map || result['message_id'] == null) {
          throw const ApiFailure('Server did not prepare a document.');
        }
        _documentId = int.tryParse('${result['message_id']}');
        await for (final delta in _api.stream(
          result['stream_endpoint']?.toString() ??
              '/writer/${result['message_id']}/stream',
          legacy: true,
        )) {
          if (!mounted) return;
          setState(() => _text += delta);
        }
      } else if (result is Map && result['images'] is List) {
        final images = (result['images'] as List)
            .whereType<Map>()
            .map((image) => image['output'] ?? image['response'])
            .whereType<String>();
        if (mounted) {
          setState(
            () => _images = images
                .map((path) => _api.origin.resolve(path).toString())
                .toList(),
          );
        }
      } else if (result is Map && result['audioPath'] is String) {
        if (mounted) {
          setState(
            () => _audio = MobileApi.instance.origin
                .resolve(result['audioPath'] as String)
                .toString(),
          );
        }
      } else {
        if (mounted) {
          setState(
            () => _text = result is Map && result['result'] is String
                ? result['result'] as String
                : const JsonEncoder.withIndent('  ').convert(result),
          );
        }
      }
      if (_supportsHistory &&
          mounted &&
          (_text.isNotEmpty || _images.isNotEmpty || _audio != null)) {
        setState(() {
          _generationCompleted = true;
          _historyVersion++;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final fields = (widget.tool['fields'] as List? ?? []).whereType<Map>();
    final generator = ListView(
      key: const ValueKey('generator-form-list'),
      primary: false,
      padding: const EdgeInsets.all(20),
      children: [
        Form(
          key: _form,
          child: Column(
            children: [
              for (final field in fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child:
                      field['type'] == 'select' &&
                          field['options'] is List &&
                          (field['options'] as List).isNotEmpty
                      ? DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _inputs[field['name'].toString()],
                          decoration: InputDecoration(
                            labelText: appTr(field['label'].toString()),
                          ),
                          items: (field['options'] as List)
                              .map(
                                (option) => DropdownMenuItem(
                                  value: option.toString(),
                                  child: Text(appTr(option.toString())),
                                ),
                              )
                              .toList(),
                          onChanged: _busy
                              ? null
                              : (value) => _inputs[field['name'].toString()] =
                                    value ?? '',
                          validator: (value) =>
                              field[appTr('required')] == true &&
                                  (value == null || value.isEmpty)
                              ? appTr('Required')
                              : null,
                          onSaved: (value) =>
                              _inputs[field['name'].toString()] = value ?? '',
                        )
                      : TextFormField(
                          initialValue: _inputs[field['name'].toString()],
                          onChanged: (value) =>
                              _inputs[field['name'].toString()] = value,
                          enabled: !_busy,
                          decoration: InputDecoration(
                            labelText: appTr(field['label'].toString()),
                          ),
                          minLines: field['type'] == 'textarea' ? 3 : 1,
                          maxLines: field['type'] == 'textarea' ? 8 : 1,
                          validator: (value) =>
                              field[appTr('required')] == true &&
                                  (value?.trim().isEmpty ?? true)
                              ? appTr('Required')
                              : null,
                          onSaved: (value) =>
                              _inputs[field['name'].toString()] =
                                  value?.trim() ?? '',
                        ),
                ),
            ],
          ),
        ),
        FilledButton(
          onPressed:
              _busy ||
                  _modelsLoading ||
                  widget.tool['kind'] == 'writer' && _model == null
              ? null
              : _generate,
          child: Text(appTr(_busy ? 'Generating…' : 'Generate')),
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              appTr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (_text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: widget.tool['kind'] == 'writer'
                ? GeneratedOutputCard(
                    key: ValueKey('generated-$_documentId'),
                    api: _api,
                    documentId: _documentId,
                    documentRevision: _outputRevision,
                    title: appTr(
                      _outputTitle ??
                          widget.tool['title']?.toString() ??
                          'Untitled Document',
                    ),
                    content: _text,
                    generating: _busy,
                    onViewHistory: _generationCompleted ? _viewHistory : null,
                    onSaved: () => setState(() => _historyVersion++),
                    onClear: () => setState(() {
                      _text = '';
                      _documentId = null;
                    }),
                  )
                : ChatResponse(text: _text, isStreaming: _busy),
          ),
        for (final url in _images)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Image.network(
              url,
              errorBuilder: (localizationContext, _, _) {
                AppLocalizations.watch(localizationContext);
                return Text(appTr('Unable to load image.'));
              },
            ),
          ),
        if (_generationCompleted && widget.tool['kind'] != 'writer')
          OutlinedButton.icon(
            onPressed: _viewHistory,
            icon: const Icon(Icons.history),
            label: Text(appTr('View in History')),
          ),
        if (_audio != null)
          FilledButton(
            onPressed: () =>
                SecureStore.invokeMethod<void>('openUrl', {'url': _audio}),
            child: Text(appTr('Play audio')),
          ),
      ],
    );
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(appTr(widget.tool['title'].toString()))),
      body: !_supportsHistory
          ? generator
          : LayoutBuilder(
              builder: (context, constraints) {
                AppLocalizations.watch(context);
                return Column(
                  children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .45,
                      ),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if ([
                                'writer',
                                'image',
                              ].contains(widget.tool['kind'])) ...[
                                AiModelSelector(
                                  models: _models,
                                  selected: _model,
                                  onSelected: _busy ? null : _selectModel,
                                ),
                                if (_modelsLoading)
                                  const LinearProgressIndicator(),
                                if (!_modelsLoading && _models.isEmpty)
                                  TextButton(
                                    onPressed: _loadModels,
                                    child: Text(appTr('Retry models')),
                                  ),
                                const SizedBox(height: 16),
                              ],
                              SegmentedButton<int>(
                                segments: [
                                  ButtonSegment(
                                    value: 0,
                                    label: Text(appTr('Generate')),
                                  ),
                                  ButtonSegment(
                                    value: 1,
                                    label: Text(
                                      appTr("History (:historyCount)", {
                                        "historyCount": _historyCount,
                                      }),
                                    ),
                                  ),
                                ],
                                selected: {_tab},
                                showSelectedIcon: false,
                                onSelectionChanged: (selected) {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _tab = selected.first);
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _tab,
                        children: [
                          generator,
                          DocumentsScreen(
                            api: _api,
                            templateId: _historyTemplateId,
                            refreshVersion: _historyVersion,
                            onCountChanged: (count) {
                              if (mounted && _historyCount != count) {
                                setState(() => _historyCount = count);
                              }
                            },
                            onDocumentUpdated: _historyUpdated,
                            onDocumentDeleted: _historyDeleted,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class ServerListScreen extends StatefulWidget {
  final String path;
  final String title;
  final MobileApi? api;
  const ServerListScreen({
    super.key,
    required this.path,
    required this.title,
    this.api,
  });
  @override
  State<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends State<ServerListScreen> {
  List<Map>? _items;
  String? _subscriptionUrl;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (widget.path != '/documents') _load();
  }

  Future<void> _load() async {
    try {
      final result = await (widget.api ?? MobileApi.instance).request(
        widget.path,
      );
      if (result is Map && result['subscription_url'] is String) {
        _subscriptionUrl = result['subscription_url'] as String;
      }
      dynamic list = result is List
          ? result
          : result is Map
          ? result['data'] ?? result['documents'] ?? result['userOpenai'] ?? []
          : result == null
          ? []
          : null;
      if (list is Map) list = list['data'];
      if (list is! List) throw const ApiFailure('Unexpected server list.');
      if (mounted) {
        setState(() {
          _items = list.whereType<Map>().toList();
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

    if (widget.path == '/documents') {
      return DocumentsScreen(api: widget.api ?? MobileApi.instance);
    }
    if (_error != null) {
      return Center(
        child: RetryPanel(message: appTr(_error!), retry: _load),
      );
    }
    if (_items == null) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            appTr(widget.title),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_items!.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    const Icon(Icons.description_outlined, size: 40),
                    const SizedBox(height: 16),
                    Text(
                      appTr("No :value yet", {
                        "value": widget.title.toLowerCase(),
                      }),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(appTr('Saved items will appear here.')),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: Text(appTr('Refresh')),
                    ),
                  ],
                ),
              ),
            ),
          for (final item in _items!)
            Card(
              child: ListTile(
                title: Text('${item['title'] ?? item['name'] ?? 'Document'}'),
                subtitle: Text(
                  widget.path == '/plans'
                      ? '${item['price'] ?? ''} ${item['frequency'] ?? ''}'
                      : '${item['created_at'] ?? ''}',
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return AlertDialog(
                      title: Text('${item['title'] ?? item['name']}'),
                      content: SingleChildScrollView(
                        child: SelectableText(
                          appTr(
                            (item['output'] ?? item['description'] ?? '')
                                .toString(),
                          ),
                        ),
                      ),
                      actions: [
                        if (widget.path == '/plans' && _subscriptionUrl != null)
                          TextButton(
                            onPressed: () => SecureStore.invokeMethod<void>(
                              'openUrl',
                              {'url': _subscriptionUrl},
                            ),
                            child: Text(appTr('Open subscriptions')),
                          ),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(appTr('Close')),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ServerChatScreen extends StatefulWidget {
  final int refreshVersion;
  final bool crm, web;
  final MobileApi? api;
  final String? initialPersona, initialPrompt;
  const ServerChatScreen({
    super.key,
    this.crm = false,
    this.web = false,
    this.api,
    this.initialPersona,
    this.initialPrompt,
    this.refreshVersion = 0,
  });
  @override
  State<ServerChatScreen> createState() => _ServerChatScreenState();
}

class _ServerChatScreenState extends State<ServerChatScreen> {
  MobileApi get _api => widget.api ?? MobileApi.instance;
  late final _service = ChatService(
    _api,
    context: widget.web ? 'web' : (widget.crm ? 'crm' : null),
  );
  final _prompt = TextEditingController(), _website = TextEditingController();
  List<Map> _personas = [], _models = [], _chats = [], _messages = [];
  String? _persona, _model, _chat, _error;
  bool _loading = true, _busy = false;
  @override
  void initState() {
    super.initState();
    _persona = widget.initialPersona;
    _prompt.text = widget.initialPrompt ?? '';
    _load();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _website.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ServerChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion && !_busy) _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final history = _service
        .conversations()
        .then((chats) {
          if (mounted) setState(() => _chats = chats);
        })
        .catchError((Object error) {
          if (mounted) {
            setState(
              () => _error = 'Conversation history could not be loaded. Pull to refresh or retry.',
            );
          }
        });
    try {
      final options = await _service.options();
      final selected = await AiModelSelection(_api).resolve(options['models']!);
      if (!mounted) return;
      setState(() {
        _personas = options['personas']!;
        _models = options['models']!;
        if (!_personas.any((item) => '${item['id']}' == _persona)) {
          _persona = _personas.firstOrNull?['id'].toString();
        }
        _model = selected;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
    await history;
  }

  Future<void> _open(String? id) async {
    try {
      final result = id == null
          ? []
          : ChatService.records(
              await _api.request('/chat/conversations/$id/messages'),
            );
      if (mounted) {
        setState(() {
          _chat = id;
          if (widget.web) {
            _website.text =
                _chats
                    .where((chat) => '${chat['id']}' == id)
                    .firstOrNull?['website_url']
                    ?.toString() ??
                '';
          }
          final category = _chats
              .where((chat) => '${chat['id']}' == id)
              .firstOrNull?['openai_chat_category_id']
              ?.toString();
          if (_personas.any((persona) => '${persona['id']}' == category)) {
            _persona = category;
          }
          _messages = result.whereType<Map>().toList();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  String? get _activeChatTitle {
    if (_chat == null) return null;
    final match = _chats.where((item) => '${item['id']}' == _chat).firstOrNull;
    return match?['title']?.toString();
  }

  String get _activeChatType {
    if (_chat == null) return 'assistant';
    final match = _chats.where((item) => '${item['id']}' == _chat).firstOrNull;
    return match?['type']?.toString() ?? 'assistant';
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1 && dt.day == now.day) {
        final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        final minute = dt.minute.toString().padLeft(2, '0');
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        return '$hour:$minute $ampm';
      }
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final month = months[dt.month - 1];
      return '$month ${dt.day}';
    } catch (_) {
      return raw;
    }
  }

  Future<void> _deleteChatDirect(String id) async {
    try {
      await _api.request('/chat/conversations/$id', method: 'DELETE');
      if (!mounted) return;
      setState(() {
        _chats.removeWhere((chat) => '${chat['id']}' == id);
        if (_chat == id) {
          _chat = null;
          _messages = [];
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(appTr('Chat session deleted'))));
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _clearAll() async {
    try {
      final contextParam = widget.web ? 'web' : (widget.crm ? 'crm' : null);
      final path =
          '/chat/conversations/clear-all${contextParam == null ? '' : '?context=$contextParam'}';
      await _api.request(path, method: 'DELETE');
      if (!mounted) return;
      setState(() {
        _chats = [];
        _chat = null;
        _messages = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr('All conversation history cleared'))),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    }
  }

  Future<void> _deleteChat(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        AppLocalizations.watch(ctx);
        return AlertDialog(
          title: Text(appTr('Delete Chat')),
          content: Text(
            appTr(
              'Are you sure you want to permanently delete this chat session?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(appTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              child: Text(appTr('Delete')),
            ),
          ],
        );
      },
    );
    if (confirm != true || !mounted) return;

    await _deleteChatDirect(id);
  }

  Future<void> _showConversationHistory(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        AppLocalizations.watch(sheetContext);
        return StatefulBuilder(
          builder: (context, setModalState) {
            AppLocalizations.watch(context);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 6),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              appTr('Conversation History'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_chats.isNotEmpty)
                            TextButton.icon(
                              key: const ValueKey('clear-all-button'),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogCtx) {
                                          AppLocalizations.watch(dialogCtx);
                                          return AlertDialog(
                                            title: Text(
                                              appTr('Clear All Conversations'),
                                            ),
                                            content: Text(
                                              appTr(
                                                'Clear all conversations? This action cannot be undone.',
                                              ),
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.of(dialogCtx)
                                                        .pop(false),
                                                child: Text(appTr('Cancel')),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.of(dialogCtx)
                                                        .pop(true),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: const Color(
                                                    0xFFEF4444,
                                                  ),
                                                ),
                                                child: Text(appTr('Clear All')),
                                              ),
                                            ],
                                          );
                                        },
                                      );
                                      if (confirmed == true &&
                                          sheetContext.mounted &&
                                          mounted) {
                                        Navigator.of(sheetContext).pop();
                                        await _clearAll();
                                      }
                                    },
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Color(0xFFEF4444),
                              ),
                              label: Text(
                                appTr('Clear All'),
                                style: TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: _chats.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 36,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.chat_bubble_outline,
                                    size: 48,
                                    color: Theme.of(context).hintColor,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    appTr('No conversation history yet'),
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.of(sheetContext).pop();
                                      _open(null);
                                    },
                                    icon: const Icon(Icons.add, size: 18),
                                    label: Text(appTr('+ New Chat')),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: _chats.length,
                              separatorBuilder: (context, index) {
                                AppLocalizations.watch(context);
                                return const Divider(height: 1, indent: 56);
                              },
                              itemBuilder: (context, index) {
                                AppLocalizations.watch(context);
                                final item = _chats[index];
                                final id = item['id'].toString();
                                final isSelected = id == _chat;
                                final type = item['type']?.toString();
                                final iconData = type == 'image'
                                    ? Icons.image_outlined
                                    : type == 'voice'
                                    ? Icons.mic_outlined
                                    : Icons.chat_bubble_outline;
                                final dateFormatted = _formatDate(
                                  item['updated_at']?.toString() ??
                                      item['created_at']?.toString(),
                                );

                                return ListTile(
                                  selected: isSelected,
                                  leading: CircleAvatar(
                                    radius: 18,
                                    backgroundColor: isSelected
                                        ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
                                        : (isDark
                                              ? const Color(0xFF2A2D3A)
                                              : const Color(0xFFF1F3F9)),
                                    child: Icon(
                                      iconData,
                                      size: 18,
                                      color: isSelected
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : Theme.of(context).hintColor,
                                    ),
                                  ),
                                  title: Text(
                                    appTr(
                                      item['title']?.toString() ??
                                          'Untitled Chat',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                  ),
                                  subtitle: dateFormatted.isNotEmpty
                                      ? Text(
                                          dateFormatted,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Theme.of(context).hintColor,
                                          ),
                                        )
                                      : null,
                                  trailing: IconButton(
                                    key: ValueKey('delete-session-$id'),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 20,
                                      color: Color(0xFF818898),
                                    ),
                                    tooltip: appTr('Delete this conversation'),
                                    onPressed: _busy
                                        ? null
                                        : () async {
                                            final confirmed = await showDialog<bool>(
                                              context: context,
                                              builder: (dialogCtx) {
                                                AppLocalizations.watch(
                                                  dialogCtx,
                                                );
                                                return AlertDialog(
                                                  title: Text(
                                                    appTr(
                                                      'Delete Conversation',
                                                    ),
                                                  ),
                                                  content: Text(
                                                    appTr(
                                                      'Delete this conversation?',
                                                    ),
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            dialogCtx,
                                                          ).pop(false),
                                                      child: Text(
                                                        appTr('Cancel'),
                                                      ),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            dialogCtx,
                                                          ).pop(true),
                                                      style:
                                                          FilledButton.styleFrom(
                                                            backgroundColor:
                                                                Theme.of(
                                                                      dialogCtx,
                                                                    )
                                                                    .colorScheme
                                                                    .error,
                                                          ),
                                                      child: Text(
                                                        appTr('Delete'),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                            if (confirmed == true && mounted) {
                                              await _deleteChatDirect(id);
                                              setModalState(() {});
                                            }
                                          },
                                  ),
                                  onTap: () {
                                    Navigator.of(sheetContext).pop();
                                    _open(id);
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _send() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || _persona == null || _model == null || _busy) return;
    final website = _website.text.trim();
    final url = Uri.tryParse(website);
    if (widget.web &&
        website.isNotEmpty &&
        (url == null ||
            !['http', 'https'].contains(url.scheme) ||
            url.host.isEmpty ||
            url.userInfo.isNotEmpty)) {
      setState(() => _error = 'Enter a valid public website URL.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    Map<String, dynamic>? entry;
    try {
      if (_chat == null) {
        final result = await _api.request(
          '/chat/conversations',
          method: 'POST',
          body: {
            'category_id': int.parse(_persona!),
            if (widget.crm) 'context': 'crm',
            if (widget.web) ...{
              'context': 'web',
              if (website.isNotEmpty) 'website_url': website,
            },
          },
        );
        if (!mounted) return;
        _chat = result['id'].toString();
        _chats.insert(0, result as Map);
      }
      entry = {'input': text, 'response': ''};
      if (mounted) setState(() => _messages.add(entry!));
      await for (final delta in _api.stream(
        '/chat/conversations/$_chat/stream',
        body: {'prompt': text, 'model': _model},
      )) {
        if (!mounted) return;
        setState(() => entry!['response'] = '${entry['response']}$delta');
      }
      _prompt.clear();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          if (entry != null && '${entry['response']}'.isEmpty) {
            _messages.remove(entry);
          }
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_personas.isEmpty && _error != null) {
      return RetryPanel(message: appTr(_error!), retry: _load);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        AppLocalizations.watch(context);
        return Column(
          children: [
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * .35,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      if (_models.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            appTr(
                              'No chat model is configured. Your conversation history remains available. Contact your administrator to enable a model.',
                            ),
                          ),
                        ),
                      if (widget.web) ...[
                        TextField(
                          controller: _website,
                          enabled: !_busy && _chat == null,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: appTr('Website URL (optional)'),
                            hintText: 'https://example.com',
                            helperText: appTr('Leave empty to search the web'),
                            prefixIcon: Icon(Icons.language),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        spacing: 10,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: constraints.maxWidth < 500
                                ? constraints.maxWidth - 24
                                : (constraints.maxWidth - 34) / 2,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              key: ValueKey('persona-$_persona'),
                              initialValue: _persona,
                              decoration: InputDecoration(
                                labelText: appTr('Persona'),
                              ),
                              items: _personas
                                  .map(
                                    (item) => DropdownMenuItem(
                                      value: item['id'].toString(),
                                      child: Row(
                                        children: [
                                          Icon(
                                            item['type'] == 'image'
                                                ? Icons.image_outlined
                                                : item['type'] == 'voice'
                                                ? Icons.mic_outlined
                                                : Icons.smart_toy_outlined,
                                            size: 18,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              item['name'].toString(),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (item['sub_description'] != null &&
                                              item['sub_description']
                                                  .toString()
                                                  .isNotEmpty)
                                            Flexible(
                                              child: Text(
                                                item['sub_description']
                                                    .toString(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: Theme.of(context)
                                                      .hintColor,
                                                  fontSize: 10,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _busy
                                  ? null
                                  : (value) => setState(() {
                                      _persona = value;
                                      _chat = null;
                                      _messages = [];
                                    }),
                            ),
                          ),
                          SizedBox(
                            width: constraints.maxWidth < 500
                                ? constraints.maxWidth - 24
                                : (constraints.maxWidth - 34) / 2,
                            child: AiModelSelector(
                              models: _models,
                              selected: _model,
                              onSelected: _busy
                                  ? null
                                  : (value) async {
                                      try {
                                        await AiModelSelection(_api)
                                            .select(value, _models);
                                        if (mounted) {
                                          setState(() => _model = value);
                                        }
                                      } catch (error) {
                                        if (mounted) {
                                          setState(
                                            () => _error = error.toString(),
                                          );
                                        }
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _busy
                                  ? null
                                  : () => _showConversationHistory(context),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _activeChatType == 'image'
                                          ? Icons.image_outlined
                                          : _activeChatType == 'voice'
                                          ? Icons.mic_outlined
                                          : Icons.chat_bubble_outline,
                                      size: 16,
                                      color: Theme.of(context).hintColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        appTr(
                                          _activeChatTitle ??
                                              'Conversation history',
                                        ),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _activeChatTitle != null
                                              ? Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.color
                                              : Theme.of(context).hintColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      color: Theme.of(context).hintColor,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (_chat != null)
                            IconButton(
                              key: const ValueKey('delete-chat-button'),
                              onPressed: _busy
                                  ? null
                                  : () => _deleteChat(_chat!),
                              icon: const Icon(Icons.delete_outline, size: 20),
                              tooltip: appTr('Delete Chat'),
                            ),
                          IconButton(
                            onPressed: _busy ? null : () => _open(null),
                            icon: const Icon(Icons.add_comment_outlined),
                            tooltip: appTr('New conversation'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.crm && _messages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final prompt in [
                      'Pipeline summary',
                      'Overdue tasks',
                      'Recent contacts',
                    ])
                      ActionChip(
                        label: Text(prompt),
                        onPressed: _busy
                            ? null
                            : () {
                                _prompt.text = prompt;
                                _send();
                              },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_messages.isEmpty && !widget.crm)
                    ChatEmptyState(
                      onPick: _busy || _model == null || _persona == null
                          ? null
                          : (prompt) {
                              _prompt.text = prompt;
                              _send();
                            },
                    ),
                  for (final message in _messages) ...[
                    if ((message['input']?.toString() ?? '').isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          margin: const EdgeInsets.only(left: 40, bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: kBrandGradient,
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(18),
                              bottomRight: Radius.circular(4),
                            ),
                          ),
                          child: Text(
                            appTr(message['input'].toString()),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    Card(
                      color: AppColors.of(context).surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: AppColors.of(context).outline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: ChatResponse(
                          text: message['response']?.toString() ?? '',
                          isStreaming:
                              _busy && identical(message, _messages.lastOrNull),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_error != null)
              Flexible(
                flex: 0,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(child: Text(appTr(_error!))),
                        TextButton(
                          onPressed: _busy ? null : _load,
                          child: Text(appTr('Retry')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_busy) const LinearProgressIndicator(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.only(left: 18, right: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: Theme.of(context).dividerColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _prompt,
                                enabled: !_busy,
                                minLines: 1,
                                maxLines: 4,
                                decoration: InputDecoration(
                                  hintText: appTr('Message your assistant'),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: appTr('Voice input'),
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      try {
                                        final text =
                                            await SecureStore.invokeMethod<
                                              String
                                            >('voiceInput');
                                        if (text != null && mounted) {
                                          setState(() => _prompt.text = text);
                                        }
                                      } catch (_) {
                                        if (mounted) {
                                          setState(
                                            () => _error = 'Voice input is unavailable on this device.',
                                          );
                                        }
                                      }
                                    },
                              icon: const Icon(Icons.mic_none),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Opacity(
                      opacity: _busy || _model == null || _persona == null
                          ? 0.5
                          : 1,
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: kBrandGradient,
                        ),
                        child: IconButton(
                          color: Colors.white,
                          tooltip: appTr('Send message'),
                          onPressed: _busy || _model == null || _persona == null
                              ? null
                              : _send,
                          icon: const Icon(Icons.send),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// "GPT-4 (Most Expensive & Fastest)" -> "GPT-4". The full text stays in the menu.
String shortModelName(String title) {
  final i = title.indexOf(' (');
  return i > 0 ? title.substring(0, i) : title;
}

class ChatEmptyState extends StatelessWidget {
  final void Function(String prompt)? onPick;
  const ChatEmptyState({super.key, this.onPick});
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    const ideas = [
      ('Write a cold email', Icons.edit_outlined, Color(0xFF6366F1)),
      (
        'Plan a 7-day content calendar',
        Icons.calendar_month_outlined,
        Color(0xFFF59E0B),
      ),
      ('Summarise this article', Icons.description_outlined, Color(0xFF38BDF8)),
      (
        'Brainstorm product names',
        Icons.auto_awesome_outlined,
        Color(0xFFF472B6),
      ),
    ];
    return Column(
      children: [
        const SizedBox(height: 16),
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: kBrandGradient,
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 14),
        Text(
          appTr('How can I help today?'),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          appTr('Ask anything, or start with an idea below.'),
          style: TextStyle(color: mutedText(context)),
        ),
        const SizedBox(height: 20),
        for (final idea in ideas)
          ToolRow(
            icon: idea.$2,
            color: idea.$3,
            title: idea.$1,
            onTap: onPick == null ? null : () => onPick!(idea.$1),
          ),
      ],
    );
  }
}
