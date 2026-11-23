import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/app_localizations.dart';
import '../../services/mobile_api.dart';
import '../../services/social_post_service.dart';
import '../../theme/app_colors.dart';

String socialPlatformName(Object? value) => switch ('$value') {
  'x' || 'twitter' => 'X',
  'youtube-shorts' || 'youtube_shorts' => 'YouTube Shorts',
  'linkedin' => 'LinkedIn',
  'tiktok' => 'TikTok',
  'youtube' => 'YouTube',
  'instagram' => 'Instagram',
  'facebook' => 'Facebook',
  _ => '$value',
};

String socialPostDate(Object? value) {
  final date = DateTime.tryParse('$value');
  return date == null
      ? '—'
      : DateFormat.yMMMd().add_jm().format(date.toLocal());
}

List<Map<String, dynamic>> socialPostMetrics(Map post) {
  final analytics = post['analytics'];
  final metrics = analytics is Map ? analytics['metrics'] : null;
  return metrics is List
      ? metrics
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList()
      : [];
}

class SocialPostStatus extends StatelessWidget {
  final String status;
  const SocialPostStatus(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final index = switch (status) {
      'published' => 3,
      'scheduled' || 'pending' => 4,
      'failed' => 2,
      _ => 0,
    };
    final color = status == 'failed'
        ? Theme.of(context).colorScheme.error
        : colors.toolAccents[index];
    final label = status.isEmpty
        ? 'Unknown'
        : '${status[0].toUpperCase()}${status.substring(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        appTr(label),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class SocialPostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onReport;
  final VoidCallback? onDelete;
  final bool grid;
  const SocialPostCard({
    super.key,
    required this.post,
    required this.onReport,
    this.onDelete,
    this.grid = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final platforms = (post['platforms'] as List? ?? [])
        .map(socialPlatformName)
        .join(', ');
    final account = '${post['accountName'] ?? ''}';
    final metrics = socialPostMetrics(post)
        .where((m) => m['value'] != null)
        .take(2);
    return Card(
      color: colors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onReport,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(Icons.public, color: colors.primary, size: 20),
                  Text(
                    platforms.isEmpty ? appTr('Social post') : platforms,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SocialPostStatus('${post['status'] ?? 'draft'}'),
                ],
              ),
              if (account.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  account,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted),
                ),
              ],
              if (grid && post['mediaUrl'] != null) ...[
                const SizedBox(height: 12),
                SocialPostMedia(post: post, compact: true),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!grid && post['mediaUrl'] != null) ...[
                    SizedBox(
                      width: 72,
                      height: 72,
                      child: SocialPostMedia(post: post, compact: true),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      '${post['caption'] ?? ''}'.trim().isEmpty
                          ? appTr('No caption')
                          : '${post['caption']}',
                      maxLines: grid ? 4 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.text, height: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${appTr(post['publishedAt'] != null
                    ? 'Published'
                    : post['scheduledAt'] != null
                    ? 'Scheduled'
                    : 'Created')} · ${socialPostDate(post['publishedAt'] ?? post['scheduledAt'] ?? post['createdAt'])}',
                style: TextStyle(color: colors.muted, fontSize: 12),
              ),
              if (metrics.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    for (final metric in metrics)
                      Text(
                        '${appTr('${metric['label']}')}: ${NumberFormat.decimalPattern().format(metric['value'])}',
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onReport,
                    icon: const Icon(Icons.bar_chart_rounded, size: 18),
                    label: Text(appTr('View report')),
                  ),
                  IconButton(
                    tooltip: appTr('Delete post'),
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SocialPostMedia extends StatefulWidget {
  final Map<String, dynamic> post;
  final bool compact;
  const SocialPostMedia({super.key, required this.post, this.compact = false});

  @override
  State<SocialPostMedia> createState() => _SocialPostMediaState();
}

class _SocialPostMediaState extends State<SocialPostMedia> {
  int _image = 0;

  @override
  void didUpdateWidget(covariant SocialPostMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.post['mediaUrl'] != widget.post['mediaUrl'] ||
        '${oldWidget.post['images']}' != '${widget.post['images']}') {
      _image = 0;
    }
  }

  Future<void> _openVideo(String url) async {
    try {
      try {
        await SecureStore.invokeMethod<void>('previewMedia', {'url': url});
      } catch (_) {
        await SecureStore.invokeMethod<void>('openUrl', {'url': url});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appTr('The media preview could not open. Please try again.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final raw = widget.post['images'];
    final images =
        (raw is List && raw.isNotEmpty ? raw : [widget.post['mediaUrl']])
            .whereType<String>()
            .where((url) {
              final uri = Uri.tryParse(url);
              return uri != null &&
                  uri.scheme == 'https' &&
                  uri.host.isNotEmpty &&
                  uri.userInfo.isEmpty;
            })
            .toList();
    final video = widget.post['mediaType'] == 'video';
    final url = '${widget.post['mediaUrl'] ?? ''}';
    final videoUri = Uri.tryParse(url);
    if (video &&
        (videoUri == null ||
            videoUri.scheme != 'https' ||
            videoUri.host.isEmpty ||
            videoUri.userInfo.isNotEmpty)) {
      return const SizedBox.shrink();
    }
    if (images.isEmpty) return const SizedBox.shrink();
    Widget placeholder(IconData icon) => ColoredBox(
      color: colors.input,
      child: Center(
        child: Icon(icon, color: colors.muted, size: widget.compact ? 28 : 48),
      ),
    );
    Widget image(String url) => Image.network(
      url,
      fit: widget.compact ? BoxFit.cover : BoxFit.contain,
      width: double.infinity,
      cacheWidth: widget.compact
          ? 240
          : (MediaQuery.sizeOf(context).width *
                    MediaQuery.devicePixelRatioOf(context))
                .round()
                .clamp(320, 1920),
      errorBuilder: (_, _, _) => placeholder(Icons.broken_image_outlined),
      loadingBuilder: (_, child, loading) =>
          loading == null ? child : placeholder(Icons.image_outlined),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: video
            ? Material(
                color: colors.input,
                child: InkWell(
                  onTap: widget.compact ? null : () => _openVideo(url),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_circle_outline,
                          size: widget.compact ? 30 : 52,
                          color: colors.primary,
                        ),
                        if (!widget.compact)
                          Text(
                            appTr('Play video'),
                            style: TextStyle(color: colors.text),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            : widget.compact || images.length == 1
            ? image(images.first)
            : Stack(
                children: [
                  PageView(
                    key: ValueKey('${widget.post['id']}:${images.join('|')}'),
                    onPageChanged: (index) => setState(() => _image = index),
                    children: [for (final url in images) image(url)],
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text(
                          '${_image + 1} / ${images.length}',
                          style: TextStyle(color: colors.text),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class SocialPostReportScreen extends StatefulWidget {
  final MobileApi api;
  final Map<String, dynamic> initialPost;
  const SocialPostReportScreen({
    super.key,
    required this.api,
    required this.initialPost,
  });

  @override
  State<SocialPostReportScreen> createState() => _SocialPostReportScreenState();
}

class _SocialPostReportScreenState extends State<SocialPostReportScreen> {
  late Map<String, dynamic> _post = widget.initialPost;
  bool _loading = false;
  int _generation = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final post = await SocialPostService(widget.api)
          .post('${widget.initialPost['id']}');
      if (mounted && generation == _generation) setState(() => _post = post);
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

  Future<void> _link(bool copy) async {
    final value = '${_post['link'] ?? ''}';
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      if (copy) {
        await Clipboard.setData(ClipboardData(text: value));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(appTr('Link copied to clipboard.'))),
          );
        }
      } else {
        await SecureStore.invokeMethod<void>('openUrl', {'url': value});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appTr('The post link could not open. Please try again.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final colors = AppColors.of(context);
    final analytics = _post['analytics'] is Map
        ? _post['analytics'] as Map
        : const {};
    final metrics = socialPostMetrics(_post);
    final hasMetrics = metrics.any((metric) => metric['value'] != null);
    final platforms = (_post['platforms'] as List? ?? [])
        .map(socialPlatformName)
        .join(', ');
    final fields = <String, String>{
      'Platform': platforms,
      if ('${_post['accountName'] ?? ''}'.isNotEmpty)
        'Account': '${_post['accountName']}',
      'Post type': '${_post['postType'] ?? 'post'}',
      'Created': socialPostDate(_post['createdAt']),
      'Scheduled': socialPostDate(_post['scheduledAt']),
      'Published': socialPostDate(_post['publishedAt']),
      if (_post['tone'] != null) 'Tone': '${_post['tone']}',
      if (_post['companyId'] != null) 'Company ID': '${_post['companyId']}',
      if (_post['campaignId'] != null) 'Campaign ID': '${_post['campaignId']}',
      if (_post['productId'] != null) 'Product ID': '${_post['productId']}',
    };
    Widget section(String title, List<Widget> children) => Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appTr(title), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
    Widget metricValue(Map metric) {
      final value = metric['value'] is! num
          ? '—'
          : metric['percent'] == true
          ? '${NumberFormat('0.##').format(metric['value'])}%'
          : NumberFormat.decimalPattern().format(metric['value']);
      return Tooltip(
        message: value,
        child: SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: TextStyle(
                color: colors.text,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    final link = Uri.tryParse('${_post['link'] ?? ''}');
    final hasLink =
        link != null &&
        link.scheme == 'https' &&
        link.host.isNotEmpty &&
        link.userInfo.isEmpty;
    return Scaffold(
      backgroundColor: colors.page,
      appBar: AppBar(
        title: Text(appTr('Post report')),
        actions: [
          IconButton(
            tooltip: appTr('Refresh report'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 960),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_error != null)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      appTr(
                                        'Unable to refresh this report. Displaying the last loaded post.',
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(appTr(_error!)),
                                    TextButton(
                                      onPressed: _loading ? null : _load,
                                      child: Text(appTr('Retry')),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              SocialPostStatus('${_post['status'] ?? 'draft'}'),
                              Text(
                                platforms,
                                style: TextStyle(color: colors.muted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (_post['mediaUrl'] != null) ...[
                            SocialPostMedia(post: _post),
                            const SizedBox(height: 16),
                          ],
                          section('Post content', [
                            SelectableText(
                              '${_post['caption'] ?? ''}',
                              style: TextStyle(color: colors.text, height: 1.6),
                            ),
                            if (_post['hashtags'] is List &&
                                (_post['hashtags'] as List).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  (_post['hashtags'] as List).join(' '),
                                  style: TextStyle(color: colors.primary),
                                ),
                              ),
                          ]),
                          section('Post details', [
                            LayoutBuilder(
                              builder: (context, constraints) => Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  for (final field in fields.entries)
                                    SizedBox(
                                      width: constraints.maxWidth < 400
                                          ? constraints.maxWidth
                                          : (constraints.maxWidth - 16) / 2,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            appTr(field.key),
                                            style: TextStyle(
                                              color: colors.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          SelectableText(
                                            field.value.isEmpty
                                                ? '—'
                                                : field.value,
                                            style: TextStyle(
                                              color: colors.text,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            if (hasLink) ...[
                              const SizedBox(height: 16),
                              SelectableText(
                                '$link',
                                style: TextStyle(color: colors.primary),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _link(false),
                                    icon: const Icon(Icons.open_in_new),
                                    label: Text(appTr('Open published post')),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _link(true),
                                    icon: const Icon(Icons.copy),
                                    label: Text(appTr('Copy link')),
                                  ),
                                ],
                              ),
                            ],
                          ]),
                          section('Post analytics', [
                            if (!hasMetrics)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  appTr(
                                    _post['status'] == 'published'
                                        ? 'Analytics are not available yet. Pull to refresh after the platform syncs.'
                                        : 'Analytics are available after this post is published and the platform syncs.',
                                  ),
                                  style: TextStyle(color: colors.muted),
                                ),
                              ),
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final minimumWidth =
                                    150 *
                                    MediaQuery.textScalerOf(context).scale(1);
                                final columns =
                                    ((constraints.maxWidth + 12) /
                                            (minimumWidth + 12))
                                        .floor()
                                        .clamp(1, 3);
                                final items = [
                                  ...metrics,
                                  {
                                    'label': 'Engagements',
                                    'value': analytics['engagementCount'],
                                  },
                                  {
                                    'label': 'Engagement rate',
                                    'value': analytics['engagementRate'],
                                    'percent': true,
                                  },
                                ];
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (final metric in items)
                                      Container(
                                        width:
                                            (constraints.maxWidth -
                                                (columns - 1) * 12) /
                                            columns,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: colors.input,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: colors.outline,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              appTr('${metric['label']}'),
                                              style: TextStyle(
                                                color: colors.muted,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            metricValue(metric),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '${appTr(analytics.containsKey('nextRefreshAt') ? 'Next analytics refresh' : 'Last synced')} · ${socialPostDate(analytics.containsKey('nextRefreshAt') ? analytics['nextRefreshAt'] : analytics['updatedAt'])}',
                              style: TextStyle(
                                color: colors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ]),
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
}
