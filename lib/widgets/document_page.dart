import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/app_localizations.dart';
import 'document_actions.dart';

Color documentBackground(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xff131620)
    : const Color(0xfffafaff);

class DocumentReader extends StatefulWidget {
  final String text;
  final void Function(TextSelection selection, String? action)? onEdit;
  const DocumentReader({super.key, required this.text, this.onEdit});
  @override
  State<DocumentReader> createState() => DocumentReaderState();
}

class DocumentReaderState extends State<DocumentReader> {
  final Map<int, GlobalKey> anchors = {};
  final Set<int> collapsed = {};

  List<String> get blocks {
    final result = <String>[];
    var start = 0;
    var previousEnd = 0;
    final ends = [
      ...RegExp(r'\n\s*\n')
          .allMatches(widget.text)
          .map((match) => (match.start, match.end)),
      (widget.text.length, widget.text.length),
    ];
    for (final (end, next) in ends) {
      final block = widget.text.substring(start, end);
      if (result.isNotEmpty && isSection(result.last) && !isSection(block)) {
        result[result.length - 1] += widget.text.substring(previousEnd, end);
      } else if (block.isNotEmpty) {
        result.add(block);
      }
      previousEnd = end;
      start = next;
    }
    return result;
  }

  String heading(String block) {
    final bold = RegExp(r'^\*\*(.+?)\*\*').firstMatch(block);
    return bold?.group(1) ??
        block.split('\n').first.replaceAll(RegExp(r'^#{1,6}\s+'), '').trim();
  }

  String sectionBody(String block) {
    final bold = RegExp(r'^\*\*(.+?)\*\*').firstMatch(block);
    if (bold != null) return block.substring(bold.end).trim();
    final newline = block.indexOf('\n');
    return newline < 0 ? '' : block.substring(newline + 1).trim();
  }

  bool isSection(String block) =>
      RegExp(r'^(#{2,6}\s|\*\*.+?\*\*)').hasMatch(block);

  Future<void> paragraphActions(int index) async {
    final block = blocks[index];
    var start = 0;
    for (var i = 0; i <= index; i++) {
      start = widget.text.indexOf(blocks[i], start);
      if (i < index) start += blocks[i].length;
    }
    final selection = TextSelection(
      baseOffset: start,
      extentOffset: start + block.length,
    );
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Wrap(
        children: [
          if (widget.onEdit != null)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(appTr('Edit')),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
          if (widget.onEdit != null)
            ListTile(
              leading: const Icon(Icons.auto_awesome),
              title: Text(appTr('AI')),
              onTap: () => Navigator.pop(context, 'refine'),
            ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(appTr('Copy')),
            onTap: () => Navigator.pop(context, 'copy'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'copy') {
      await copyDocumentText(context, block);
    } else {
      widget.onEdit?.call(selection, action == 'edit' ? null : action);
    }
  }

  Future<void> showSections() async {
    final items = blocks;
    final index = await showModalBottomSheet<int>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              appTr('Jump to section'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          for (var i = 0; i < items.length; i++)
            if (isSection(items[i]))
              ListTile(
                leading: const Icon(Icons.segment),
                title: Text(heading(items[i])),
                onTap: () => Navigator.pop(context, i),
              ),
          if (!items.any(isSection))
            ListTile(
              title: Text(appTr('Content')),
              onTap: () => Navigator.pop(context, 0),
            ),
        ],
      ),
    );
    if (index == null || !mounted) return;
    setState(() => collapsed.remove(index));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = anchors[index]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = blocks;
    final theme = Theme.of(context);
    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(height: 1.7),
      h2: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      h3: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            key: anchors.putIfAbsent(i, GlobalKey.new),
            padding: const EdgeInsets.only(bottom: 14),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => paragraphActions(i),
              child: isSection(items[i]) && !items[i].startsWith('## ')
                  ? Card(
                      margin: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: theme.dividerColor.withValues(alpha: .2),
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: const Color(0xff7c3aed),
                              foregroundColor: Colors.white,
                              child: Text(
                                '${items.take(i + 1).where(isSection).length}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            title: Text(
                              heading(items[i]),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: Icon(
                              collapsed.contains(i)
                                  ? Icons.expand_more
                                  : Icons.expand_less,
                            ),
                            onTap: () => setState(
                              () => collapsed.contains(i)
                                  ? collapsed.remove(i)
                                  : collapsed.add(i),
                            ),
                          ),
                          if (!collapsed.contains(i) &&
                              sectionBody(items[i]).isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: MarkdownBody(
                                data: sectionBody(items[i]),
                                selectable: true,
                                styleSheet: markdownStyle,
                              ),
                            ),
                        ],
                      ),
                    )
                  : MarkdownBody(
                      data: items[i],
                      selectable: true,
                      styleSheet: markdownStyle,
                    ),
            ),
          ),
      ],
    );
  }
}

/// Keeps Markdown as the saved value while styling native editable text.
class DocumentTextController extends TextEditingController {
  DocumentTextController({super.text});
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing &&
        value.composing.isValid &&
        !value.composing.isCollapsed) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <InlineSpan>[];
    final pattern = RegExp(
      r'(^#{1,6} )([^\n]+)|\*\*([^\n]+?)\*\*|(?<!\*)\*([^\n*]+)\*(?!\*)',
      multiLine: true,
    );
    var offset = 0;
    const hidden = TextStyle(fontSize: 0, height: 0, color: Colors.transparent);
    for (final match in pattern.allMatches(text)) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
      if (match.group(1) != null) {
        spans.add(TextSpan(text: match.group(1), style: hidden));
        spans.add(
          TextSpan(
            text: match.group(2),
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
        );
      } else {
        final bold = match.group(3) != null;
        final marker = bold ? '**' : '*';
        spans.add(TextSpan(text: marker, style: hidden));
        spans.add(
          TextSpan(
            text: match.group(bold ? 3 : 4),
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
              fontStyle: bold ? null : FontStyle.italic,
            ),
          ),
        );
        spans.add(TextSpan(text: marker, style: hidden));
      }
      offset = match.end;
    }
    spans.add(TextSpan(text: text.substring(offset)));
    return TextSpan(style: style, children: spans);
  }
}
