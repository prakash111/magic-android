import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_localizations.dart';
import '../../services/inbox_service.dart';
import '../../services/mobile_api.dart';
import '../../theme/app_colors.dart';
import '../../widgets/avatar_with_badge.dart';
import 'thread_screen.dart';
import 'widgets.dart';
import '../workspace_screen.dart' show openMarketingBotSettings;

class InboxScreen extends StatefulWidget {
  final InboxService service;
  InboxScreen({super.key, InboxService? service, MobileApi? api})
    : service = service ?? InboxService.forApi(api ?? MobileApi.instance);
  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> with WidgetsBindingObserver {
  final search = TextEditingController();
  Timer? poll, debounce;
  String network = '';
  bool waiting = false, loading = true, busy = false, active = true;
  bool reloadPending = false;
  String? error, cursor;
  int generation = 0;
  InboxState get inbox => widget.service.state;
  List<Map<String, dynamic>> get chats => inbox.chats;
  int get needsReply => inbox.counts?.needsReply ?? 0;
  int _refreshSignal = 0;

  void stateChanged() {
    if (!mounted) return;
    setState(() {});
    if (_refreshSignal != inbox.refreshSignal) {
      _refreshSignal = inbox.refreshSignal;
      unawaited(load(silent: true));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    inbox.addListener(stateChanged);
    inbox.attachInbox();
    _refreshSignal = inbox.refreshSignal;
    load();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (active && (ModalRoute.of(context)?.isCurrent ?? true)) {
        load(silent: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) load(silent: true);
  }

  Future<void> load({bool silent = false, bool more = false}) async {
    if (busy) {
      if (!silent) {
        generation++;
        reloadPending = true;
      }
      return;
    }
    busy = true;
    final ticket = ++generation;
    if (!silent && !more) setState(() => loading = true);
    try {
      unawaited(widget.service.flush().catchError((_) {}));
      final applied = await widget.service.loadChats(
        network: network,
        query: search.text,
        needsReply: waiting,
        cursor: more ? cursor : null,
        append: more,
      );
      if (!mounted || ticket != generation) return;
      if (!applied) reloadPending = true;
      setState(() {
        cursor = inbox.cursor;
        error = null;
        if (waiting && needsReply == 0) {
          waiting = false;
          reloadPending = true;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      busy = false;
      if (mounted) {
        setState(() => loading = false);
        if (reloadPending) {
          reloadPending = false;
          unawaited(load());
        }
      }
    }
  }

  void filter(String value) {
    network = value;
    cursor = null;
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 200), () => load());
    setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    inbox.removeListener(stateChanged);
    inbox.detachInbox();
    poll?.cancel();
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Navigator.canPop(context) ? const BackButton() : null,
        title: Text(appTr('Inbox')),
        actions: [
          IconButton(
            tooltip: appTr('Refresh'),
            onPressed: () => load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: appTr('Search for chats…'),
              ),
              onChanged: (_) {
                debounce?.cancel();
                debounce = Timer(
                  const Duration(milliseconds: 300),
                  () => load(),
                );
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                for (final item in [
                  ('', 'All'),
                  ('tg', 'Telegram'),
                  ('wa', 'WhatsApp'),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      selected: network == item.$1,
                      showCheckmark: false,
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: item.$1 == 'tg'
                                  ? const Color(0xff22a9df)
                                  : item.$1 == 'wa'
                                  ? const Color(0xff22c55e)
                                  : colors.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(appTr(item.$2)),
                          if (inbox.countsLoading) ...[
                            const SizedBox(width: 6),
                            Container(
                              key: ValueKey('inbox-count-skeleton-${item.$1}'),
                              width: 18,
                              height: 14,
                              decoration: BoxDecoration(
                                color: colors.muted.withValues(alpha: .2),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ] else if ((inbox.counts?.network(item.$1) ?? 0) >
                              0) ...[
                            const SizedBox(width: 6),
                            Badge(
                              key: ValueKey('inbox-tab-badge-${item.$1}'),
                              backgroundColor: item.$1 == 'tg'
                                  ? const Color(0xff168abe)
                                  : item.$1 == 'wa'
                                  ? const Color(0xff15803d)
                                  : colors.primary,
                              label: Text(
                                InboxCounts.badge(
                                  inbox.counts!.network(item.$1),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      onSelected: (_) => filter(item.$1),
                    ),
                  ),
              ],
            ),
          ),
          if (inbox.countsError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      appTr(
                        'Counts could not refresh. Showing last known counts.',
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () => load(),
                    child: Text(appTr('Retry')),
                  ),
                ],
              ),
            ),
          if (needsReply > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: colors.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(appTr('AI inbox')),
                  subtitle: Text(
                    appTr(
                      needsReply == 1
                          ? ':count chat is waiting for your reply'
                          : ':count chats are waiting for your reply',
                      {'count': needsReply},
                    ),
                  ),
                  trailing: waiting
                      ? const Icon(Icons.close)
                      : const Icon(Icons.chevron_right),
                  onTap: () {
                    setState(() => waiting = !waiting);
                    load();
                  },
                ),
              ),
            ),
          if (error != null && chats.isNotEmpty && inbox.countsError == null)
            MaterialBanner(
              content: Text(appTr(error!)),
              actions: [
                TextButton(
                  onPressed: () => load(),
                  child: Text(appTr('Retry')),
                ),
              ],
            ),
          Expanded(
            child: loading && chats.isEmpty || chats.isEmpty
                ? InboxStateView(
                    loading: loading,
                    error: error,
                    empty: (inbox.counts?.chatsTotal ?? 0) == 0
                        ? 'No chats yet. Connect Telegram or WhatsApp in Marketing Bot settings.'
                        : 'No chats match your search.',
                    actionLabel:
                        !loading &&
                            error == null &&
                            (inbox.counts?.chatsTotal ?? 0) == 0
                        ? 'Open Marketing Bot settings'
                        : null,
                    action: () => openMarketingBotSettings(
                      context,
                      api: widget.service.api,
                    ),
                    retry: () => load(),
                  )
                : RefreshIndicator(
                    onRefresh: () => load(),
                    child: ListView.builder(
                      itemCount: chats.length + (cursor == null ? 0 : 1),
                      itemBuilder: (context, index) {
                        if (index == chats.length) {
                          return TextButton(
                            onPressed: () => load(more: true),
                            child: Text(appTr('Load more')),
                          );
                        }
                        final chat = chats[index];
                        final last = chat['last_message'] as Map?;
                        final unread = inboxNumber(chat['unread']);
                        final isGroup = chat['is_group'] == true;
                        final sender = isGroup && last?['direction'] == 'in'
                            ? '${last?['sender_name'] ?? ''}: '
                            : '';
                        final typing = chat['typing_name'];
                        return ListTile(
                          minVerticalPadding: 12,
                          leading: AvatarWithBadge(
                            name: '${chat['title']}',
                            network: '${chat['network']}',
                            url: chat['photo_url'] as String?,
                          ),
                          title: Row(
                            children: [
                              if (chat['pinned'] == true)
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(end: 4),
                                  child: Icon(Icons.push_pin, size: 14),
                                ),
                              Expanded(
                                child: Text(
                                  '${chat['title']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${appTr(isGroup ? 'Group' : 'Chat')} · ${chat['remote_id'] ?? chat['id']}${chat['members'] == null ? '' : ' · ${appTr(':count members', {'count': chat['members']})}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              Text(
                                typing != null
                                    ? appTr(':name is typing…', {
                                        'name': typing,
                                      })
                                    : '$sender${last?['body'] ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: typing != null ? Colors.green : null,
                                ),
                              ),
                            ],
                          ),
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                inboxTime(chat['last_at']),
                                style: Theme.of(context).textTheme.labelSmall,
                              ),
                              if (unread > 0)
                                Badge(
                                  backgroundColor: chat['muted'] == true
                                      ? colors.muted
                                      : colors.primary,
                                  label: Text('$unread'),
                                ),
                            ],
                          ),
                          onTap: () async {
                            inbox.markRead(chat['id'] as int);
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => ThreadScreen(
                                  service: widget.service,
                                  chat: chat,
                                ),
                              ),
                            );
                            if (mounted) load(silent: true);
                          },
                          onLongPress: () async {
                            await widget.service.pin(
                              chat['id'] as int,
                              pinned: chat['pinned'] != true,
                            );
                            load(silent: true);
                          },
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
