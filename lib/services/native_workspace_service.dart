import 'mobile_api.dart';

class NativeWorkspaceService {
  final MobileApi api;
  final String moduleId;
  const NativeWorkspaceService(this.api, this.moduleId);

  Future<Map<String, dynamic>> load({
    String query = '',
    int page = 1,
    String status = 'all',
    String? currency,
    DateTime? day,
    String? viewType,
    int? agentId,
    String? direction,
    Map<String, dynamic>? extra,
  }) async {
    final data = await api
        .request(
          '/native/workspace',
          method: 'POST',
          body: {
            'module_id': moduleId,
            'query': query.trim(),
            'page': page,
            'status': status,
            'currency': ?currency,
            'view_type': ?viewType,
            'agent_id': ?agentId,
            'direction': ?direction,
            ...?extra,
            if (day != null) ...{
              'from': DateTime(
                day.year,
                day.month,
                day.day,
              ).toUtc().toIso8601String(),
              'until': DateTime(
                day.year,
                day.month,
                day.day + 1,
              ).toUtc().toIso8601String(),
            },
          },
        )
        .timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw const ApiFailure(
            'Your workspace is taking longer to load. Please retry.',
          ),
        );
    if (data is! Map ||
        data['schema_version'] != 1 ||
        data['kind'] is! String) {
      throw const ApiFailure('Unable to load this workspace. Please retry.');
    }
    final normalized = Map<String, dynamic>.from(data);
    final rawData = normalized['data'];
    if (rawData is Map) {
      normalized['data'] = (rawData['data'] as List? ?? []).toList();
      normalized['current_page'] ??= rawData['current_page'];
      normalized['last_page'] ??= rawData['last_page'];
      normalized['total'] ??= rawData['total'];
    } else if (rawData is! List) {
      normalized['data'] = <dynamic>[];
    }
    if (normalized['modules'] is! List) {
      normalized['modules'] = <dynamic>[];
    }
    return normalized;
  }

  Future<void> save({
    required String kind,
    required String requestId,
    required Map<String, dynamic> inputs,
    int? id,
  }) async {
    await api.request(
      '/native/records',
      method: 'POST',
      body: {
        'module_id': moduleId,
        'kind': kind,
        'operation': 'save',
        'request_id': requestId,
        'inputs': inputs,
        'record_id': ?id,
      },
    );
  }

  Future<Map<String, dynamic>> mutate({
    required String kind,
    required String operation,
    required String requestId,
    Map<String, dynamic>? inputs,
    int? recordId,
  }) async {
    final response = await api.request(
      '/native/records',
      method: 'POST',
      body: {
        'module_id': moduleId,
        'kind': kind,
        'operation': operation,
        'request_id': requestId,
        'inputs': ?inputs,
        'record_id': ?recordId,
      },
    );
    return response is Map ? Map<String, dynamic>.from(response) : {};
  }

  Future<void> delete({
    required String kind,
    required int id,
    required String requestId,
  }) =>
      mutate(
        kind: kind,
        operation: 'delete',
        requestId: requestId,
        recordId: id,
      );

  Future<void> publishPost({
    required String requestId,
    required int id,
    String kind = 'blog_post',
  }) =>
      mutate(
        kind: kind,
        operation: 'publish',
        requestId: requestId,
        recordId: id,
      );

  Future<void> duplicatePost({
    required String requestId,
    required int id,
    String kind = 'blog_post',
  }) =>
      mutate(
        kind: kind,
        operation: 'duplicate',
        requestId: requestId,
        recordId: id,
      );

  Future<void> toggleAgent({
    required String requestId,
    required int id,
    String kind = 'blog_agent',
  }) =>
      mutate(
        kind: kind,
        operation: 'toggle_active',
        requestId: requestId,
        recordId: id,
      );
}
