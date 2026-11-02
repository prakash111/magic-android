import 'package:flutter/material.dart';

import '../services/app_localizations.dart';

class AiReviewCard extends StatelessWidget {
  final String original, corrected;
  final VoidCallback onCorrected, onOriginal, onEdit;
  const AiReviewCard({
    super.key,
    required this.original,
    required this.corrected,
    required this.onCorrected,
    required this.onOriginal,
    required this.onEdit,
  });
  static List<TextSpan> diffSpans(
    String before,
    String after, {
    required bool original,
  }) {
    final a = RegExp(r'\S+|\s+')
        .allMatches(before)
        .map((m) => m.group(0)!)
        .toList();
    final b = RegExp(r'\S+|\s+')
        .allMatches(after)
        .map((m) => m.group(0)!)
        .toList();
    const removed = TextStyle(
      decoration: TextDecoration.lineThrough,
      color: Color(0xfffb7185),
    );
    const added = TextStyle(
      backgroundColor: Color(0x4434d399),
      color: Color(0xff34d399),
    );
    if (a.length > 500 || b.length > 500) {
      return [
        TextSpan(
          text: original ? before : after,
          style: original ? removed : added,
        ),
      ];
    }
    final table = List.generate(
      a.length + 1,
      (_) => List.filled(b.length + 1, 0),
    );
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        table[i][j] = a[i] == b[j]
            ? 1 + table[i + 1][j + 1]
            : (table[i + 1][j] > table[i][j + 1]
                  ? table[i + 1][j]
                  : table[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    final spans = <TextSpan>[];
    while (i < a.length || j < b.length) {
      if (i < a.length && j < b.length && a[i] == b[j]) {
        spans.add(TextSpan(text: a[i]));
        i++;
        j++;
      } else if (j < b.length &&
          (i == a.length || table[i][j + 1] >= table[i + 1][j])) {
        if (!original) spans.add(TextSpan(text: b[j], style: added));
        j++;
      } else {
        if (original) spans.add(TextSpan(text: a[i], style: removed));
        i++;
      }
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.all(10),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  appTr('Review AI corrections'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            appTr('You wrote'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Text.rich(
            TextSpan(children: diffSpans(original, corrected, original: true)),
          ),
          const SizedBox(height: 6),
          Text(
            appTr('Corrected'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
          Text.rich(
            TextSpan(children: diffSpans(original, corrected, original: false)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TextButton(
                onPressed: onOriginal,
                child: Text(appTr('Send as typed')),
              ),
              TextButton(onPressed: onEdit, child: Text(appTr('Edit'))),
              FilledButton(
                onPressed: onCorrected,
                child: Text(appTr('Send corrected')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
