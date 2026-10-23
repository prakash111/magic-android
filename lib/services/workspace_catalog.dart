String workspaceCategory(Map module) {
  final category = module['category']?.toString().trim();
  return category == null || category.isEmpty
      ? 'Work & productivity'
      : category;
}

String workspaceTitle(Map module, {bool duplicate = false}) {
  final supplied = module['display_title']?.toString().trim();
  if (supplied != null && supplied.isNotEmpty) return supplied;
  final title = module['title']?.toString().trim() ?? 'Workspace';
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

List<Map<String, dynamic>> namedWorkspaces(List<Map<String, dynamic>> modules) {
  final counts = <String, int>{};
  for (final module in modules) {
    final title = '${module['title']}'.toLowerCase();
    counts[title] = (counts[title] ?? 0) + 1;
  }
  return modules
      .map(
        (module) => <String, dynamic>{
          ...module,
          'category': workspaceCategory(module),
          'display_title': workspaceTitle(
            module,
            duplicate: (counts['${module['title']}'.toLowerCase()] ?? 0) > 1,
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
