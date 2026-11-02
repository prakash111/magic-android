import '../screens/workspace_screen.dart' show openMarketingBotSettings;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/inbox_service.dart';
import '../services/mobile_api.dart';
import '../screens/inbox/inbox_screen.dart';
import '../screens/inbox/widgets.dart';
import 'avatar_with_badge.dart';

Future<void> showSendToNetwork(
  BuildContext context, {
  required String text,
  required MobileApi api,
  String? model,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => SendToNetworkSheet(
    service: InboxService.forApi(api),
    text: text,
    model: model,
  ),
);

class SendToNetworkSheet extends StatefulWidget {
  final InboxService service;
  final String text;
  final String? model;
  const SendToNetworkSheet({
    super.key,
    required this.service,
    required this.text,
    this.model,
  });
  @override
  State<SendToNetworkSheet> createState() => _SendToNetworkSheetState();
}

class _SendToNetworkSheetState extends State<SendToNetworkSheet> {
  late final preview = TextEditingController(text: widget.text);
  final search = TextEditingController();
  String network = '';
  List<Map<String, dynamic>> chats = [], networks = [], results = [];
  Set<int> selected = {};
  String? error, cursor;
  bool loading = true, sending = false, fix = false;
  Timer? debounce, deliveryPoll;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool more = false}) async {
    final ticket = ++generation;
    if (!more) setState(() => loading = true);
    try {
      final data = await widget.service.chats(
        network: network,
        query: search.text,
        cursor: more ? cursor : null,
      );
      if (!mounted || ticket != generation) return;
      setState(() {
        final rows = (data['data'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        chats = more ? [...chats, ...rows] : rows;
        cursor = data['next_cursor'] as String?;
        networks = (data['networks'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted && ticket == generation) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    if (selected.isEmpty || sending) return;
    setState(() => sending = true);
    try {
      final data = await widget.service.forward(
        preview.text,
        selected.toList(),
        fix: fix,
        model: widget.model,
      );
      if (mounted) {
        setState(() => results = data);
        deliveryPoll = Timer.periodic(
          const Duration(seconds: 5),
          (_) => refreshDelivery(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> refreshDelivery() async {
    final ids = results
        .where((r) => r['message_id'] != null)
        .map((r) => r['message_id'] as int)
        .toList();
    if (ids.isEmpty) return;
    try {
      final statuses = await widget.service.sendStatus(ids);
      if (!mounted) return;
      setState(() {
        for (final row in results) {
          final status = statuses
              .where((s) => s['id'] == row['message_id'])
              .firstOrNull;
          if (status != null) {
            row['status'] = status['status'];
            if (status['error_code'] != null) {
              row['error'] = status['error_code'] == 'template_required'
                  ? 'The WhatsApp reply window is closed. Choose an approved template.'
                  : 'Delivery failed. Open Inbox to retry.';
            }
          }
        }
      });
      if (results.every((r) => !['queued', 'sending'].contains(r['status']))) {
        deliveryPoll?.cancel();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    debounce?.cancel();
    deliveryPoll?.cancel();
    preview.dispose();
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              appTr('Send to network'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              appTr('Send from your connected Telegram and WhatsApp accounts.'),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
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
                        label: Text(
                          '${appTr(item.$2)}${item.$1.isNotEmpty && !networks.any((n) => n['network'] == item.$1 && n['status'] == 'connected') ? ' · ${appTr('Connect')}' : ''}',
                        ),
                        selected: network == item.$1,
                        onSelected:
                            item.$1.isEmpty ||
                                networks.any(
                                  (n) =>
                                      n['network'] == item.$1 &&
                                      n['status'] == 'connected',
                                )
                            ? (_) {
                                setState(() => network = item.$1);
                                load();
                              }
                            : null,
                      ),
                    ),
                ],
              ),
            ),
            if (results.any((r) => r['ai_fallback'] == true))
              Text(appTr('AI unavailable. Messages were sent as typed.')),
            if (results.isEmpty) ...[
              if (!networks.any((network) => network['status'] == 'connected'))
                TextButton(
                  onPressed: () async {
                    await openMarketingBotSettings(
                      context,
                      api: widget.service.api,
                    );
                    if (mounted) await load();
                  },
                  child: Text(appTr('Connect a network')),
                ),
              TextField(
                controller: search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: appTr('Search chats…'),
                ),
                onChanged: (_) {
                  debounce?.cancel();
                  debounce = Timer(
                    const Duration(milliseconds: 300),
                    () => load(),
                  );
                },
              ),
              Expanded(
                child: loading
                    ? InboxStateView(loading: true, empty: '', retry: load)
                    : chats.isEmpty
                    ? InboxStateView(
                        error: error,
                        empty: 'No connected chats yet.',
                        retry: load,
                      )
                    : ListView.builder(
                        itemCount: chats.length + (cursor == null ? 0 : 1),
                        itemBuilder: (context, index) {
                          if (index == chats.length) {
                            return TextButton(
                              onPressed: () => load(more: true),
                              child: Text(appTr('Load more')),
                            );
                          }
                          final chat = chats[index];
                          final healthy =
                              chat['connection_status'] == 'connected';
                          return CheckboxListTile(
                            value: selected.contains(chat['id']),
                            onChanged: healthy
                                ? (value) => setState(
                                    () => value == true
                                        ? selected.add(chat['id'] as int)
                                        : selected.remove(chat['id']),
                                  )
                                : null,
                            secondary: AvatarWithBadge(
                              name: '${chat['title']}',
                              network: '${chat['network']}',
                              url: chat['photo_url'] as String?,
                            ),
                            title: Text('${chat['title']}'),
                            subtitle: Text(
                              appTr(
                                healthy
                                    ? (chat['network'] == 'tg'
                                          ? 'Telegram'
                                          : 'WhatsApp')
                                    : 'Reconnect this network',
                              ),
                            ),
                          );
                        },
                      ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 140),
                child: TextField(
                  controller: preview,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 10000,
                  decoration: InputDecoration(
                    labelText: appTr('Message preview'),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(appTr('Fix spelling with AI before sending')),
                subtitle: Text(
                  appTr('Uses your selected model and plan credits.'),
                ),
                value: fix,
                onChanged: sending
                    ? null
                    : (value) => setState(() => fix = value),
              ),
              if (error != null)
                Text(
                  appTr(error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              FilledButton.icon(
                onPressed:
                    selected.isEmpty || sending || preview.text.trim().isEmpty
                    ? null
                    : send,
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(
                  appTr('Send to :count chats', {'count': selected.length}),
                ),
              ),
            ] else ...[
              Expanded(
                child: ListView(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Icon(
                        Icons.check_circle_outline,
                        size: 56,
                        color: Colors.green,
                      ),
                    ),
                    for (final result in results)
                      ListTile(
                        leading: Icon(
                          result['status'] == 'failed'
                              ? Icons.error_outline
                              : [
                                  'sent',
                                  'delivered',
                                  'read',
                                ].contains(result['status'])
                              ? Icons.done_all
                              : Icons.schedule,
                          color: result['status'] == 'failed'
                              ? Colors.red
                              : Colors.green,
                        ),
                        title: Text(
                          '${chats.where((c) => c['id'] == result['chat_id']).firstOrNull?['title'] ?? result['chat_id']}',
                        ),
                        subtitle: Text(
                          appTr(
                            result['status'] == 'failed'
                                ? '${result['error']}'
                                : [
                                    'sent',
                                    'delivered',
                                    'read',
                                  ].contains(result['status'])
                                ? 'Sent'
                                : 'Queued for delivery',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => InboxScreen(service: widget.service),
                    ),
                  );
                },
                child: Text(appTr('Open in Inbox')),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
