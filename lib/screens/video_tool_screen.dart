import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../services/app_localizations.dart';
import '../services/mobile_api.dart';
import '../services/video_tool_models.dart';
import '../widgets/tool_render_boundary.dart';
import 'native_workspace_screen.dart' show WorkspaceEmptyState;
import 'server_screen.dart' show RetryPanel;

class VideoToolScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi? api;

  const VideoToolScreen({super.key, required this.module, this.api});

  @override
  State<VideoToolScreen> createState() => _VideoToolScreenState();
}

class _VideoToolScreenState extends State<VideoToolScreen>
    with SingleTickerProviderStateMixin {
  late final MobileApi _client = widget.api ?? MobileApi.instance;
  late final TabController _tabController;

  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  String _aspectRatio = '16:9';
  int _duration = 5;
  String _selectedModel = 'standard';
  String? _selectedAvatar;
  String? _selectedVoice;
  String _avatarStyle = 'rectangular';

  Uint8List? _selectedImageBytes;
  String? _selectedImageName;
  String? _uploadedImageUrl;
  bool _uploadingImage = false;

  bool _loadingConfig = true;
  bool _loadingOutputs = false;
  bool _generating = false;
  String? _error;
  String? _outputsError;
  String? _activeJobId;
  int _activeJobProgress = 0;
  String? _activeJobStatusText;
  Timer? _pollTimer;

  List<VideoModelOption> _modelOptions = const [];
  List<Map<String, dynamic>> _outputs = [];
  int _currentPage = 1;
  int _lastPage = 1;

  String get _toolKey {
    const aliases = {
      'video_pro': 'ai_video_pro',
      'video_to_video': 'ai_video_to_video',
      'auto_edit': 'auto_edit_videos',
    };
    String? fallback;
    for (final key in ['video_tool', 'route_slug', 'id', 'route_type']) {
      final raw = widget.module[key]?.toString().trim() ?? '';
      if (raw.isEmpty) continue;
      final normalized = raw
          .replaceFirst(RegExp(r'^web:'), '')
          .replaceAll('-', '_')
          .toLowerCase();
      final canonical = aliases[normalized] ?? normalized;
      fallback ??= canonical;
      if ([
        'ai_video',
        'ai_video_pro',
        'ai_video_to_video',
        'auto_edit_videos',
        'video_agent',
        'ai_avatar',
        'viral_clips',
        'ai_influencer',
      ].contains(canonical)) {
        return canonical;
      }
    }
    return fallback ?? 'ai_video';
  }

  String get _toolTitle =>
      '${widget.module['display_title'] ?? widget.module['title'] ?? 'AI Video'}';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initDefaults();
    _load();
  }

  void _initDefaults() {
    final key = _toolKey;
    if (key.contains('auto_edit') || key.contains('viral')) {
      _aspectRatio = '9:16';
      _duration = 30;
    } else if (key.contains('avatar') || key.contains('agent')) {
      _duration = 30;
      _promptController.text = 'Welcome to our presentation. Today we will explore innovative solutions.';
    } else {
      _aspectRatio = '16:9';
      _duration = 5;
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    _promptController.dispose();
    _titleController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingConfig = true;
      _error = null;
    });

    try {
      final configRes = await _client
          .request('/video/tools')
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      final config = VideoToolConfiguration.fromResponse(
        configRes,
        tool: _toolKey,
        previousModel: _selectedModel,
      );
      setState(() {
        _modelOptions = config.models;
        _selectedModel = config.selectedModel;
        _loadingConfig = false;
      });

      await _loadOutputs();
    } on FormatException catch (e) {
      if (mounted) {
        setState(
          () => _error = e.message.startsWith('No video models')
              ? appTr(e.message)
              : appTr('Video settings could not be displayed. Please retry.'),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingConfig = false);
      }
    }
  }

  Future<void> _loadOutputs({bool append = false}) async {
    if (!mounted) return;
    setState(() {
      _loadingOutputs = true;
      _outputsError = null;
    });

    try {
      final page = append ? _currentPage + 1 : 1;
      final res = await _client
          .request('/video/outputs?tool=$_toolKey&page=$page')
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res is! Map || res['data'] is! List) {
        throw const ApiFailure(
          'Video history could not be loaded. Please retry.',
        );
      }
      {
        final list = (res['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        setState(() {
          _currentPage = int.tryParse('${res['current_page']}') ?? 1;
          _lastPage = int.tryParse('${res['last_page']}') ?? 1;
          _outputs = append ? [..._outputs, ...list] : list;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _outputsError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingOutputs = false);
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final name = picked.name;

      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = name;
        _uploadingImage = true;
      });

      final url = await _client.uploadImage(bytes, name);
      if (mounted) {
        setState(() {
          _uploadedImageUrl = url;
          _uploadingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(appTr('Source image uploaded successfully'))),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appTr('Failed to upload image: :err', {'err': e.toString()}),
            ),
          ),
        );
      }
    }
  }

  Future<void> _generate() async {
    final prompt = _promptController.text.trim();
    final urlInput = _urlController.text.trim();

    if (_toolKey.contains('viral') && urlInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appTr('Please enter a YouTube video URL or source link'),
          ),
        ),
      );
      return;
    }

    if (!_toolKey.contains('viral') && prompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appTr('Please enter a prompt or script for the video')),
        ),
      );
      return;
    }

    setState(() {
      _generating = true;
      _activeJobProgress = 10;
      _activeJobStatusText = appTr('Submitting generation request...');
    });

    try {
      final payload = <String, dynamic>{
        'tool': _toolKey,
        'prompt': prompt,
        'title': _titleController.text.trim(),
        'aspect_ratio': _aspectRatio,
        'duration': _duration,
        'model': _selectedModel,
        if (_uploadedImageUrl != null) 'image_url': _uploadedImageUrl,
        if (urlInput.isNotEmpty) 'video_url': urlInput,
        if (_selectedAvatar != null) 'avatar_id': _selectedAvatar,
        if (_selectedVoice != null) 'voice_id': _selectedVoice,
        if (_avatarStyle.isNotEmpty) 'style': _avatarStyle,
      };

      final res = await _client.request(
        '/video/generate',
        method: 'POST',
        body: payload,
      );

      if (res is Map && res['id'] != null) {
        final jobId = '${res['id']}';
        setState(() {
          _activeJobId = jobId;
          _activeJobProgress = 25;
          _activeJobStatusText = appTr('Queued for video rendering...');
        });

        _startPolling(jobId);
      } else {
        throw ApiFailure(
          res is Map
              ? '${res['message'] ?? 'Unexpected response'}'
              : 'Failed to start generation',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _generating = false;
          _activeJobId = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(appTr(e.toString()))));
      }
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final res = await _client.request('/video/check/$jobId');
        if (!mounted) return;

        if (res is Map) {
          final status = '${res['status']}'.toLowerCase();
          final progress = res['progress'] as int? ?? 50;
          final msg = res['message'] as String? ?? appTr('Rendering video...');

          setState(() {
            _activeJobProgress = progress;
            _activeJobStatusText = msg;
          });

          if (status == 'completed' ||
              status == 'complete' ||
              status == 'success') {
            timer.cancel();
            setState(() {
              _generating = false;
              _activeJobId = null;
            });

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(appTr('Video generated successfully!'))),
            );

            await _loadOutputs();
            if (mounted) {
              _tabController.animateTo(1);
            }
          } else if (status == 'failed' || status == 'error') {
            timer.cancel();
            setState(() {
              _generating = false;
              _activeJobId = null;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  appTr('Video rendering failed: :msg', {'msg': msg}),
                ),
              ),
            );
          }
        }
      } catch (_) {
        // Continue polling silently on transient timeout
      }
    });
  }

  Future<void> _deleteOutput(Map<String, dynamic> video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appTr('Delete video')),
        content: Text(
          appTr('Are you sure you want to permanently delete this video?'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(appTr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(appTr('Delete')),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final id = video['id'];
      await _client.request('/video/outputs/$id', method: 'DELETE');
      setState(() {
        _outputs.removeWhere((item) => item['id'] == id);
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(appTr('Video deleted'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appTr('Failed to delete video: :err', {'err': e.toString()}),
            ),
          ),
        );
      }
    }
  }

  void _showPlayModal(Map<String, dynamic> video) {
    final title = '${video['title'] ?? 'Video Output'}';
    final videoUrl = '${video['video_url'] ?? ''}';
    final duration = video['duration_seconds'] != null
        ? '${video['duration_seconds']}s'
        : null;
    final res = video['resolution'] ?? video['target_resolution'];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(ctx).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text('${video['status'] ?? 'complete'}')),
                  if (duration != null) Chip(label: Text(duration)),
                  if (res != null) Chip(label: Text('$res')),
                ],
              ),
              const SizedBox(height: 16),
              if (video['thumbnail_url'] != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    '${video['thumbnail_url']}',
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: videoUrl));
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              appTr('Video URL copied to clipboard'),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(appTr('Copy link')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        final box = ctx.findRenderObject() as RenderBox?;
                        SharePlus.instance.share(
                          ShareParams(
                            text: appTr('Watch this video: :url', {
                              'url': videoUrl,
                            }),
                            sharePositionOrigin: box == null
                                ? null
                                : box.localToGlobal(Offset.zero) & box.size,
                          ),
                        );
                      },
                      icon: const Icon(Icons.share_rounded),
                      label: Text(appTr('Share video')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appTr(_toolTitle)),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              icon: const Icon(Icons.auto_awesome_rounded),
              text: appTr('Create'),
            ),
            Tab(
              icon: const Icon(Icons.video_library_outlined),
              text: appTr('Gallery (:count)', {'count': '${_outputs.length}'}),
            ),
          ],
        ),
      ),
      body: _loadingConfig
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: RetryPanel(message: appTr(_error!), retry: _load),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                ToolRenderBoundary(
                  message: appTr(
                    'Video settings could not be displayed. Please retry.',
                  ),
                  onRetry: _load,
                  builder: (_) => _buildCreateTab(),
                ),
                ToolRenderBoundary(
                  message: appTr(
                    'Video history could not be displayed. Please retry.',
                  ),
                  onRetry: _loadOutputs,
                  builder: (_) => _buildGalleryTab(),
                ),
              ],
            ),
    );
  }

  Widget _buildCreateTab() {
    final key = _toolKey;
    final isViral = key.contains('viral');
    final isAvatar = key.contains('avatar') || key.contains('agent');
    final isAutoEdit = key.contains('auto_edit');
    final engineModels = _modelOptions;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_generating) _buildActiveProgressCard(),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appTr('Video Configuration'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),

                  if (isViral) ...[
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(
                        labelText: appTr('YouTube / Video URL'),
                        hintText: 'https://www.youtube.com/watch?v=...',
                        prefixIcon: const Icon(Icons.link_rounded),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: appTr('Video Title (optional)'),
                      hintText: appTr('My cinematic clip'),
                      prefixIcon: const Icon(Icons.title_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),

                  TextField(
                    controller: _promptController,
                    maxLines: isAvatar ? 5 : 3,
                    decoration: InputDecoration(
                      labelText: isAvatar
                          ? appTr('Avatar Speech Script')
                          : appTr('Visual Prompt / Instructions'),
                      hintText: isAvatar
                          ? appTr('Type what the presenter should say...')
                          : appTr(
                              'Cinematic lighting, camera panning over mountain peak...',
                            ),
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (!isViral && !isAvatar && !isAutoEdit) ...[
                    Text(
                      appTr('Source Image (optional)'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickImage,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 120),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                            style: BorderStyle.solid,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: .3),
                        ),
                        child: _uploadingImage
                            ? const SizedBox(
                                height: 120,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            : _selectedImageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _selectedImageBytes!,
                                  fit: BoxFit.cover,
                                  height: 120,
                                  width: double.infinity,
                                ),
                              )
                            : Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 36,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _selectedImageName ??
                                          appTr('Tap to pick source image'),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (engineModels.isNotEmpty) ...[
                    Text(
                      appTr('Engine Model'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('video-engine-$_toolKey-$_selectedModel'),
                      initialValue: _selectedModel,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.tune_rounded),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: engineModels.map((m) {
                        return DropdownMenuItem<String>(
                          value: m.id,
                          child: Text(
                            appTr(m.label),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedModel = val);
                      },
                    ),
                    const SizedBox(height: 16),
                  ],

                  if (isAvatar) ...[
                    Text(
                      appTr('Avatar Framing'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: ['rectangular', 'circle', 'close-up'].map((
                        style,
                      ) {
                        final selected = _avatarStyle == style;
                        return ChoiceChip(
                          label: Text(appTr(style)),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _avatarStyle = style),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                  ],

                  Text(
                    appTr('Aspect Ratio'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['16:9', '9:16', '1:1'].map((ratio) {
                      final selected = _aspectRatio == ratio;
                      return ChoiceChip(
                        label: Text(ratio),
                        selected: selected,
                        onSelected: (_) => setState(() => _aspectRatio = ratio),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    appTr('Target Duration'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [5, 10, 15, 30, 60].map((dur) {
                      final selected = _duration == dur;
                      return ChoiceChip(
                        label: Text('${dur}s'),
                        selected: selected,
                        onSelected: (_) => setState(() => _duration = dur),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _generating ? null : _generate,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        minimumSize: const Size(48, 52),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _generating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              appTr(
                                _generating
                                    ? 'Generating Video...'
                                    : 'Generate Video',
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildActiveProgressCard() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: .4),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    appTr('Active Generation in Progress'),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Text('$_activeJobProgress%'),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _activeJobProgress / 100.0),
            const SizedBox(height: 8),
            Text(
              _activeJobStatusText ?? appTr('Rendering frames...'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (_activeJobId != null) ...[
              const SizedBox(height: 4),
              Text(
                'Task ID: $_activeJobId',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGalleryTab() {
    if (_loadingOutputs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_outputsError != null) {
      return Center(
        child: RetryPanel(message: appTr(_outputsError!), retry: _loadOutputs),
      );
    }

    if (_outputs.isEmpty) {
      return Center(
        child: WorkspaceEmptyState(
          icon: Icons.movie_creation_outlined,
          title: appTr('No videos generated yet'),
          message: appTr(
            'Configure your prompt and settings in the Create tab to generate your first video.',
          ),
          actionLabel: appTr('Create a video'),
          onAction: () => _tabController.animateTo(0),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOutputs,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _outputs.length + (_currentPage < _lastPage ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _outputs.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: TextButton(
                  onPressed: () => _loadOutputs(append: true),
                  child: Text(appTr('Load more videos')),
                ),
              ),
            );
          }

          final video = _outputs[index];
          final title = '${video['title'] ?? 'Video Output #${video['id']}'}';
          final thumbnail = video['thumbnail_url'];
          final thumb = thumbnail is String ? thumbnail : null;
          final status = '${video['status'] ?? 'complete'}';
          final duration = video['duration_seconds'] != null
              ? '${video['duration_seconds']}s'
              : null;
          final tool = video['tool_label'] ?? video['tool'];

          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showPlayModal(video),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (thumb != null && thumb.startsWith('http'))
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.network(
                          thumb,
                          height: 160,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 120,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            child: const Center(
                              child: Icon(
                                Icons.movie_creation_outlined,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                        CircleAvatar(
                          backgroundColor: Colors.black54,
                          radius: 26,
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      height: 100,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.movie_creation_outlined, size: 40),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                status,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                            ),
                            if (duration != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                duration,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (tool != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '•  $tool',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _deleteOutput(video),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
