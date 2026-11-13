class VideoModelOption {
  final String id;
  final String label;
  const VideoModelOption(this.id, this.label);
}

class VideoToolConfiguration {
  final List<VideoModelOption> models;
  final String selectedModel;

  const VideoToolConfiguration._(this.models, this.selectedModel);

  factory VideoToolConfiguration.fromResponse(
    dynamic response, {
    required String tool,
    String previousModel = 'standard',
  }) {
    if (response is! Map || response['engines'] is! List) {
      throw const FormatException('Invalid video settings');
    }
    Map? engine;
    for (final candidate in response['engines'] as List) {
      if (candidate is Map &&
          candidate['id'] is String &&
          (candidate['id'] as String).trim().toLowerCase() == tool) {
        engine = candidate;
        break;
      }
    }
    if (engine == null && tool == 'ai_video_pro') {
      throw const FormatException('Missing video engine');
    }
    final models = videoModelOptions(engine?['models']);
    if (models.isEmpty && tool == 'ai_video_pro') {
      throw const FormatException(
        'No video models are currently available. Enable a model in your web settings and retry.',
      );
    }
    final preferred = engine?['default_model'];
    final preferredId = preferred is String ? preferred.trim() : null;
    final selected = models.any((model) => model.id == preferredId)
        ? preferredId!
        : models.any((model) => model.id == previousModel)
        ? previousModel
        : models.isNotEmpty
        ? models.first.id
        : 'standard';
    return VideoToolConfiguration._(List.unmodifiable(models), selected);
  }
}

List<VideoModelOption> videoModelOptions(dynamic configuration) {
  final options = <String, VideoModelOption>{};
  void add(String id, dynamic label) {
    id = id.trim();
    if (id.isEmpty) return;
    options.putIfAbsent(
      id,
      () => VideoModelOption(
        id,
        label is String && label.trim().isNotEmpty
            ? label.trim()
            : id.split('/').last,
      ),
    );
  }

  void visit(dynamic value, [String? key, int depth = 0]) {
    if (depth > 32) {
      throw const FormatException('Video settings are nested too deeply');
    }
    if (value is String) {
      add(key ?? value, value);
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item, null, depth + 1);
      }
      return;
    }
    if (value is! Map) return;
    for (final flag in ['isActive', 'active', 'enabled']) {
      final enabled = value[flag];
      if ([false, 0].contains(enabled) ||
          (enabled is String &&
              ['0', 'false'].contains(enabled.trim().toLowerCase()))) {
        return;
      }
    }
    final status = value['status'];
    if (status is String &&
        ['disabled', 'inactive'].contains(status.trim().toLowerCase())) {
      return;
    }
    if (value.containsKey('subModels') || value.containsKey('features')) {
      visit(value['subModels'], null, depth + 1);
      visit(value['features'], null, depth + 1);
      return;
    }
    final id = value['id'] ?? value['value'];
    if (id is String) {
      add(id, value['label'] ?? value['name']);
    } else if (key != null &&
        (value['label'] is String || value['name'] is String)) {
      add(key, value['label'] ?? value['name']);
    } else {
      for (final entry in value.entries) {
        if (entry.key is String &&
            ![
              'label',
              'name',
              'description',
              'inputs',
              'status',
              'isActive',
              'active',
              'enabled',
            ].contains(entry.key)) {
          visit(entry.value, entry.key as String, depth + 1);
        }
      }
    }
  }

  visit(configuration);
  return options.values.toList();
}
