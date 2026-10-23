import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/app_colors.dart';

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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmDocumentDelete(
  BuildContext context, {
  bool clearOutput = false,
}) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.of(context).surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.of(context).outline),
        ),
        title: Text(
          clearOutput ? 'Clear generated output?' : 'Delete document?',
        ),
        content: Text(
          clearOutput
              ? 'This clears the result from this screen. Your saved document remains in My documents.'
              : 'This permanently deletes the document from your account and this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(clearOutput ? 'Clear output' : 'Delete document'),
          ),
        ],
      ),
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
}) => showModalBottomSheet<DocumentEdit>(
  context: context,
  useRootNavigator: true,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: AppColors.of(context).surface,
  constraints: const BoxConstraints(maxWidth: 720),
  builder: (_) => _DocumentEditor(title: title, content: content, draft: draft),
);

class _DocumentEditor extends StatefulWidget {
  final String title;
  final String content;
  final bool draft;
  const _DocumentEditor({
    required this.title,
    required this.content,
    required this.draft,
  });
  @override
  State<_DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends State<_DocumentEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(text: widget.title);
  late final content = TextEditingController(text: widget.content);
  @override
  void dispose() {
    title.dispose();
    content.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SizedBox(
      height:
          (MediaQuery.sizeOf(context).height -
              MediaQuery.viewInsetsOf(context).bottom) *
          .9,
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Edit document',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close editor',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('document-title-input'),
              controller: title,
              maxLength: 255,
              decoration: const InputDecoration(labelText: 'Document title'),
              validator: (value) =>
                  value == null ||
                      value.trim().isEmpty ||
                      ['null', 'undefined'].contains(value.trim().toLowerCase())
                  ? 'Enter a document title.'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('document-content-input'),
              controller: content,
              minLines: 8,
              maxLines: 20,
              maxLength: 200000,
              decoration: const InputDecoration(
                labelText: 'Content',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter some document content.'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () {
                if (form.currentState!.validate()) {
                  Navigator.pop(
                    context,
                    DocumentEdit(title.text.trim(), content.text),
                  );
                }
              },
              icon: Icon(widget.draft ? Icons.check : Icons.save_outlined),
              label: Text(widget.draft ? 'Apply changes' : 'Save changes'),
            ),
          ],
        ),
      ),
    ),
  );
}
