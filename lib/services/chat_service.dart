import 'mobile_api.dart';

class ChatService {
  final MobileApi api;
  final String? context;
  ChatService(this.api, {this.context});

  String path(String resource) =>
      '/chat/$resource${context == null ? '' : '?context=$context'}';

  static List<Map<String, dynamic>> records(dynamic data) {
    final rows = data is Map ? data['data'] : data;
    if (rows is! List) {
      throw const ApiFailure('Unable to read chat data. Please retry.');
    }
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<Map<String, List<Map<String, dynamic>>>> options() async {
    final data = await api
        .request(path('options'))
        .timeout(
          const Duration(seconds: 25),
          onTimeout: () => throw const ApiFailure(
            'Chat settings are taking too long to load. Please retry.',
          ),
        );
    if (data is! Map) {
      throw const ApiFailure('Unable to load chat settings. Please retry.');
    }
    return {
      'personas': records(data['personas']),
      'models': records(data['models']),
    };
  }

  Future<List<Map<String, dynamic>>> conversations({String? type}) async {
    String p = path('conversations');
    if (type != null && type.isNotEmpty) {
      p += p.contains('?') ? '&type=$type' : '?type=$type';
    }
    return records(
      await api
          .request(p)
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw const ApiFailure(
              'Conversation history is taking too long to load. Please retry.',
            ),
          ),
    );
  }

  Future<bool> deleteConversation(String id) async {
    final response = await api.request(
      '/chat/conversations/$id',
      method: 'DELETE',
    );
    if (response is Map && response['success'] == true) {
      return true;
    }
    return true;
  }

  Future<bool> clearAllConversations({String? type}) async {
    String p = '/chat/conversations/clear-all';
    final query = <String>[];
    if (context != null) query.add('context=$context');
    if (type != null && type.isNotEmpty) query.add('type=$type');
    if (query.isNotEmpty) {
      p += '?${query.join('&')}';
    }
    final response = await api.request(p, method: 'DELETE');
    if (response is Map && response['success'] == true) {
      return true;
    }
    return true;
  }
}
