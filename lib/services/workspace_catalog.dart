String workspaceCategory(Map module) {
  final category = module['category']?.toString().trim();
  return category == null || category.isEmpty
      ? 'Work & productivity'
      : category;
}

String toolDisplayName(Map module, {bool duplicate = false}) {
  final supplied = module['display_title']?.toString().trim();
  if (supplied != null && supplied.isNotEmpty) return supplied;
  final title = (module['title'] ?? module['name'])?.toString().trim();
  if (title == null || title.isEmpty) {
    return module['label']?.toString().trim() ?? 'Workspace';
  }
  if (title.toLowerCase() != 'dashboard' && !duplicate) return title;
  final category = workspaceCategory(module);
  final prefix = switch (category) {
    'Work & productivity' => 'Productivity',
    'Social & marketing' => 'Social Media',
    _ => category,
  };
  return title.toLowerCase().startsWith('${prefix.toLowerCase()} ')
      ? title
      : '$prefix $title';
}

/// Filter out redundant root/parent CRM entry that fails to load and causes Retry.
bool isSupportedWorkspace(Map module) {
  final id = '${module['id']}'.toLowerCase();
  final title = '${module['title'] ?? module['name'] ?? ''}'.trim().toLowerCase();
  final displayTitle = '${module['display_title'] ?? ''}'.trim().toLowerCase();
  final category = workspaceCategory(module).toLowerCase();

  if (id == 'web:ext_crm_dropdown' || id == 'ext_crm_dropdown') {
    return false;
  }
  if (category == 'crm' && (title == 'crm' || displayTitle == 'crm')) {
    return false;
  }
  return true;
}

List<Map<String, dynamic>> namedWorkspaces(List<Map<String, dynamic>> modules) {
  final validModules = modules.where(isSupportedWorkspace).toList();
  final counts = <String, int>{};
  for (final module in validModules) {
    final title = toolDisplayName(module).toLowerCase();
    counts[title] = (counts[title] ?? 0) + 1;
  }
  return validModules
      .map(
        (module) => <String, dynamic>{
          ...module,
          'category': workspaceCategory(module),
          'display_title': toolDisplayName(
            module,
            duplicate: (counts[toolDisplayName(module).toLowerCase()] ?? 0) > 1,
          ),
        },
      )
      .toList();
}

Map<String, List<Map<String, dynamic>>> groupedWorkspaces(
  List<Map<String, dynamic>> modules, {
  String category = 'All',
  String query = '',
}) {
  final groups = <String, List<Map<String, dynamic>>>{};
  final search = query.toLowerCase().trim();
  for (final module in namedWorkspaces(modules)) {
    final section = workspaceCategory(module);
    if (category != 'All' && section != category) continue;
    if (!'${module['title']} ${module['display_title']} ${module['description']} $section'
        .toLowerCase()
        .contains(search)) {
      continue;
    }
    groups.putIfAbsent(section, () => []).add(module);
  }
  return groups;
}

/// Resolve legacy names only when they identify exactly one tool. IDs always win.
List<String> migrateToolFavorites(
  List<String> saved,
  List<Map<String, dynamic>> modules,
) {
  final tools = namedWorkspaces(modules);
  final ids = {for (final tool in tools) '${tool['id']}'};
  final aliases = <String, Set<String>>{};
  for (final tool in tools) {
    for (final name in [toolDisplayName(tool), tool['title'], tool['name']]) {
      if (name == null || '$name'.trim().isEmpty) continue;
      aliases
          .putIfAbsent('$name'.trim(), () => <String>{})
          .add('${tool['id']}');
    }
  }
  final result = <String>[];
  for (final value in saved) {
    final matches = aliases[value.trim()];
    final id = ids.contains(value) || matches == null || matches.length != 1
        ? value
        : matches.single;
    if (!result.contains(id)) result.add(id);
  }
  return result;
}
