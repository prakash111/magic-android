import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../services/mobile_api.dart';
import '../theme/design.dart';
import '../screens/inbox/widgets.dart';
import 'avatar_with_badge.dart';

class MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final String network;
  final bool group, showAvatar;
  final void Function(String action)? onAction;
  const MessageBubble({
    super.key,
    required this.message,
    required this.network,
    this.group = false,
    this.showAvatar = true,
    this.onAction,
  });
  Future<void> openAttachment(BuildContext context, Map file) async {
    final uri = Uri.tryParse('${file['url'] ?? ''}');
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return;
    try {
      await SecureStore.invokeMethod<void>(
        file['kind'] == 'video' ? 'previewMedia' : 'openUrl',
        {'url': uri.toString()},
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appTr('Unable to open this attachment. Please retry.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final outgoing = message['direction'] == 'out';
    final sender = '${message['sender_name'] ?? ''}';
    final status = '${message['status'] ?? ''}';
    final color = outgoing
        ? (network == 'wa' ? const Color(0xff059669) : const Color(0xff7041ef))
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final quote = message['reply_quote'] as Map?;
    final fixed = message['ai_fixed_json'] as Map?;
    final card = Material(
      color: color,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onLongPress: onAction == null
            ? null
            : () async {
                final action = await showModalBottomSheet<String>(
                  context: context,
                  useSafeArea: true,
                  showDragHandle: true,
                  builder: (context) => Wrap(
                    children: [
                      for (final item in [
                        ('reply', Icons.reply, 'Reply'),
                        ('ai', Icons.auto_awesome, 'Reply with AI'),
                        ('copy', Icons.copy_outlined, 'Copy'),
                      ])
                        ListTile(
                          leading: Icon(item.$2),
                          title: Text(appTr(item.$3)),
                          onTap: () => Navigator.pop(context, item.$1),
                        ),
                    ],
                  ),
                );
                if (action != null) onAction!(action);
              },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message['upload_progress'] is num)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(
                    value: (message['upload_progress'] as num).toDouble(),
                    semanticsLabel: appTr('Uploading attachment'),
                  ),
                ),
              if (group && !outgoing && sender.isNotEmpty)
                Text(
                  sender,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: accentFor(
                      '${message['sender_remote_id'] ?? sender}',
                    ),
                  ),
                ),
              if (quote != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: .12),
                    border: const BorderDirectional(
                      start: BorderSide(color: Color(0xffa78bfa), width: 3),
                    ),
                  ),
                  child: Text(
                    '${quote['sender_name'] ?? ''}\n${quote['body'] ?? ''}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (fixed != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text(appTr('Original message')),
                      content: Text('${fixed['original'] ?? ''}'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(appTr('Close')),
                        ),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: Text(
                    appTr('AI fixed :count words', {
                      'count':
                          fixed['word_count'] ??
                          (fixed['changes'] as List? ?? []).length,
                    }),
                  ),
                ),
              for (final file
                  in (message['attachments'] as List? ?? []).whereType<Map>())
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => openAttachment(context, file),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: file['kind'] == 'photo' && file['url'] != null
                          ? Image.network(
                              '${file['url']}',
                              height: 160,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Row(
                                children: [
                                  const Icon(Icons.downloading),
                                  Expanded(child: Text('${file['name']}')),
                                ],
                              ),
                            )
                          : Row(
                              children: [
                                Icon(
                                  file['kind'] == 'video'
                                      ? Icons.play_circle_outline
                                      : Icons.description_outlined,
                                  color: outgoing ? Colors.white : null,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${file['name']}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${((file['size'] as num? ?? 0) / 1024).toStringAsFixed(0)} KB',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              if ('${message['body'] ?? ''}'.isNotEmpty)
                Text(
                  '${message['body']}',
                  style: TextStyle(
                    color: outgoing ? Colors.white : null,
                    height: 1.4,
                  ),
                ),
              if (message['sent_via'] == 'chatbot')
                Text(
                  appTr('via MagicAI Chatbot'),
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    inboxTime(message['created_at']),
                    style: TextStyle(
                      fontSize: 11,
                      color: outgoing
                          ? Colors.white70
                          : Theme.of(context).hintColor,
                    ),
                  ),
                  if (outgoing) ...[
                    const SizedBox(width: 4),
                    Icon(
                      status == 'read' || status == 'delivered'
                          ? Icons.done_all
                          : status == 'sent'
                          ? Icons.done
                          : status == 'failed'
                          ? Icons.error_outline
                          : Icons.schedule,
                      size: 15,
                      color: status == 'read'
                          ? const Color(0xff67e8f9)
                          : outgoing
                          ? Colors.white70
                          : null,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: outgoing
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!outgoing && group)
            SizedBox(
              width: 34,
              child: showAvatar
                  ? AvatarWithBadge(
                      name: sender,
                      network: network,
                      url: message['sender_photo_url'] as String?,
                      radius: 14,
                    )
                  : null,
            ),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * .82,
              ),
              child: card,
            ),
          ),
        ],
      ),
    );
  }
}
