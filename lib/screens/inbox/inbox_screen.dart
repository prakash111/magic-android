import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/app_localizations.dart';
import '../../services/inbox_service.dart';
import '../../services/mobile_api.dart';
import '../../theme/app_colors.dart';
import '../../widgets/avatar_with_badge.dart';
import 'thread_screen.dart';
import 'widgets.dart';

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
  List<Map<String, dynamic>> chats = [];
  Map<String, dynamic> counts = {};
  int needsReply = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      final result = await widget.service.chats(
        network: network,
        query: search.text,
        needsReply: waiting,
        cursor: more ? cursor : null,
      );
      if (!mounted || ticket != generation) return;
      setState(() {
        final rows = (result['data'] as List? ?? []).whereType<Map>().map(
          (e) => Map<String, dynamic>.from(e),
        );
        final unique = {
          for (final c in more ? chats : <Map<String, dynamic>>[]) c['id']: c,
        };
        for (final c in rows) {
          unique[c['id']] = c;
        }
        chats = unique.values.toList();
        counts = Map<String, dynamic>.from(result['unread'] as Map? ?? {});
        needsReply = (result['needs_reply'] as num?)?.toInt() ?? 0;
        cursor = result['next_cursor'] as String?;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = await widget.service.cached('chats');
      if (!mounted) return;
      setState(() {
        error = e.toString();
        if (chats.isEmpty && cached is Map) {
          chats = (cached['data'] as List? ?? [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      });
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

  Future<void> connectionSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => InboxConnectionsSheet(
        service: widget.service,
        openSettings: () async {
          try {
            await widget.service.openConnections();
            if (context.mounted) Navigator.pop(context);
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(appTr(error.toString()))));
            }
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
        title: Text(appTr('Inbox')),
        actions: [
          IconButton(
            tooltip: appTr('Connection settings'),
            onPressed: connectionSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
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
                      label: Text(
                        '${appTr(item.$2)} ${counts[item.$1.isEmpty ? 'all' : item.$1] ?? 0}',
                      ),
                      onSelected: (_) => filter(item.$1),
                    ),
                  ),
              ],
            ),
          ),
          if (needsReply > 0 || waiting)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                color: colors.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome),
                  title: Text(appTr('AI inbox')),
                  subtitle: Text(
                    appTr(':count chats are waiting for your reply', {
                      'count': needsReply,
                    }),
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
          if (error != null && chats.isNotEmpty)
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
                    empty: 'No conversations yet. Connect Telegram or WhatsApp to get started.',
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
                        final unread = (chat['unread'] as num?)?.toInt() ?? 0;
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
                          subtitle: Text(
                            typing != null
                                ? appTr(':name is typing…', {'name': typing})
                                : '$sender${last?['body'] ?? ''}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: typing != null ? Colors.green : null,
                            ),
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
