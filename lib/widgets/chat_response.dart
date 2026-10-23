import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../theme/app_colors.dart';
import '../services/mobile_api.dart';
import 'document_actions.dart';

class ChatResponse extends StatelessWidget {
  final String text;
  final bool isStreaming;
  final bool showActions;
  const ChatResponse({
    super.key,
    required this.text,
    this.isStreaming = false,
    this.showActions = true,
  });

  @override
  Widget build(BuildContext context) {
    final references = text.split('\n\nSources:\n');
    final sources = RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)\)')
        .allMatches(references.length > 1 ? references.last : '')
        .where((match) => Uri.tryParse(match[2]!)?.userInfo.isEmpty == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarkdownBody(
          data: references.first,
          selectable: true,
          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
            p: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 15,
              height: 1.5,
            ),
            h1: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 24,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
            h2: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 21,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
            h3: TextStyle(
              color: AppColors.of(context).text,
              fontSize: 18,
              height: 1.45,
              fontWeight: FontWeight.w700,
            ),
            listBullet: TextStyle(
              color: AppColors.of(context).text,
              height: 1.5,
            ),
            blockSpacing: 14,
            pPadding: const EdgeInsets.only(bottom: 8),
            h1Padding: const EdgeInsets.only(top: 12, bottom: 8),
            h2Padding: const EdgeInsets.only(top: 10, bottom: 8),
            h3Padding: const EdgeInsets.symmetric(vertical: 8),
            codeblockDecoration: BoxDecoration(
              color: AppColors.of(context).input,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          imageBuilder: (_, title, alt) => Text(alt ?? title ?? 'Image'),
          onTapLink: (_, href, _) async {
            final url = Uri.tryParse(href ?? '');
            if (url == null ||
                url.scheme != 'https' ||
                url.userInfo.isNotEmpty) {
              return;
            }
            try {
              await SecureStore.invokeMethod<void>('openUrl', {
                'url': url.toString(),
              });
            } catch (_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to open this link.')),
                );
              }
            }
          },
        ),
        if (showActions && text.trim().isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Copy response',
                onPressed: isStreaming
                    ? null
                    : () => copyDocumentText(context, text),
                icon: const Icon(Icons.copy_outlined),
              ),
              IconButton(
                tooltip: 'Share response',
                onPressed: isStreaming
                    ? null
                    : () => shareDocumentText(context, text),
                icon: const Icon(Icons.share_outlined),
              ),
            ],
          ),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Sources'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final source in sources)
                ActionChip(
                  avatar: const Icon(Icons.open_in_new, size: 16),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(source[1]!, overflow: TextOverflow.ellipsis),
                  ),
                  onPressed: () async {
                    try {
                      await SecureStore.invokeMethod<void>('openUrl', {
                        'url': source[2],
                      });
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Unable to open this source.'),
                          ),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}
