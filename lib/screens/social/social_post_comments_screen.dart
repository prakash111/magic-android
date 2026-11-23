import 'package:flutter/material.dart';

import '../../services/app_localizations.dart';
import '../../services/mobile_api.dart';
import '../../services/social_post_service.dart';
import '../../services/social_notification_navigation.dart';
import '../workspace_screen.dart' show SocialAccountsScreen;

class SocialPostCommentsScreen extends StatefulWidget {
  final MobileApi api;
  final String postId;
  final String? commentId;
  const SocialPostCommentsScreen({
    super.key,
    required this.api,
    required this.postId,
    this.commentId,
  });

  @override
  State<SocialPostCommentsScreen> createState() =>
      _SocialPostCommentsScreenState();
}

class _SocialPostCommentsScreenState extends State<SocialPostCommentsScreen> {
  final _comments = <Map<String, dynamic>>[];
  bool _loading = false,
      _supported = true,
      _canReply = false,
      _reconnect = false;
  int _page = 0, _lastPage = 1, _generation = 0;
  String? _next, _error, _notice;

  @override
  void initState() {
    super.initState();
    SocialNotificationNavigation.updates.addListener(_onCommentUpdate);
    _load();
  }

  void _onCommentUpdate() {
    if (SocialNotificationNavigation.updates.value?.postId == widget.postId) {
      _load();
    }
  }

  @override
  void dispose() {
    SocialNotificationNavigation.updates.removeListener(_onCommentUpdate);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading && more) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final remotePage = more && _page >= _lastPage && _next != null;
      final result = await SocialPostService(widget.api).comments(
        widget.postId,
        page: more ? (remotePage ? _page : _page + 1) : 1,
        cursor: remotePage ? _next : null,
        commentId: more ? null : widget.commentId,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final rows = (result['data'] as List).whereType<Map>().map(
          (row) => Map<String, dynamic>.from(row),
        );
        if (!more) _comments.clear();
        for (final row in rows) {
          final index = _comments.indexWhere(
            (existing) => '${existing['id']}' == '${row['id']}',
          );
          if (index < 0) {
            _comments.add(row);
          } else {
            _comments[index] = row;
          }
        }
        _page = (result['current_page'] as num?)?.toInt() ?? 1;
        _lastPage = (result['last_page'] as num?)?.toInt() ?? 1;
        if (!more || remotePage) _next = result['next_cursor'] as String?;
        _supported = result['supported'] == true;
        _canReply = result['can_reply'] == true;
        _notice = result['reason'] as String?;
        _reconnect = result['reconnect_required'] == true;
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

  Future<void> _reply(Map<String, dynamic> comment) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _ReplySheet(api: widget.api, postId: widget.postId, comment: comment),
    );
    if (sent == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(appTr('Comments and replies')),
        actions: [
          IconButton(
            tooltip: appTr('Refresh comments'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (_notice != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(appTr(_notice!)),
                      ),
                    if (_reconnect)
                      TextButton.icon(
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  SocialAccountsScreen(api: widget.api),
                            ),
                          );
                          if (mounted) await _load();
                        },
                        icon: const Icon(Icons.settings_outlined),
                        label: Text(appTr('Open Platforms')),
                      ),
                    if (_error != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(appTr(_error!)),
                              TextButton(
                                onPressed: _load,
                                child: Text(appTr('Retry')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!_loading &&
                        _comments.isEmpty &&
                        _error == null &&
                        _supported)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(appTr('No comments yet. Pull to refresh.')),
                      ),
                    if (_loading && _comments.isEmpty)
                      ...List.generate(
                        3,
                        (_) => const Card(child: SizedBox(height: 96)),
                      ),
                    for (final comment in _comments)
                      Card(
                        key: ValueKey('social-comment-${comment['id']}'),
                        color: '${comment['id']}' == widget.commentId
                            ? Theme.of(context).colorScheme.primaryContainer
                            : null,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${comment['author'] ?? ''}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 8),
                              SelectableText('${comment['text'] ?? ''}'),
                              for (final reply
                                  in (comment['replies'] as List? ?? [])
                                      .whereType<Map>())
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 16,
                                    top: 12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        appTr(
                                          reply['status'] == 'sent'
                                              ? 'Your reply'
                                              : reply['status'] == 'received'
                                              ? '${reply['author'] ?? ''}'
                                              : 'Reply not confirmed',
                                        ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelMedium,
                                      ),
                                      Text('${reply['text'] ?? ''}'),
                                    ],
                                  ),
                                ),
                              if (_canReply && comment['can_reply'] == true)
                                TextButton.icon(
                                  onPressed: () => _reply(comment),
                                  icon: const Icon(Icons.reply),
                                  label: Text(appTr('Reply')),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (_page < _lastPage || _next != null)
                      TextButton(
                        onPressed: _loading ? null : () => _load(more: true),
                        child: Text(appTr('Load more comments')),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplySheet extends StatefulWidget {
  final MobileApi api;
  final String postId;
  final Map<String, dynamic> comment;
  const _ReplySheet({
    required this.api,
    required this.postId,
    required this.comment,
  });
  @override
  State<_ReplySheet> createState() => _ReplySheetState();
}

class _ReplySheetState extends State<_ReplySheet> {
  final _text = TextEditingController();
  String _requestId = SocialPostService.requestId();
  bool _sending = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await SocialPostService(widget.api).replyToComment(
        widget.postId,
        '${widget.comment['id']}',
        _text.text.trim(),
        _requestId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appTr('Reply to :name', {
              'name': '${widget.comment['author'] ?? ''}',
            }),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${widget.comment['text'] ?? ''}',
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _text,
            enabled: !_sending,
            minLines: 2,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(labelText: appTr('Your reply')),
            onChanged: (_) => _requestId = SocialPostService.requestId(),
          ),
          if (_error != null)
            Text(
              appTr(_error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
            label: Text(appTr(_sending ? 'Sending…' : 'Send reply')),
          ),
        ],
      ),
    ),
  );
}
