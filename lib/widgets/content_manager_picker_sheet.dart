import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/content_manager_service.dart';
import '../services/mobile_api.dart';

class ContentManagerPickerSheet extends StatefulWidget {
  final ContentManagerService service;
  final String initialType;
  final Set<String> allowedTypes;
  const ContentManagerPickerSheet({
    super.key,
    required this.service,
    this.initialType = 'image',
    this.allowedTypes = const {'image', 'video', 'other'},
  });

  static Future<ContentManagerAsset?> show(
    BuildContext context, {
    required MobileApi api,
    String initialType = 'image',
    Set<String> allowedTypes = const {'image', 'video', 'other'},
  }) => showModalBottomSheet<ContentManagerAsset>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: false,
    isDismissible: false,
    builder: (_) => ContentManagerPickerSheet(
      service: ContentManagerService(api),
      initialType: initialType,
      allowedTypes: allowedTypes,
    ),
  );

  @override
  State<ContentManagerPickerSheet> createState() =>
      _ContentManagerPickerSheetState();
}

class _ContentManagerPickerSheetState extends State<ContentManagerPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final List<ContentManagerAsset> _items = [];
  Timer? _debounce;
  String _sort = 'newest';
  String? _error, _notice;
  bool _loading = true, _uploading = false;
  double _progress = 0;
  int _page = 0, _lastPage = 1, _generation = 0, _maxBytes = 25 * 1024 * 1024;
  static const _types = ['all', 'images', 'videos', 'other'];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialType == 'video'
          ? 2
          : widget.initialType == 'other'
          ? 3
          : 1,
    );
    _activeTab = _tabs.index;
    _tabs.addListener(_tabChanged);
    _scroll.addListener(() {
      if (_scroll.hasClients &&
          _scroll.position.extentAfter < 300 &&
          !_loading &&
          _error == null &&
          _page < _lastPage) {
        _load();
      }
    });
    _load(reset: true);
  }

  void _tabChanged() {
    if (!_tabs.indexIsChanging && _tabs.index != _activeTab) {
      _activeTab = _tabs.index;
      _load(reset: true);
    }
  }

  int _activeTab = 1;

  Future<void> _load({bool reset = false}) async {
    final generation = reset ? ++_generation : _generation;
    if (reset) {
      _items.clear();
      _page = 0;
      _lastPage = 1;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.list(
        type: _types[_tabs.index],
        sort: _sort,
        search: _search.text.trim(),
        page: _page + 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final ids = _items.map((item) => item.id).toSet();
        _items.addAll(result.items.where((item) => ids.add(item.id)));
        _page = result.page;
        _lastPage = result.lastPage;
        _maxBytes = result.maxUploadBytes;
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

  void _select(ContentManagerAsset asset) {
    if (!widget.allowedTypes.contains(asset.type)) {
      setState(
        () => _notice = appTr(
          'This post supports images and videos. Other files remain available in your library.',
        ),
      );
      return;
    }
    Navigator.pop(context, asset);
  }

  Future<void> _upload(String kind) async {
    setState(() {
      _uploading = true;
      _progress = 0;
      _notice = null;
    });
    try {
      final file = await widget.service.pick(kind, _maxBytes);
      if (file == null || !mounted) return;
      final asset = await widget.service.upload(
        file,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      if (widget.allowedTypes.contains(asset.type)) {
        _select(asset);
      } else {
        _tabs.index = 3;
        setState(
          () => _notice = appTr(
            'Uploaded to your library. Choose an image or video for this post.',
          ),
        );
        await _load(reset: true);
      }
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tabs.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return PopScope(
      canPop: !_uploading,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            appTr('Content Manager'),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: _uploading
                              ? null
                              : () => Navigator.pop(context),
                          tooltip: appTr('Close'),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabs,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      for (final label in [
                        'Upload Files',
                        'Images',
                        'Videos',
                        'Other Files',
                      ])
                        Tab(text: appTr(label)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final search = TextField(
                          controller: _search,
                          decoration: InputDecoration(
                            labelText: appTr('Search media'),
                            prefixIcon: const Icon(Icons.search),
                          ),
                          onChanged: (_) {
                            _debounce?.cancel();
                            _debounce = Timer(
                              const Duration(milliseconds: 300),
                              () => _load(reset: true),
                            );
                          },
                        );
                        final sort = DropdownButtonFormField<String>(
                          initialValue: _sort,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: appTr('Sort by'),
                          ),
                          items: [
                            for (final entry in {
                              'newest': 'Newest first',
                              'oldest': 'Oldest first',
                              'name': 'Name',
                            }.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(appTr(entry.value)),
                              ),
                          ],
                          onChanged: _uploading
                              ? null
                              : (value) {
                                  if (value != null) {
                                    _sort = value;
                                    _load(reset: true);
                                  }
                                },
                        );
                        return constraints.maxWidth < 500
                            ? Column(
                                children: [
                                  search,
                                  const SizedBox(height: 12),
                                  sort,
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(child: search),
                                  const SizedBox(width: 12),
                                  SizedBox(width: 200, child: sort),
                                ],
                              );
                      },
                    ),
                  ),
                  if (_tabs.index == 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final entry in {
                                'image': 'Upload image',
                                'video': 'Upload video',
                                'file': 'Upload file',
                              }.entries)
                                OutlinedButton.icon(
                                  onPressed: _uploading
                                      ? null
                                      : () => _upload(entry.key),
                                  icon: Icon(
                                    entry.key == 'video'
                                        ? Icons.video_library_outlined
                                        : entry.key == 'image'
                                        ? Icons.image_outlined
                                        : Icons.upload_file,
                                  ),
                                  label: Text(appTr(entry.value)),
                                ),
                            ],
                          ),
                          Text(
                            appTr('Maximum upload size: :value MB', {
                              'value': '${(_maxBytes / (1024 * 1024)).round()}',
                            }),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  if (_uploading)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _progress == 0 ? null : _progress,
                          ),
                          Text(
                            appTr('Uploading… :value%', {
                              'value': '${(_progress * 100).round()}',
                            }),
                          ),
                        ],
                      ),
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        appTr(_notice!),
                        semanticsLabel: appTr(_notice!),
                      ),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _load(reset: true),
                      child: _body(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (_items.isEmpty && !_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 40),
          Icon(_error == null ? Icons.folder_open : Icons.cloud_off, size: 48),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              appTr(
                _error ??
                    'No media found. Upload a file or try another search.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (_error != null)
            Center(
              child: TextButton(
                onPressed: () => _load(reset: true),
                child: Text(appTr('Retry')),
              ),
            ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 650 ? 3 : 2;
        final scale = MediaQuery.textScalerOf(context).scale(1);
        return GridView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: 172 + 45 * scale,
          ),
          itemCount:
              _items.length +
              (_loading
                  ? columns * 2
                  : _error != null
                  ? 1
                  : 0),
          itemBuilder: (context, index) {
            if (index >= _items.length) {
              if (_error != null) {
                return Center(
                  child: TextButton(
                    onPressed: () => _load(),
                    child: Text(appTr('Retry')),
                  ),
                );
              }
              return Semantics(
                label: appTr('Loading media'),
                child: Card(
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: LinearProgressIndicator(),
                      ),
                    ],
                  ),
                ),
              );
            }
            final asset = _items[index];
            return Semantics(
              button: true,
              label: '${asset.title}, ${appTr(asset.type)}',
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _uploading ? null : () => _select(asset),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ContentManagerThumbnail(asset: asset),
                            if (asset.type == 'video')
                              const Center(
                                child: Icon(
                                  Icons.play_circle_fill,
                                  size: 44,
                                  color: Colors.white,
                                ),
                              ),
                            Positioned(
                              bottom: 6,
                              right: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Text(
                                    asset.duration != null
                                        ? '${asset.duration!.round()}s'
                                        : asset.mimeType
                                              .split('/')
                                              .last
                                              .toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          asset.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class ContentManagerThumbnail extends StatelessWidget {
  final ContentManagerAsset asset;
  const ContentManagerThumbnail({super.key, required this.asset});
  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Icon(
        asset.type == 'video'
            ? Icons.movie_outlined
            : asset.type == 'image'
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        size: 42,
      ),
    );
    final url = asset.thumbnailUrl;
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: url == null
          ? fallback
          : Image.network(
              url,
              fit: BoxFit.cover,
              cacheWidth: 480,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => fallback,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes == null
                            ? null
                            : progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!,
                      ),
                    ),
            ),
    );
  }
}
