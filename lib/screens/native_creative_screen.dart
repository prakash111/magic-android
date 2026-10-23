import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/mobile_api.dart';
import '../services/image_attachment_picker.dart';
import '../widgets/ai_model_selector.dart';
import '../services/image_generation_service.dart';

class NativeCreativeScreen extends StatefulWidget {
  final MobileApi api;
  final ImageAttachmentPicker? imagePicker;
  const NativeCreativeScreen({super.key, required this.api, this.imagePicker});
  @override
  State<NativeCreativeScreen> createState() => _NativeCreativeScreenState();
}

class _NativeCreativeScreenState extends State<NativeCreativeScreen> {
  final _prompt = TextEditingController(),
      _name = TextEditingController(text: 'Untitled design');
  final _canvasKey = GlobalKey();
  final _scroll = ScrollController();
  List<Map> _models = [];
  String? _model;
  double _width = 1080, _height = 1080;
  bool _editorOnly = false;
  List<Map> _projects = [], _templates = [];
  List<Map<String, dynamic>> _layers = [];
  String? _error;
  String _mode = 'image', _background = '#1E2230';
  int? _project, _selected;
  int _page = 1, _lastPage = 1;
  bool _loading = true, _busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _prompt.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    try {
      final results = await Future.wait([
        widget.api.request(
          '/native/creative/projects?page=${more ? _page + 1 : 1}',
        ),
        widget.api.request('/native/creative/templates'),
        widget.api.request('/image-models'),
      ]);
      if (mounted) {
        setState(() {
          final data = results[0] as Map;
          final rows = (data['data'] as List? ?? []).whereType<Map>().toList();
          _projects = more ? [..._projects, ...rows] : rows;
          _page = int.tryParse('${data['current_page']}') ?? 1;
          _lastPage = int.tryParse('${data['last_page']}') ?? 1;
          _templates = (results[1] is List ? results[1] as List : [])
              .whereType<Map>()
              .toList();
          _models =
              (results[2] is Map
                      ? (results[2] as Map)['data'] as List? ?? []
                      : [])
                  .whereType<Map>()
                  .toList();
          if (!_models.any((item) => item['id'] == _model)) {
            _model =
                (_models
                            .where((item) => item['is_default'] == true)
                            .firstOrNull ??
                        _models.firstOrNull)?['id']
                    as String?;
          }
          _loading = false;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _generate() async {
    if (_prompt.text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_model == null) {
        throw const ApiFailure(
          'No enabled image models are available. Ask your administrator to check image settings.',
        );
      }
      final path = await ImageGenerationService(widget.api)
          .generate(prompt: _prompt.text.trim(), model: _model!);
      if (mounted) {
        setState(() {
          _layers.insert(0, {
            'type': 'image',
            'url': path,
            'x': 0.0,
            'y': 0.0,
            'size': 1.0,
          });
          _selected = 0;
        });
        await _save();
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reference() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final image = await (widget.imagePicker ?? ImageAttachmentPicker()).pick(
        moduleId: 'web:creative_suite',
        field: 'reference_image',
        maxBytes: 10 * 1024 * 1024,
      );
      if (image == null) return;
      final url = await widget.api.uploadImage(image.bytes, image.name);
      if (mounted) {
        setState(() {
          _layers.add({
            'type': 'image',
            'url': url,
            'x': 0.1,
            'y': 0.1,
            'size': 0.6,
          });
          _selected = _layers.length - 1;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _text() async {
    final controller = TextEditingController(
      text: _selected != null && _layers[_selected!]['type'] == 'text'
          ? '${_layers[_selected!]['text']}'
          : 'Your headline',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add your words'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    setState(() {
      if (_selected != null && _layers[_selected!]['type'] == 'text') {
        _layers[_selected!]['text'] = value;
      } else {
        _layers.add({
          'type': 'text',
          'text': value,
          'x': 0.12,
          'y': 0.4,
          'size': 0.09,
          'color': '#FFFFFF',
        });
        _selected = _layers.length - 1;
      }
    });
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.api.request(
        '/native/creative/projects${_project == null ? '' : '/$_project'}',
        method: _project == null ? 'POST' : 'PUT',
        body: {
          'name': _name.text.trim(),
          'payload': {
            'version': 1,
            'width': _width.round(),
            'height': _height.round(),
            'background': _background,
            'layers': _layers,
          },
        },
      ) as Map;
      _project = data['data']['id'] as int;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Project saved')));
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    try {
      setState(() => _selected = null);
      final canvasContext = _canvasKey.currentContext;
      if (canvasContext == null) {
        throw const ApiFailure('Open the canvas before exporting.');
      }
      await Scrollable.ensureVisible(
        canvasContext,
        duration: const Duration(milliseconds: 200),
      );
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _canvasKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes != null) {
        await SecureStore.invokeMethod<void>('saveImage', {
          'bytes': bytes.buffer.asUint8List(),
          'name': 'magicai-design.png',
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Unable to export this design. $error');
      }
    }
  }

  Future<void> _open(Map project) async {
    if (project['canvas'] is! Map) {
      setState(
        () => _error = 'This project could not be read. Refresh and try again.',
      );
      return;
    }
    final canvas = project['canvas'] as Map;
    setState(() {
      final needsCopy =
          (int.tryParse('${canvas['unsupported_layers']}') ?? 0) > 0;
      _project = needsCopy ? null : int.tryParse('${project['id']}');
      _name.text =
          '${project['name'] ?? 'Untitled design'}${needsCopy ? ' (native copy)' : ''}';
      _error = needsCopy
          ? 'Some web layers cannot be edited here. Text and images are loaded; saving creates a copy and preserves your original.'
          : null;
      _width = (canvas['width'] as num?)?.toDouble() ?? 1080;
      _height = (canvas['height'] as num?)?.toDouble() ?? 1080;
      _editorOnly = true;
      _background = '${canvas['background'] ?? '#FFFFFF'}';
      _layers = (canvas['layers'] as List? ?? [])
          .whereType<Map>()
          .map((layer) => Map<String, dynamic>.from(layer))
          .toList();
      _selected = null;
    });
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Color _color(String hex) =>
      Color(int.tryParse(hex.replaceFirst('#', 'FF'), radix: 16) ?? 0xFF1E2230);
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Turn an idea into your next asset.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _busy
                ? null
                : () => setState(() => _editorOnly = !_editorOnly),
            icon: const Icon(Icons.layers_outlined),
            label: Text(_editorOnly ? 'AI image tools' : 'Advanced canvas'),
          ),
          if (!_editorOnly) ...[
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Start with AI Template'),
                  selected: _mode == 'template',
                  onSelected: (_) => setState(() => _mode = 'template'),
                ),
                ChoiceChip(
                  label: const Text('Start with AI Image'),
                  selected: _mode == 'image',
                  onSelected: (_) => setState(() => _mode = 'image'),
                ),
              ],
            ),
            if (_mode == 'template')
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final template in _templates)
                      ActionChip(
                        label: Text('${template['title']}'),
                        onPressed: () => setState(() {
                          _prompt.text = '${template['prompt']}';
                          _name.text = '${template['title']}';
                          _background = '${template['background']}';
                        }),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _prompt,
              enabled: !_busy,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Describe your design',
                hintText: 'A bold campaign visual with soft studio lighting…',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _generate,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(_busy ? 'Working…' : 'Generate reference'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: _busy ? null : _reference,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: 'Add reference image',
                ),
              ],
            ),
            const SizedBox(height: 12),
            AiModelSelector(
              models: _models,
              selected: _model,
              onSelected: _busy
                  ? null
                  : (id) async {
                      setState(() => _model = id);
                    },
            ),
          ],
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Project name'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ratio in {
                '1:1': [1080.0, 1080.0],
                '9:16': [1080.0, 1920.0],
                '16:9': [1920.0, 1080.0],
              }.entries)
                ChoiceChip(
                  label: Text(ratio.key),
                  selected:
                      (_width / _height - ratio.value[0] / ratio.value[1])
                          .abs() <
                      .001,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() {
                          _width = ratio.value[0];
                          _height = ratio.value[1];
                        }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _CanvasKeepAlive(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = constraints.maxWidth;
                return RepaintBoundary(
                  key: _canvasKey,
                  child: AspectRatio(
                    aspectRatio: _width / _height,
                    child: ClipRect(
                      child: ColoredBox(
                        color: _color(_background),
                        child: Stack(
                          children: [
                            if (_layers.isEmpty)
                              const Center(
                                child: Icon(
                                  Icons.auto_awesome_outlined,
                                  size: 64,
                                  color: Colors.white24,
                                ),
                              ),
                            for (var i = 0; i < _layers.length; i++)
                              Positioned(
                                left: (_layers[i]['x'] as num) * size,
                                top:
                                    (_layers[i]['y'] as num) *
                                    size *
                                    _height /
                                    _width,
                                child: GestureDetector(
                                  onTap: () => setState(() => _selected = i),
                                  onPanUpdate: _busy
                                      ? null
                                      : (details) => setState(() {
                                          _layers[i]['x'] =
                                              ((_layers[i]['x'] as num) +
                                                      details.delta.dx / size)
                                                  .clamp(0, 0.95);
                                          _layers[i]['y'] =
                                              ((_layers[i]['y'] as num) +
                                                      details.delta.dy /
                                                          (size *
                                                              _height /
                                                              _width))
                                                  .clamp(0, 0.95);
                                        }),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: _selected == i
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : Colors.transparent,
                                      ),
                                    ),
                                    child: _layers[i]['type'] == 'image'
                                        ? Image.network(
                                            '${_layers[i]['url']}',
                                            width:
                                                size *
                                                (_layers[i]['size'] as num),
                                            height:
                                                size *
                                                (_layers[i]['size'] as num),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, e, s) =>
                                                const Padding(
                                                  padding: EdgeInsets.all(24),
                                                  child: Icon(
                                                    Icons.broken_image_outlined,
                                                  ),
                                                ),
                                          )
                                        : SizedBox(
                                            width: size * .8,
                                            child: Text(
                                              '${_layers[i]['text']}',
                                              style: TextStyle(
                                                color: _color(
                                                  '${_layers[i]['color'] ?? '#FFFFFF'}',
                                                ),
                                                fontSize:
                                                    size *
                                                    (_layers[i]['size'] as num),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _text,
                icon: const Icon(Icons.text_fields),
                label: const Text('Text'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _reference,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Image'),
              ),
              if (_selected != null)
                IconButton(
                  onPressed: () => setState(() {
                    _layers.removeAt(_selected!);
                    _selected = null;
                  }),
                  icon: const Icon(Icons.delete_outline),
                ),
              for (final color in [
                '#131620',
                '#1E2230',
                '#6366F1',
                '#FFFFFF',
                '#000000',
              ])
                InkWell(
                  onTap: () => setState(() {
                    if (_selected != null &&
                        _layers[_selected!]['type'] == 'text') {
                      _layers[_selected!]['color'] = color;
                    } else {
                      _background = color;
                    }
                  }),
                  child: CircleAvatar(
                    radius: 24,
                    backgroundColor: _color(color),
                    child: _background == color
                        ? const Icon(Icons.check, size: 15)
                        : null,
                  ),
                ),
            ],
          ),
          if (_selected != null)
            Slider(
              value: (_layers[_selected!]['size'] as num).toDouble().clamp(
                .02,
                1,
              ),
              min: .02,
              max: 1,
              onChanged: (value) =>
                  setState(() => _layers[_selected!]['size'] = value),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: _busy || _layers.isEmpty ? null : _save,
                child: const Text('Save project'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _busy || _layers.isEmpty ? null : _export,
                child: const Text('Export PNG'),
              ),
              IconButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _project = null;
                        _layers = [];
                        _selected = null;
                        _name.text = 'Untitled design';
                        _width = _height = 1080;
                        _background = '#1E2230';
                      }),
                icon: const Icon(Icons.add),
                tooltip: 'New project',
              ),
            ],
          ),
          const SizedBox(height: 28),
          Text(
            'Recent projects',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (_projects.isEmpty)
            const Text('Your saved designs will appear here.'),
          for (final project in _projects)
            Card(
              child: ListTile(
                leading: project['preview_url'] is String
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          '${project['preview_url']}',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, e, s) =>
                              const Icon(Icons.image_outlined),
                        ),
                      )
                    : const Icon(Icons.layers_outlined),
                title: Text('${project['name']}'),
                subtitle: Text(
                  '${project['created_at'] ?? ''}'.split('T').first,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(project),
              ),
            ),
          if (_page < _lastPage)
            TextButton(
              onPressed: () => _load(more: true),
              child: const Text('Load more projects'),
            ),
        ],
      ),
    );
  }
}

class _CanvasKeepAlive extends StatefulWidget {
  final Widget child;
  const _CanvasKeepAlive({required this.child});
  @override
  State<_CanvasKeepAlive> createState() => _CanvasKeepAliveState();
}

class _CanvasKeepAliveState extends State<_CanvasKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
