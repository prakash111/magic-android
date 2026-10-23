import 'package:shared_preferences/shared_preferences.dart';

import 'mobile_api.dart';

class AiModelSelection {
  final MobileApi api;
  AiModelSelection(this.api);
  static final _scopes = Expando<String>();
  static final _defaults = Expando<String>();
  static const preferenceKey = 'selected_ai_model_id';
  String get _scope => _scopes[api] ?? api.origin.origin;

  static void configure(MobileApi api, Map config) {
    _scopes[api] = '${api.origin.origin}:${config['user']?['id'] ?? 'default'}';
    final id = config['ai']?['default_model_id'];
    if (id is String && id.isNotEmpty) _defaults[api] = id;
  }

  Future<List<Map<String, dynamic>>> models() async {
    final result = await api.request('/models');
    final rows = result is Map ? result['data'] : result;
    if (rows is! List) {
      throw const ApiFailure('Unable to load AI models. Please retry.');
    }
    return rows
        .whereType<Map>()
        .where(
          (row) =>
              row['id'] is String &&
              (row['id'] as String).trim().isNotEmpty &&
              row['active'] != false &&
              row['status'] != 'disabled',
        )
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<String?> resolve(List<Map> models) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_ai_model_scope') == _scope
        ? prefs.getString(preferenceKey)
        : null;
    bool available(String? value) =>
        value != null && models.any((row) => row['id'] == value);
    if (available(saved)) return saved;
    final preferred =
        models.where((row) => row['is_default'] == true).firstOrNull ??
        models.where((row) => row['is_system_default'] == true).firstOrNull;
    if (preferred != null) return preferred['id'] as String;
    if (available(_defaults[api])) return _defaults[api];
    return models.firstOrNull?['id'] as String?;
  }

  Future<void> select(String id, List<Map> models) async {
    if (!models.any((model) => model['id'] == id)) {
      throw const ApiFailure('Choose an available AI model.');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_ai_model_scope', _scope);
    await prefs.setString(preferenceKey, id);
  }
}
