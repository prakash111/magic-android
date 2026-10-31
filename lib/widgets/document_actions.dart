import '../services/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';
import '../services/mobile_api.dart';
import '../services/document_assistant.dart';
import '../services/social_post_service.dart';
import 'chat_response.dart';

Future<void> copyDocumentText(BuildContext context, String text) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) documentNotice(context, 'Copied to clipboard');
  } catch (_) {
    if (context.mounted) {
      documentNotice(context, 'Unable to copy this response.');
    }
  }
}

Future<void> shareDocumentText(BuildContext context, String text) async {
  try {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  } catch (_) {
    if (context.mounted) {
      documentNotice(context, 'Unable to share this document.');
    }
  }
}

void documentNotice(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(appTr(message))));
}

Future<bool> confirmDocumentDelete(
  BuildContext context, {
  bool clearOutput = false,
}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) {
        AppLocalizations.watch(context);
        return AlertDialog(
          backgroundColor: AppColors.of(context).surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: AppColors.of(context).outline),
          ),
          title: Text(
            appTr(clearOutput ? 'Clear generated output?' : 'Delete document?'),
          ),
          content: Text(
            appTr(
              clearOutput
                  ? 'This clears the result from this screen. Your saved document remains in My documents.'
                  : 'This permanently deletes the document from your account and this device.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(appTr('Cancel')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(
                appTr(clearOutput ? 'Clear output' : 'Delete document'),
              ),
            ),
          ],
        );
      },
    ) ??
    false;

class DocumentEdit {
  final String title;
  final String content;
  const DocumentEdit(this.title, this.content);
}

Future<DocumentEdit?> editDocumentText(
  BuildContext context, {
  required String title,
  required String content,
  bool draft = false,
  MobileApi? api,
  int? documentId,
  String? initialAiAction,
  Future<void> Function(DocumentEdit)? onSave,
}) => showModalBottomSheet<DocumentEdit>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  isDismissible: false,
  enableDrag: false,
  useSafeArea: true,
  backgroundColor: AppColors.of(context).surface,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (localizationContext) {
    AppLocalizations.watch(localizationContext);
    return _DocumentEditor(
      title: appTr(title),
      content: content,
      draft: draft,
      api: api,
      documentId: documentId,
      initialAiAction: initialAiAction,
      onSave: onSave,
    );
  },
);

class _DocumentEditor extends StatefulWidget {
  final String title;
  final String content;
  final bool draft;
  final MobileApi? api;
  final int? documentId;
  final String? initialAiAction;
  final Future<void> Function(DocumentEdit)? onSave;
  const _DocumentEditor({
    required this.title,
    required this.content,
    required this.draft,
    this.api,
    this.documentId,
    this.initialAiAction,
    this.onSave,
  });
  @override
  State<_DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<_DocumentEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.title);
  late final content = TextEditingController(text: widget.content);
  final instruction = TextEditingController();
  final contentFocus = FocusNode();
  TextSelection? selection;
  DocumentAiProposal? proposal;
  String? action, error, requestId;
  String lastText = '';
  bool generating = false, saving = false;
  bool get canAssist => widget.api != null && widget.documentId != null;
  bool get busy => generating || saving;

  @override
  void initState() {
    super.initState();
    lastText = content.text;
    content.addListener(rememberSelection);
    action = widget.initialAiAction;
    if (action == 'correct' && canAssist) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) generate('correct');
      });
    }
  }

  void rememberSelection() {
    if (content.text != lastText) {
      selection = null;
      requestId = null;
    }
    final value = content.selection;
    if (value.isValid && !value.isCollapsed) selection = value;
    if (contentFocus.hasFocus && value.isValid && value.isCollapsed) {
      selection = null;
    }
    lastText = content.text;
  }

  Future<void> generate(String operation) async {
    if (busy || !canAssist) return;
    final captured = DocumentAiSelection(content.text, selection);
    setState(() {
      generating = true;
      error = null;
      action = operation;
    });
    requestId ??= SocialPostService.requestId();
    try {
      final result = await DocumentAssistant(widget.api!).propose(
        documentId: widget.documentId!,
        selection: captured,
        action: operation,
        instruction: instruction.text,
        requestId: requestId,
      );
      if (!mounted) return;
      if (content.text != result.original) {
        throw const ApiFailure(
          'The text changed while AI was working. Please generate a new preview.',
        );
      }
      setState(() => proposal = result);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> save() async {
    if (busy || proposal != null || !form.currentState!.validate()) return;
    final edit = DocumentEdit(title.text.trim(), content.text);
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.onSave?.call(edit);
      if (mounted) Navigator.pop(context, edit);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget aiControls() => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            appTr('Write with AI'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            appTr(
              'Select text to edit a section, or leave it unselected to edit the whole document. AI generation uses your plan credits.',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy || proposal != null
                    ? null
                    : () {
                        if (action != 'correct') requestId = null;
                        generate('correct');
                      },
                icon: const Icon(Icons.spellcheck),
                label: Text(appTr('AI Correct')),
              ),
              OutlinedButton.icon(
                onPressed: busy || proposal != null
                    ? null
                    : () => setState(() {
                        action = 'refine';
                        requestId = null;
                        error = null;
                      }),
                icon: const Icon(Icons.auto_fix_high),
                label: Text(appTr('Make changes / Refine')),
              ),
              OutlinedButton.icon(
                onPressed: busy || proposal != null
                    ? null
                    : () => setState(() {
                        action = 'extend';
                        requestId = null;
                        error = null;
                      }),
                icon: const Icon(Icons.playlist_add),
                label: Text(appTr('Addition / Extend')),
              ),
            ],
          ),
          if (action == 'refine' || action == 'extend') ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('document-ai-instruction'),
              controller: instruction,
              enabled: !busy && proposal == null,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              decoration: InputDecoration(
                labelText: appTr(
                  action == 'refine'
                      ? 'What would you like to change?'
                      : 'What should AI add? (optional)',
                ),
                hintText: appTr(
                  action == 'refine'
                      ? 'Make the tone warmer and simplify the wording'
                      : 'Add a practical example or a concluding paragraph',
                ),
                alignLabelWithHint: true,
              ),
              onChanged: (_) => requestId = null,
            ),
            FilledButton.tonalIcon(
              onPressed: busy || proposal != null
                  ? null
                  : () => generate(action!),
              icon: const Icon(Icons.auto_awesome),
              label: Text(appTr('Generate preview')),
            ),
          ],
          if (generating) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(appTr('Preparing your suggestion…')),
          ],
          if (proposal != null) ...[
            const SizedBox(height: 16),
            Text(
              appTr('Preview changes'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              appTr(
                proposal!.selectionOnly
                    ? proposal!.action == 'extend'
                          ? 'New content will be inserted after your selected passage. Your original is kept until you accept.'
                          : 'Only the selected passage will change. Your original is kept until you accept.'
                    : 'Your original text is kept until you accept.',
              ),
            ),
            ExpansionTile(
              title: Text(appTr('Original text')),
              tilePadding: EdgeInsets.zero,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: ChatResponse(
                      text: proposal!.original,
                      showActions: false,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: ChatResponse(
                  key: const ValueKey('document-ai-preview'),
                  text: proposal!.suggested,
                  showActions: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          final text = proposal!.suggested;
                          content.value = TextEditingValue(
                            text: text,
                            selection: TextSelection.collapsed(
                              offset: text.length,
                            ),
                          );
                          proposal = null;
                          requestId = null;
                          error = null;
                        }),
                  icon: const Icon(Icons.check),
                  label: Text(appTr('Accept changes')),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          proposal = null;
                          requestId = null;
                        }),
                  child: Text(appTr('Discard')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(appTr('Accepted text is saved when you tap Save changes.')),
          ],
        ],
      ),
    ),
  );

  @override
  void dispose() {
    instruction.dispose();
    contentFocus.dispose();
    content.removeListener(rememberSelection);
    title.dispose();
    content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return PopScope(
      canPop: !busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SizedBox(
          height:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.viewInsetsOf(context).bottom) *
              .9,
          child: Form(
            key: form,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          appTr('Edit document'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: appTr('Close editor'),
                        onPressed: busy ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('document-title-input'),
                          controller: title,
                          style: Theme.of(context).textTheme.headlineSmall,
                          enabled: !busy,
                          maxLength: 255,
                          decoration: InputDecoration(
                            labelText: appTr('Document title'),
                          ),
                          validator: (value) =>
                              value == null ||
                                  value.trim().isEmpty ||
                                  [
                                    appTr('null'),
                                    appTr('undefined'),
                                  ].contains(value.trim().toLowerCase())
                              ? appTr('Enter a document title.')
                              : null,
                        ),
                        const SizedBox(height: 16),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              appTr(error!),
                              key: const ValueKey('document-editor-error'),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        TextFormField(
                          key: const ValueKey('document-content-input'),
                          controller: content,
                          focusNode: contentFocus,
                          enabled: !busy && proposal == null,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(height: 1.65),
                          minLines: 8,
                          maxLines: 20,
                          maxLength: 200000,
                          decoration: InputDecoration(
                            labelText: appTr('Content'),
                            alignLabelWithHint: true,
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? appTr('Enter some document content.')
                              : null,
                        ),
                        const SizedBox(height: 20),
                        if (canAssist) aiControls(),
                      ],
                    ),
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: busy || proposal != null ? null : save,
                        icon: Icon(
                          widget.draft ? Icons.check : Icons.save_outlined,
                        ),
                        label: Text(
                          appTr(
                            saving
                                ? 'Saving…'
                                : widget.draft
                                ? 'Apply changes'
                                : 'Save changes',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
