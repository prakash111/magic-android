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
        data['kind'] is! String ||
        data['data'] is! List ||
        data['modules'] is! List) {
      throw const ApiFailure('Unable to load this workspace. Please retry.');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<void> save({
    required String kind,
    required String requestId,
    required Map<String, String> inputs,
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

  Future<void> delete({
    required String kind,
    required String requestId,
    required int id,
  }) async {
    await api.request(
      '/native/records',
      method: 'POST',
      body: {
        'module_id': moduleId,
        'kind': kind,
        'operation': 'delete',
        'request_id': requestId,
        'record_id': id,
      },
    );
  }
}
