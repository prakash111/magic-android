import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Styled rendering for the flat `components` list returned by `/native/screen`.
///
/// The server sends plain `heading` / `text` / `stat` items. Drawn as-is they
/// look like unformatted text, so this groups them into intro text, section
/// headers, stat/label tiles, status sections and info cards.
/// Anything it does not recognise goes to [fallback] (forms, links, tables...).
List<Widget> buildStyledComponents(
  BuildContext context,
  List<Map> items,
  Widget Function(Map) fallback,
) {
  final out = <Widget>[];
  var i = 0;
  while (i < items.length) {
    final item = items[i];
    final type = item['type'];

    if (type == 'heading') {
      final text = '${item['text']}'.trim();
      if (i == 0 && _isIntro(text)) {
        out.add(SchemaIntro(text: text));
        i++;
        continue;
      }
      var j = i + 1;
      final body = <String>[];
      while (j < items.length && items[j]['type'] == 'text') {
        body.add('${items[j]['text']}'.trim());
        j++;
      }
      final status = statusColorFor(text);
      if (status != null) {
        // Gather consecutive status sections (Pending, Completed, ...) so
        // they can be shown as tabs instead of one long stacked list.
        final groups = <StatusGroup>[
          StatusGroup(title: text, color: status, lines: body),
        ];
        while (j < items.length &&
            items[j]['type'] == 'heading' &&
            statusColorFor('${items[j]['text']}') != null) {
          final nextTitle = '${items[j]['text']}'.trim();
          var k = j + 1;
          final nextBody = <String>[];
          while (k < items.length && items[k]['type'] == 'text') {
            nextBody.add('${items[k]['text']}'.trim());
            k++;
          }
          groups.add(
            StatusGroup(
              title: nextTitle,
              color: statusColorFor(nextTitle)!,
              lines: nextBody,
            ),
          );
          j = k;
        }
        out.add(
          groups.length == 1
              ? SchemaStatusSection(title: text, color: status, lines: body)
              : SchemaStatusTabs(groups: groups),
        );
      } else {
        out.add(SchemaSectionHeader(title: text));
        if (body.isNotEmpty) out.add(SchemaTextBlock(lines: body));
      }
      i = j;
      continue;
    }

    if (type == 'text') {
      final body = <String>[];
      var j = i;
      while (j < items.length && items[j]['type'] == 'text') {
        body.add('${items[j]['text']}'.trim());
        j++;
      }
      out.add(SchemaTextBlock(lines: body));
      i = j;
      continue;
    }

    if (type == 'stat') {
      final stats = <Map>[];
      var j = i;
      while (j < items.length && items[j]['type'] == 'stat') {
        stats.add(items[j]);
        j++;
      }
      out.add(
        _TwoColumn(
          children: [
            for (final s in stats)
              SchemaTile(
                label: '${s['label'] ?? ''}',
                value: s['value'] == null ? null : '${s['value']}',
              ),
          ],
        ),
      );
      i = j;
      continue;
    }

    out.add(fallback(item));
    i++;
  }
  return out;
}

const _statusColors = <String, Color>{
  'pending': AppTheme.warning,
  'scheduled': AppTheme.warning,
  'draft': AppTheme.warning,
  'queued': AppTheme.warning,
  'in progress': AppTheme.warning,
  'completed': AppTheme.success,
  'published': AppTheme.success,
  'active': AppTheme.success,
  'sent': AppTheme.success,
  'done': AppTheme.success,
  'paid': AppTheme.success,
  'cancelled': AppTheme.error,
  'canceled': AppTheme.error,
  'failed': AppTheme.error,
  'archived': AppTheme.error,
  'overdue': AppTheme.error,
  'rejected': AppTheme.error,
};

/// Colour for a status word such as "Pending", or null when [text] is not one.
Color? statusColorFor(String text) => _statusColors[text.trim().toLowerCase()];

bool _isIntro(String text) =>
    text.endsWith('.') || text.split(RegExp(r'\s+')).length >= 6;

final _dateLike = RegExp(
  r'^([A-Z][a-z]{2} \d{1,2}, \d{4}|\d{4}-\d{2}-\d{2}|\d{1,2}/\d{1,2}/\d{2,4})',
);
final _phoneLike = RegExp(r'^\+?[\d\s\-()]{7,}$');

bool _isLabelOnly(String t) =>
    t.isNotEmpty &&
    t.length <= 32 &&
    !t.endsWith('.') &&
    !_dateLike.hasMatch(t) &&
    !t.contains('@');

IconData _rowIcon(String t, int index) {
  if (_dateLike.hasMatch(t)) return Icons.event_outlined;
  if (t.contains('@')) return Icons.mail_outline;
  if (_phoneLike.hasMatch(t)) return Icons.phone_outlined;
  return index == 0 ? Icons.person_outline : Icons.notes_outlined;
}

IconData _tileIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('schedul')) return Icons.schedule_outlined;
  if (l.contains('publish') || l.contains('complete')) {
    return Icons.check_circle_outline;
  }
  if (l.contains('contact') || l.contains('subscriber')) {
    return Icons.people_outline;
  }
  if (l.contains('campaign')) return Icons.campaign_outlined;
  if (l.contains('task')) return Icons.task_alt_outlined;
  return Icons.insights_outlined;
}

Color _muted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);

class SchemaIntro extends StatelessWidget {
  final String text;
  const SchemaIntro({super.key, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyLarge
          ?.copyWith(color: _muted(context), height: 1.4),
    ),
  );
}

class SchemaSectionHeader extends StatelessWidget {
  final String title;
  const SchemaSectionHeader({super.key, required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class SchemaStatusSection extends StatelessWidget {
  final String title;
  final Color color;
  final List<String> lines;
  const SchemaStatusSection({
    super.key,
    required this.title,
    required this.color,
    required this.lines,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: Text(
              'Nothing here yet',
              style: TextStyle(color: _muted(context), fontSize: 13),
            ),
          )
        else
          SchemaInfoCard(lines: lines, accent: color),
      ],
    ),
  );
}

class SchemaTextBlock extends StatelessWidget {
  final List<String> lines;
  const SchemaTextBlock({super.key, required this.lines});
  @override
  Widget build(BuildContext context) {
    if (lines.length >= 2 && lines.every(_isLabelOnly)) {
      return _TwoColumn(
        children: [for (final l in lines) SchemaTile(label: l)],
      );
    }
    if (lines.length == 1 && !_isLabelOnly(lines.first)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SelectableText(
          lines.first,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
        ),
      );
    }
    return SchemaInfoCard(lines: lines);
  }
}

class SchemaInfoCard extends StatelessWidget {
  final List<String> lines;
  final Color? accent;
  const SchemaInfoCard({super.key, required this.lines, this.accent});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var k = 0; k < lines.length; k++)
            Padding(
              padding: EdgeInsets.only(bottom: k == lines.length - 1 ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _rowIcon(lines[k], k),
                    size: 18,
                    color: accent ?? AppTheme.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      lines[k],
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: k == 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class SchemaTile extends StatelessWidget {
  final String label;
  final String? value;
  const SchemaTile({super.key, required this.label, this.value});
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_tileIcon(label), size: 18, color: AppTheme.primary),
          ),
          const SizedBox(height: 12),
          if (value != null) ...[
            Text(
              value!,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
          ],
          Text(
            label,
            style: TextStyle(
              color: value == null ? null : _muted(context),
              fontSize: 13,
              fontWeight: value == null ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    ),
  );
}

class _TwoColumn extends StatelessWidget {
  final List<Widget> children;
  const _TwoColumn({required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final width = (box.maxWidth - 12) / 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Friendly replacement for the plain "workspace is ready" text.
class SchemaEmptyState extends StatelessWidget {
  const SchemaEmptyState({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
    child: Column(
      children: [
        Icon(Icons.inbox_outlined, size: 48, color: _muted(context)),
        const SizedBox(height: 12),
        Text(
          'Nothing here yet',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          'New tools and data will appear here as they become available.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted(context)),
        ),
      ],
    ),
  );
}

class StatusGroup {
  final String title;
  final Color color;
  final List<String> lines;
  const StatusGroup({
    required this.title,
    required this.color,
    required this.lines,
  });
}

/// Segmented tabs for status sections such as Pending / Completed / Cancelled.
class SchemaStatusTabs extends StatefulWidget {
  final List<StatusGroup> groups;
  const SchemaStatusTabs({super.key, required this.groups});
  @override
  State<SchemaStatusTabs> createState() => _SchemaStatusTabsState();
}

class _SchemaStatusTabsState extends State<SchemaStatusTabs> {
  late int _selected = () {
    final first = widget.groups.indexWhere((g) => g.lines.isNotEmpty);
    return first < 0 ? 0 : first;
  }();

  @override
  Widget build(BuildContext context) {
    final groups = widget.groups;
    final index = _selected.clamp(0, groups.length - 1);
    final group = groups[index];
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).cardTheme.color,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppTheme.borderDark),
            ),
            child: Row(
              children: [
                for (var k = 0; k < groups.length; k++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: k == index,
                      label: groups[k].title,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() => _selected = k),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 44),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k == index
                                ? const Color(0xFF2A3046)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  groups[k].title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: k == index
                                        ? Colors.white
                                        : AppTheme.textMuted,
                                  ),
                                ),
                              ),
                              if (groups[k].lines.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: groups[k].color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (group.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  Icon(Icons.inbox_outlined, size: 36, color: _muted(context)),
                  const SizedBox(height: 8),
                  Text(
                    'Nothing here yet',
                    style: TextStyle(color: _muted(context)),
                  ),
                ],
              ),
            )
          else
            SchemaInfoCard(lines: group.lines, accent: group.color),
        ],
      ),
    );
  }
}
