import '../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../services/document_service.dart';
import '../services/mobile_api.dart';
import '../theme/app_colors.dart';
import 'chat_response.dart';
import 'document_actions.dart';

class GeneratedOutputCard extends StatefulWidget {
  final MobileApi api;
  final int? documentId;
  final String title;
  final String content;
  final bool generating;
  final VoidCallback onClear;
  final VoidCallback? onViewHistory;
  final VoidCallback? onSaved;
  final String? documentRevision;
  const GeneratedOutputCard({
    super.key,
    required this.api,
    required this.documentId,
    required this.title,
    required this.content,
    required this.generating,
    required this.onClear,
    this.onViewHistory,
    this.onSaved,
    this.documentRevision,
  });
  @override
  State<GeneratedOutputCard> createState() => _GeneratedOutputCardState();
}

class _GeneratedOutputCardState extends State<GeneratedOutputCard> {
  late String content = widget.content;
  late String title = widget.title;
  late String? revision = widget.documentRevision;
  bool saving = false;
  bool saved = false;
  String? error;
  @override
  void didUpdateWidget(covariant GeneratedOutputCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.documentRevision != widget.documentRevision) {
      revision = widget.documentRevision;
      title = widget.title;
    }
    if (oldWidget.content != widget.content) {
      content = widget.content;
      saved = false;
    }
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final document = await DocumentService(widget.api).save(
        id: widget.documentId!,
        title: title,
        content: content,
        revision: revision,
      );
      if (!mounted) return;
      setState(() {
        saved = true;
        revision = document.revision;
      });
      widget.onSaved?.call();
      documentNotice(
        context,
        document.storedLocally
            ? 'Saved to My documents and this device.'
            : 'Saved to My documents. The local copy could not be stored.',
      );
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final colors = AppColors.of(context);
    final busy = widget.generating || saving;
    return Card(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              appTr('Generated result'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(appTr(title), style: TextStyle(color: colors.muted)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                primary: false,
                child: ChatResponse(
                  text: content,
                  isStreaming: widget.generating,
                  showActions: false,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Divider(color: colors.outline),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy || widget.documentId == null ? null : save,
                  icon: Icon(saved ? Icons.check : Icons.save_outlined),
                  label: Text(appTr(saving ? 'Saving…' : 'Save')),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final edit = await editDocumentText(
                            context,
                            title: title,
                            content: content,
                            draft: true,
                            api: widget.api,
                            documentId: widget.documentId,
                          );
                          if (edit != null && mounted) {
                            setState(() {
                              title = edit.title;
                              content = edit.content;
                              saved = false;
                              error = null;
                            });
                          }
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(appTr('Edit')),
                ),
                Tooltip(
                  message: appTr('Copy response'),
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => copyDocumentText(context, content),
                    icon: const Icon(Icons.copy_outlined),
                    label: Text(appTr('Copy')),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirmDocumentDelete(
                                context,
                                clearOutput: true,
                              ) &&
                              mounted) {
                            widget.onClear();
                          }
                        },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(appTr('Delete')),
                ),
              ],
            ),
            if (widget.onViewHistory != null && !busy) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: widget.onViewHistory,
                icon: const Icon(Icons.history),
                label: Text(appTr('View in History')),
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  appTr(error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
