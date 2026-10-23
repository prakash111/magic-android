import 'dart:async';
import 'dart:math';

import 'package:share_plus/share_plus.dart';

import '../services/image_attachment_picker.dart';
import 'native_module_screen.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/extension_workflow_service.dart';
import '../services/mobile_api.dart';
import 'native_visual_editor.dart';
import 'server_screen.dart' show RetryPanel;

class ExtensionWorkflowScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  final ImageAttachmentPicker? imagePicker;
  const ExtensionWorkflowScreen({
    super.key,
    required this.module,
    required this.api,
    this.imagePicker,
  });
  @override
  State<ExtensionWorkflowScreen> createState() =>
      _ExtensionWorkflowScreenState();
}

class _ExtensionWorkflowScreenState extends State<ExtensionWorkflowScreen>
    with WidgetsBindingObserver {
  late final _service = ExtensionWorkflowService(
    widget.api,
    '${widget.module['id']}',
  );
  final _form = GlobalKey<FormState>();
  final _values = <String, dynamic>{};
  final _files = <String, WorkflowFile>{};
  Map<String, dynamic>? _definition;
  List<Map> _history = [];
  Timer? _poll;
  String? _error, _requestId;
  int _promptRevision = 0;
  bool _busy = false, _refreshing = false, _active = true;

  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

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
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _poll?.cancel();
    } else {
      _schedule();
    }
  }

  Future<void> _load() async {
    try {
      final data = await _service.describe().timeout(
        const Duration(seconds: 25),
        onTimeout: () =>
            throw const ApiFailure('Unable to load this tool. Please retry.'),
      );
      if (!mounted) return;
      for (final field in (data['fields'] as List).whereType<Map>()) {
        if (field['type'] == 'select' &&
            (field['options'] as List).isNotEmpty) {
          _values.putIfAbsent(
            '${field['name']}',
            () => '${field['value'] ?? field['options'][0]['value']}',
          );
        }
      }
      final hasImages = (data['fields'] as List).whereType<Map>().any(
        (field) => field['accept'] == 'image/*',
      );
      final recovered = hasImages
          ? await ImageAttachmentPicker.takeRecovered('${widget.module['id']}')
          : null;
      if (!mounted) return;
      if (recovered != null) {
        final field = (data['fields'] as List)
            .whereType<Map>()
            .where((field) => field['name'] == recovered.$1)
            .firstOrNull;
        if (field != null &&
            recovered.$2.bytes.length <=
                (field['max_bytes'] as int? ?? 5 * 1024 * 1024)) {
          _files[recovered.$1] = recovered.$2;
        }
      }
      setState(() {
        _definition = data;
        _history = (data['data'] as List).whereType<Map>().toList();
        _error = null;
      });
      _schedule();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  bool get _hasPending => _history.any(
    (row) =>
        [
          'pending',
          'processing',
          'running',
          'queued',
          'in_progress',
          'uploading',
          'rendering',
        ].contains('${row['status']}'.toLowerCase()) ||
        ['pending', 'processing'].contains(row['export']?['status']),
  );

  void _schedule() {
    _poll?.cancel();
    if (_active && mounted && _hasPending && !_busy) {
      _poll = Timer(const Duration(seconds: 8), () => _refresh(poll: true));
    }
  }

  Future<void> _refresh({bool poll = false}) async {
    if (_refreshing || _busy) return;
    _refreshing = true;
    try {
      final data = await _service.history(refresh: true);
      if (mounted) {
        setState(() {
          _history = (data['data'] as List).whereType<Map>().toList();
          _error = null;
        });
      }
      _schedule();
    } catch (error) {
      _poll?.cancel();
      if (mounted) {
        setState(
          () => _error =
              '${error.toString()}${poll ? ' Automatic updates paused; tap Refresh to retry.' : ''}',
        );
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _pick(Map field) async {
    try {
      WorkflowFile? file;
      if ('${field['accept']}'.startsWith('image/')) {
        file = await (widget.imagePicker ?? ImageAttachmentPicker()).pick(
          moduleId: '${widget.module['id']}',
          field: '${field['name']}',
          maxBytes: field['max_bytes'] as int? ?? 5 * 1024 * 1024,
        );
      } else {
        final result = await SecureStore.invokeMapMethod<String, dynamic>(
          'pickFile',
          {'accept': field['accept']},
        );
        if (result != null) {
          file = WorkflowFile(
            '${result['name']}',
            (result['bytes'] as List).cast<int>(),
          );
        }
      }
      if (file != null && mounted) {
        setState(() {
          _files['${field['name']}'] = file!;
          _requestId = null;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _submit({int? exportProject}) async {
    if (_busy || exportProject == null && !_form.currentState!.validate()) {
      return;
    }
    _poll?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });
    _requestId ??= _uuid();
    try {
      final result = exportProject == null
          ? await _service.generate(_values, _files, requestId: _requestId!)
          : await _service.export(exportProject, _requestId!);
      if (!mounted) return;
      setState(() {
        _history = (result['data'] as List).whereType<Map>().toList();
        _requestId = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${result['message']}')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Uri? _output(String value) {
    final url = widget.api.origin.resolve(value);
    return url.scheme == 'https' && url.userInfo.isEmpty ? url : null;
  }

  Future<void> _preview(Map item) async {
    final url = _output('${item['output_url'] ?? ''}');
    if (url == null) return;
    if (RegExp(
      r'\.(mp4|mov|webm)(\?|$)',
      caseSensitive: false,
    ).hasMatch(url.toString())) {
      try {
        await SecureStore.invokeMethod<void>('previewMedia', {
          'url': url.toString(),
        });
      } catch (_) {
        if (mounted) {
          setState(
            () => _error = 'Install a video player to preview this result.',
          );
        }
      }
    } else {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Close preview',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  child: Image.network(
                    url.toString(),
                    errorBuilder: (_, error, stack) => const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Unable to load this result.'),
                    ),
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Save to gallery',
                    onPressed: () => _download(url),
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: 'Copy share link',
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: url.toString()),
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(this.context).showSnackBar(
                          const SnackBar(content: Text('Link copied')),
                        );
                      }
                    },
                    icon: const Icon(Icons.link),
                  ),
                  IconButton(
                    tooltip: 'Share result',
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        uri: url,
                        sharePositionOrigin: Rect.fromLTWH(
                          0,
                          0,
                          MediaQuery.sizeOf(context).width,
                          1,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.share_outlined),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
  }

  bool get _studio =>
      '${widget.module['id']}'.contains('photo') ||
      '${widget.module['id']}'.contains('fashion') ||
      _definition?['view'] == 'wardrobe';

  Widget _attachment(String name, Map field) {
    final file = _files[name]!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                Uint8List.fromList(file.bytes),
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => const SizedBox(
                  width: 72,
                  height: 72,
                  child: Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(file.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    '${(file.bytes.length / 1024).toStringAsFixed(1)} KB',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Replace photo',
              onPressed: _busy ? null : () => _pick(field),
              icon: const Icon(Icons.swap_horiz),
            ),
            IconButton(
              tooltip: 'Remove photo',
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _files.remove(name);
                      _requestId = null;
                    }),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  Widget _assetField(Map field, List<Map> options) {
    final selected = options
        .where((item) => '${item['value']}' == _values[field['name']])
        .firstOrNull;
    return OutlinedButton.icon(
      icon: const Icon(Icons.photo_library_outlined),
      label: Text('${field['label']}: ${selected?['label'] ?? 'Choose'}'),
      onPressed: _busy
          ? null
          : () async {
              var query = '', filter = 'All';
              final filters = <String>{
                'All',
                ...options
                    .map(
                      (item) => '${item['gender'] ?? item['category'] ?? ''}',
                    )
                    .where((value) => value.isNotEmpty),
              };
              final chosen = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (context) => StatefulBuilder(
                  builder: (context, update) {
                    final filtered = options
                        .where(
                          (item) =>
                              '${item['label']}'.toLowerCase().contains(
                                query,
                              ) &&
                              (filter == 'All' ||
                                  item['gender'] == filter ||
                                  item['category'] == filter),
                        )
                        .toList();
                    return SizedBox(
                      height: MediaQuery.sizeOf(context).height * .8,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(
                              'Choose ${field['label']}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              decoration: const InputDecoration(
                                hintText: 'Search assets...',
                                prefixIcon: Icon(Icons.search),
                              ),
                              onChanged: (value) =>
                                  update(() => query = value.toLowerCase()),
                            ),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: filters
                                    .map(
                                      (value) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: ChoiceChip(
                                          label: Text(value),
                                          selected: filter == value,
                                          onSelected: (_) =>
                                              update(() => filter = value),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                            Expanded(
                              child: GridView.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 12,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: .85,
                                    ),
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final item = filtered[index];
                                  return Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: InkWell(
                                      onTap: () => Navigator.pop(
                                        context,
                                        '${item['value']}',
                                      ),
                                      child: Column(
                                        children: [
                                          Expanded(
                                            child: Image.network(
                                              widget.api.origin
                                                  .resolve(
                                                    '${item['image_url']}',
                                                  )
                                                  .toString(),
                                              fit: BoxFit.cover,
                                              width: double.infinity,
                                              errorBuilder: (_, e, s) => const Icon(
                                                Icons
                                                    .image_not_supported_outlined,
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Text(
                                              '${item['label']}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
              if (chosen != null && mounted) {
                setState(() {
                  _values['${field['name']}'] = chosen;
                  _requestId = null;
                });
              }
            },
    );
  }

  Widget _gallery() => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: .8,
    ),
    itemCount: _history.length,
    itemBuilder: (context, index) {
      final item = _history[index],
          url = _output('${_history[index]['output_url'] ?? ''}');
      final pending = [
        'processing',
        'pending',
        'queued',
      ].contains('${item['status']}'.toLowerCase());
      return Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: url == null ? null : () => _preview(item),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: url == null
                    ? Center(
                        child: pending
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.image_outlined),
                      )
                    : Image.network(
                        url.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, e, s) =>
                            const Icon(Icons.image_not_supported_outlined),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item['title']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${item['status']}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (url != null)
                    IconButton(
                      tooltip: 'Open result',
                      onPressed: () => _preview(item),
                      icon: const Icon(Icons.open_in_full),
                    ),
                  if (_definition?['can_delete'] == true)
                    IconButton(
                      tooltip: 'Delete result',
                      onPressed: _busy ? null : () => _delete(item),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _delete(Map item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this item?'),
        content: const Text('This removes the item from your account.'),
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
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await _service.delete(item['id'] as int, _uuid());
      if (mounted) {
        setState(
          () => _history = (result['data'] as List).whereType<Map>().toList(),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _schedule();
      }
    }
  }

  Future<void> _download(Uri url) async {
    try {
      final response = await widget.api.client
          .get(url)
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 50 * 1024 * 1024 ||
          ImageAttachmentPicker.imageMimeType(response.bodyBytes) == null) {
        throw const ApiFailure('This image could not be downloaded.');
      }
      await SecureStore.invokeMethod<void>('saveImageToGallery', {
        'bytes': response.bodyBytes,
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Image saved to gallery')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Widget _field(Map field) {
    final name = '${field['name']}';
    final label = '${field['label']}';
    final required = field['required'] == true;
    var options = (field['options'] as List? ?? []).whereType<Map>().toList();
    if (name == 'ratio') {
      final model = (_definition!['fields'] as List)
          .whereType<Map>()
          .where((item) => item['name'] == 'model')
          .firstOrNull;
      final ratios = model?['ratios_by_model']?[_values['model']];
      if (ratios is Map) {
        options = ratios.entries
            .map((entry) => {'value': entry.key, 'label': entry.value})
            .toList();
      }
    }
    if (field['type'] == 'select' &&
        const ['ratio', 'aspect_ratio'].contains(name)) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FormField<String>(
          key: ValueKey('$name:${_values[name]}'),
          initialValue: _values[name]?.toString(),
          validator: (_) => required && _values[name] == null
              ? 'Choose an aspect ratio.'
              : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    ChoiceChip(
                      label: Text('${option['label']}'),
                      selected: _values[name] == '${option['value']}',
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _values[name] = '${option['value']}';
                              _requestId = null;
                              state.didChange('${option['value']}');
                            }),
                    ),
                ],
              ),
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: switch (field['type']) {
        'file' => FormField<WorkflowFile>(
          validator: (_) =>
              required && !_files.containsKey(name) ? 'Choose $label' : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_files[name] != null &&
                  '${field['accept']}'.startsWith('image/'))
                _attachment(name, field)
              else
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(field),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(_files[name]?.name ?? label),
                ),
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        'asset' => _assetField(field, options),
        'select' => DropdownButtonFormField<String>(
          key: ValueKey('$name:${_values[name]}'),
          initialValue: _values[name]?.toString(),
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: '${option['value']}',
                  child: Text(
                    '${option['label']}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _busy || field['read_only'] == true
              ? null
              : (value) {
                  setState(() {
                    _values[name] = value;
                    if (field['ratios_by_model'] is Map) {
                      final ratios = field['ratios_by_model'][value] as Map?;
                      if (ratios != null &&
                          !ratios.containsKey(_values['ratio'])) {
                        _values['ratio'] = ratios.keys.first.toString();
                      }
                    }
                    _requestId = null;
                  });
                },
          validator: (value) => required && value == null ? 'Required' : null,
        ),
        'multiselect' => FormField<List<String>>(
          validator: (_) => required && (_values[name] as List? ?? []).isEmpty
              ? 'Choose at least one option'
              : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in options)
                    FilterChip(
                      avatar: option['image_url'] == null
                          ? null
                          : CircleAvatar(
                              backgroundImage: NetworkImage(
                                widget.api.origin
                                    .resolve('${option['image_url']}')
                                    .toString(),
                              ),
                            ),
                      label: Text('${option['label']}'),
                      selected: (_values[name] as List? ?? []).contains(
                        '${option['value']}',
                      ),
                      onSelected: _busy
                          ? null
                          : (selected) => setState(() {
                              final values = List<String>.from(
                                _values[name] as List? ?? [],
                              );
                              if (selected) {
                                if (name == 'products' && values.length >= 3) {
                                  return;
                                }
                                values.add('${option['value']}');
                              } else {
                                values.remove('${option['value']}');
                              }
                              _values[name] = values;
                              _requestId = null;
                            }),
                    ),
                ],
              ),
              if (state.hasError)
                Text(
                  state.errorText!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        _ => TextFormField(
          key: ValueKey('$name:$_promptRevision'),
          initialValue: _values[name]?.toString(),
          enabled: !_busy,
          decoration: InputDecoration(labelText: label),
          minLines: name == 'prompt' ? 3 : 1,
          maxLines: name == 'prompt' ? 5 : 1,
          onChanged: (value) {
            _values[name] = value;
            _requestId = null;
          },
          validator: (value) =>
              required && (value?.trim().isEmpty ?? true) ? 'Required' : null,
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_definition == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : RetryPanel(message: _error!, retry: _load),
      );
    }
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if ((_definition!['tools'] as List? ?? []).isNotEmpty)
                    ...(_definition!['tools'] as List).whereType<Map>().map(
                      (tool) => Card(
                        child: ListTile(
                          leading: const Icon(Icons.auto_awesome_outlined),
                          title: Text(
                            '${tool['display_title'] ?? tool['title']}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => NativeModuleScreen(
                                module: Map<String, dynamic>.from(tool),
                                api: widget.api,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_definition!['can_generate'] != false)
                    Card(
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Form(
                          key: _form,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '${_definition!['title']}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 20),
                              if (_definition!['editor'] is String)
                                OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          _poll?.cancel();
                                          await openVisualEditor(
                                            context,
                                            api: widget.api,
                                            moduleId: '${widget.module['id']}',
                                            kind: '${_definition!['editor']}',
                                            title: 'Image editor',
                                          );
                                          if (mounted) _refresh();
                                        },
                                  icon: const Icon(Icons.brush_outlined),
                                  label: const Text('Advanced editor'),
                                ),
                              if ((_definition!['presets'] as List? ?? [])
                                  .isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final preset
                                          in (_definition!['presets'] as List))
                                        ActionChip(
                                          label: Text('$preset'),
                                          onPressed: _busy
                                              ? null
                                              : () => setState(() {
                                                  _values['prompt'] = '$preset';
                                                  _promptRevision++;
                                                  _requestId = null;
                                                }),
                                        ),
                                    ],
                                  ),
                                ),
                              for (final field
                                  in (_definition!['fields'] as List)
                                      .whereType<Map>())
                                _field(field),
                              FilledButton.icon(
                                onPressed: _busy ? null : _submit,
                                icon: const Icon(Icons.auto_awesome),
                                label: Text(
                                  _definition!['visual'] == null
                                      ? (_definition!['view'] == 'wardrobe'
                                            ? 'Upload garment'
                                            : 'Generate')
                                      : 'Create project',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Recent work',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (_history.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Your generated results will appear here.'),
                    ),
                  if (_studio) _gallery(),
                  if (!_studio)
                    for (final item in _history)
                      Card(
                        color: Theme.of(context).colorScheme.surface,
                        child: Column(
                          children: [
                            ListTile(
                              title: Text('${item['title']}'),
                              subtitle: Text('${item['status']}'),
                              leading: const Icon(Icons.collections_outlined),
                              trailing: item['visual'] != null
                                  ? IconButton(
                                      tooltip: 'Edit timeline',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: _busy
                                          ? null
                                          : () async {
                                              _poll?.cancel();
                                              await openVisualEditor(
                                                context,
                                                api: widget.api,
                                                moduleId:
                                                    '${widget.module['id']}',
                                                kind: '${item['visual']}',
                                                recordId: item['id'] as int,
                                                title: '${item['title']}',
                                              );
                                              if (mounted) _refresh();
                                            },
                                    )
                                  : item['output_url'] != null
                                  ? IconButton(
                                      tooltip: 'Preview result',
                                      icon: const Icon(Icons.open_in_full),
                                      onPressed: () => _preview(item),
                                    )
                                  : null,
                            ),
                            if (item['export'] is Map)
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  'Export: ${item['export']['status']} · ${item['export']['progress']}%',
                                ),
                              ),
                            if (item['visual'] != null)
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _submit(
                                        exportProject: item['id'] as int,
                                      ),
                                icon: const Icon(Icons.file_download_outlined),
                                label: const Text('Render video'),
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
    );
  }
}
