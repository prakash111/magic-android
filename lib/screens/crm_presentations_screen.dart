import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/mobile_api.dart';
import '../services/native_extension_service.dart';
import 'server_screen.dart' show RetryPanel;

List<Map<String, dynamic>> _maps(dynamic data) => data is List
    ? data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
    : [];
int _int(dynamic value) => int.tryParse('$value') ?? 0;
bool _pending(Map data) => ['pending', 'generating'].contains(data['status']);
String _content(dynamic value) {
  if (value is Map) {
    return value.values.map(_content).where((s) => s.isNotEmpty).join('\n');
  }
  if (value is List) {
    return value.map(_content).where((s) => s.isNotEmpty).join('\n');
  }
  return value == null ? '' : '$value';
}

class CrmPresentationsScreen extends StatefulWidget {
  const CrmPresentationsScreen({
    super.key,
    required this.module,
    required this.api,
  });
  final Map<String, dynamic> module;
  final MobileApi api;
  @override
  State<CrmPresentationsScreen> createState() => _CrmPresentationsState();
}

class _CrmPresentationsState extends State<CrmPresentationsScreen> {
  late final _service = NativeExtensionService(
    widget.api,
    '${widget.module['id']}',
  );
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = [], _deals = [];
  bool _loading = true, _loaded = false;
  String? _error;
  String _status = 'all';
  int _page = 1, _lastPage = 1, _generation = 0;
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
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.call(
        'load',
        values: {
          'query': _search.text.trim(),
          'status': _status,
          'page': more ? _page + 1 : 1,
        },
      );
      if (!mounted || generation != _generation) return;
      if (result['data'] is! List || result['deals'] is! List) {
        throw const ApiFailure(
          'Presentations could not be loaded. Please retry.',
        );
      }
      setState(() {
        _rows = more
            ? [..._rows, ..._maps(result['data'])]
            : _maps(result['data']);
        _deals = _maps(result['deals']);
        _page = _int(result['current_page']).clamp(1, 10000);
        _lastPage = _int(result['last_page']).clamp(1, 10000);
        _loaded = true;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PresentationDetail(service: _service, id: id),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _create() async {
    final id = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CreatePresentation(service: _service, deals: _deals),
    );
    if (id != null && mounted) await _open(id);
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      appTr('Generate AI-powered pitch decks for your deals.'),
                    ),
                  ),
                  IconButton(
                    tooltip: appTr('Refresh'),
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: !_loaded || _deals.isEmpty ? null : _create,
                  icon: const Icon(Icons.add),
                  label: Text(appTr('New Presentation')),
                ),
              ),
              if (_loaded && _deals.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    appTr(
                      'Create a deal in CRM before generating a presentation.',
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: appTr('Search presentations'),
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), _load);
                },
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final status in [
                      'all',
                      'pending',
                      'generating',
                      'completed',
                      'failed',
                    ])
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ChoiceChip(
                          label: Text(
                            appTr(
                              status[0].toUpperCase() + status.substring(1),
                            ),
                          ),
                          selected: _status == status,
                          onSelected: (_) {
                            setState(() => _status = status);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                if (_error != null)
                  RetryPanel(message: appTr(_error!), retry: _load),
                if (_loaded && _rows.isEmpty && _error == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Icon(Icons.slideshow, size: 40),
                        const SizedBox(height: 16),
                        Text(appTr('No presentations found')),
                        const SizedBox(height: 8),
                        Text(
                          appTr(
                            'Generate your first AI-powered pitch deck for a deal.',
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                for (final row in _rows)
                  Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _open(_int(row['id'])),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['title'] ?? ''}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Chip(
                                  label: Text(
                                    appTr('${row['status'] ?? 'pending'}'),
                                  ),
                                ),
                                if (row['style'] != null)
                                  Chip(label: Text(appTr('${row['style']}'))),
                              ],
                            ),
                            if (row['deal'] is Map)
                              Text('${row['deal']['title'] ?? ''}'),
                            if (row['company'] != null)
                              Text('${row['company']}'),
                            const SizedBox(height: 8),
                            if (row['engine'] == 'gamma')
                              Text(appTr('Generated with Gamma.'))
                            else
                              Text(
                                appTr(':done of :total slides', {
                                  'done': _int(row['completed_slides']),
                                  'total': _int(row['total_slides']),
                                }),
                              ),
                            if (_pending(row)) ...[
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: (_int(row['progress']) / 100).clamp(
                                  0,
                                  1,
                                ),
                              ),
                            ],
                            if (row['error_message'] != null)
                              Text(
                                '${row['error_message']}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_page < _lastPage)
                  TextButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: Text(appTr('Load more')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CreatePresentation extends StatefulWidget {
  const _CreatePresentation({required this.service, required this.deals});
  final NativeExtensionService service;
  final List<Map<String, dynamic>> deals;
  @override
  State<_CreatePresentation> createState() => _CreatePresentationState();
}

class _CreatePresentationState extends State<_CreatePresentation> {
  int? _deal;
  String _style = 'corporate';
  bool _saving = false;
  String? _error;
  Future<void> _save() async {
    if (_deal == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.service.call(
        'create_presentation',
        inputs: {'crm_deal_id': _deal, 'style': _style},
      );
      final id = _int(result['record_id']);
      if (id <= 0) {
        throw const ApiFailure(
          'The server did not return the presentation. Refresh before retrying.',
        );
      }
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appTr('Generate Presentation'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            isExpanded: true,
            initialValue: _deal,
            decoration: InputDecoration(labelText: appTr('Deal')),
            items: widget.deals
                .map(
                  (deal) => DropdownMenuItem(
                    value: _int(deal['id']),
                    child: Text(
                      '${deal['title']}${deal['company'] == null ? '' : ' · ${deal['company']}'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) => setState(() => _deal = value),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _style,
            decoration: InputDecoration(labelText: appTr('Style')),
            items: [
              for (final style in [
                'corporate',
                'modern',
                'minimal',
                'creative',
              ])
                DropdownMenuItem(
                  value: style,
                  child: Text(
                    appTr(style[0].toUpperCase() + style.substring(1)),
                  ),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _style = value ?? 'corporate'),
          ),
          const SizedBox(height: 16),
          Text(
            appTr(
              'Text generation and image credits will be deducted according to your configured presentation engine.',
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                appTr(_error!),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving || _deal == null ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(appTr(_saving ? 'Starting generation...' : 'Generate')),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: Text(appTr('Cancel')),
          ),
        ],
      ),
    ),
  );
}

class _PresentationDetail extends StatefulWidget {
  const _PresentationDetail({required this.service, required this.id});
  final NativeExtensionService service;
  final int id;
  @override
  State<_PresentationDetail> createState() => _PresentationDetailState();
}

class _PresentationDetailState extends State<_PresentationDetail>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _record;
  bool _loading = false, _busy = false, _foreground = true;
  String? _error;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _poll?.cancel();
    } else if (_record == null || _pending(_record!)) {
      _load();
    }
  }

  Future<void> _load() async {
    if (_loading) return;
    _poll?.cancel();
    setState(() => _loading = true);
    try {
      final data = await widget.service.call(
        'load',
        values: {'record_id': widget.id},
      );
      if (data['presentation'] is! Map) {
        throw const ApiFailure(
          'This presentation could not be loaded. Please retry.',
        );
      }
      if (mounted) {
        setState(() {
          _record = Map<String, dynamic>.from(data['presentation']);
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_foreground && _record != null && _pending(_record!)) {
          _poll = Timer(const Duration(seconds: 5), _load);
        }
      }
    }
  }

  Future<void> _export(String format, {int? slideId}) async {
    setState(() => _busy = true);
    try {
      final result = await widget.service.call(
        'export_presentation',
        values: {'record_id': widget.id},
        inputs: {'format': format, 'slide_id': ?slideId},
      );
      final uri = Uri.tryParse('${result['url'] ?? ''}');
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const ApiFailure('This download is not available. Please retry.');
      }
      await SecureStore.invokeMethod<void>('openUrl', {'url': '$uri'});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(appTr(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appTr('Delete presentation?')),
        content: Text(
          appTr(
            'This will permanently delete the presentation and its slides.',
          ),
        ),
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
    if (confirmed != true || !mounted) return;
    _poll?.cancel();
    setState(() => _busy = true);
    try {
      await widget.service.call(
        'delete_presentation',
        values: {'record_id': widget.id},
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(appTr(e.toString()))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_record != null && _pending(_record!) && _foreground) {
          _poll = Timer(const Duration(seconds: 5), _load);
        }
      }
    }
  }

  Widget _slide(Map<String, dynamic> slide) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (slide['image_url'] is String)
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('${slide['title'] ?? ''}')),
                    body: Center(
                      child: InteractiveViewer(
                        child: Image.network(
                          slide['image_url'] as String,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: Image.network(
                slide['image_url'] as String,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 120,
                  child: Center(child: Icon(Icons.broken_image_outlined)),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            '${slide['title'] ?? ''}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(appTr('${slide['status'] ?? ''}')),
          if (_content(slide['content']).isNotEmpty)
            SelectionArea(child: Text(_content(slide['content']))),
          if (slide['error_message'] != null)
            Text(
              '${slide['error_message']}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (slide['image_url'] is String && slide['status'] == 'completed')
            TextButton.icon(
              onPressed: _busy
                  ? null
                  : () => _export('slide', slideId: _int(slide['id'])),
              icon: const Icon(Icons.download),
              label: Text(appTr('Download slide')),
            ),
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final record = _record;
    return Scaffold(
      appBar: AppBar(
        title: Text('${record?['title'] ?? appTr('Presentation')}'),
        actions: [
          IconButton(
            tooltip: appTr('Refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: appTr('Delete presentation'),
            onPressed: record == null || _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_loading || _busy) const LinearProgressIndicator(),
            if (_error != null)
              RetryPanel(message: appTr(_error!), retry: _load),
            if (record != null) ...[
              Text(
                appTr('${record['status'] ?? ''}'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (record['engine'] == 'gamma')
                Text(
                  appTr(
                    _pending(record)
                        ? 'Gamma is building your deck. This can take a minute.'
                        : 'Generated with Gamma. View it online or download the PDF.',
                  ),
                )
              else
                Text(
                  appTr(':done of :total slides', {
                    'done': _int(record['completed_slides']),
                    'total': _int(record['total_slides']),
                  }),
                ),
              if (_pending(record)) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (_int(record['progress']) / 100).clamp(0, 1),
                ),
                const SizedBox(height: 8),
                Text(
                  appTr(
                    'Your slides are being created. Progress updates automatically.',
                  ),
                ),
              ],
              if (record['error_message'] != null)
                Text(
                  '${record['error_message']}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (record['has_pdf'] == true)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _export('pdf'),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(appTr('Download PDF')),
                    ),
                  if (_int(record['completed_slides']) > 0)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _export('zip'),
                      icon: const Icon(Icons.folder_zip_outlined),
                      label: Text(appTr('Download slides')),
                    ),
                  if (record['has_pptx'] == true)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _export('pptx'),
                      icon: const Icon(Icons.slideshow),
                      label: Text(appTr('Download PowerPoint')),
                    ),
                  if (record['has_web_view'] == true)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _export('open'),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(appTr('Open presentation')),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              ..._maps(record['slides']).map(_slide),
              if (_maps(record['slides']).isEmpty &&
                  !_pending(record) &&
                  record['engine'] != 'gamma')
                Text(appTr('No slides available.')),
            ],
          ],
        ),
      ),
    );
  }
}
