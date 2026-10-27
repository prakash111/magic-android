import '../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class AiModelSelector extends StatelessWidget {
  final List<Map> models;
  final String? selected;
  final ValueChanged<String>? onSelected;
  const AiModelSelector({
    super.key,
    required this.models,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final model = models.where((row) => row['id'] == selected).firstOrNull;
    return OutlinedButton(
      key: const ValueKey('ai-model-selector'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 56),
        alignment: Alignment.centerLeft,
      ),
      onPressed: onSelected == null || models.isEmpty
          ? null
          : () async {
              final value = await showModalBottomSheet<String>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (localizationContext) {
                  AppLocalizations.watch(localizationContext);
                  return _ModelSheet(models: models, selected: selected);
                },
              );
              if (value != null) onSelected?.call(value);
            },
      child: Row(
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              appTr(model?['title']?.toString() ?? 'Choose AI model'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.expand_more),
        ],
      ),
    );
  }
}

class _ModelSheet extends StatefulWidget {
  final List<Map> models;
  final String? selected;
  const _ModelSheet({required this.models, this.selected});
  @override
  State<_ModelSheet> createState() => _ModelSheetState();
}

class _ModelSheetState extends State<_ModelSheet> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final colors = AppColors.of(context);
    final groups = <String, List<Map>>{};
    for (final model in widget.models) {
      final search =
          '${model['id']} ${model['title']} ${model['provider']} ${model['engine']} ${model['capabilities']}'
              .toLowerCase();
      if (!search.contains(query.trim().toLowerCase())) continue;
      final group =
          model['is_system_default'] == true || model['is_default'] == true
          ? 'System defaults'
          : '${model['provider'] ?? model['engine'] ?? 'Other models'}';
      groups.putIfAbsent(group, () => []).add(model);
    }
    final names = [
      if (groups.containsKey('System defaults')) 'System defaults',
      ...groups.keys.where((name) => name != 'System defaults'),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height:
            (MediaQuery.sizeOf(context).height -
                MediaQuery.viewInsetsOf(context).bottom) *
            .85,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          children: [
            Text(
              appTr('Choose AI model'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: appTr('Search AI models...'),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 12),
            if (groups.isEmpty)
              Padding(
                padding: EdgeInsets.all(24),
                child: Text(appTr('No matching models')),
              )
            else ...[
              for (final group in names) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    appTr(group),
                    style: TextStyle(
                      color: colors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                for (final model in groups[group]!)
                  Card(
                    color: colors.surface,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Text(
                        '${model['title'] ?? model['id']}',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        [
                          if (model['is_system_default'] == true)
                            'System default',
                          if (model['is_default'] == true &&
                              model['is_system_default'] != true)
                            'Plan default',
                          '${model['provider'] ?? model['engine'] ?? ''}',
                          if (model['capabilities'] is List)
                            (model['capabilities'] as List).join(' • '),
                        ].where((text) => text.isNotEmpty).join(' · '),
                      ),
                      trailing: model['id'] == widget.selected
                          ? Icon(Icons.check_circle, color: colors.primary)
                          : const Icon(Icons.circle_outlined),
                      onTap: () =>
                          Navigator.pop(context, model['id'] as String),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
