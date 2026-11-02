import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mobile_api.dart';
import 'inbox_state.dart';
export 'inbox_state.dart';
import 'inbox_files_io.dart'
    if (dart.library.js_interop) 'inbox_files_web.dart';
import 'extension_workflow_service.dart';
import 'social_post_service.dart';

class InboxService {
  final MobileApi api;
  InboxService(this.api);
  final state = InboxState();
  String? _stateScope;
  Future<void> _stateSave = Future.value();
  Future<void>? _countsFetch;
  static final Expando<InboxService> _instances = Expando();
  static InboxService forApi(MobileApi api) =>
      _instances[api] ??= InboxService(api);
  Future<String> scope() async {
    final token = await api.store.read('access_token') ?? '';
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
      );
      return 'inbox:${payload['sub']}';
    } catch (_) {
      var value = 0;
      for (final unit in token.codeUnits) {
        value = (value * 31 + unit) & 0x7fffffff;
      }
      return 'inbox:$value';
    }
  }

  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool ai = false,
  }) async {
    final result = await api
        .request(path, method: method, body: body)
        .timeout(
          Duration(seconds: ai ? 4 : 9),
          onTimeout: () => throw const ApiFailure(
            'The request took too long. Please retry.',
          ),
        );
    if (result is! Map) throw const ApiFailure('Invalid inbox response.');
    return Map<String, dynamic>.from(result);
  }

  Future<void> cache(String name, Object value) async {
    await api.store.write('${await scope()}:$name', jsonEncode(value));
  }

  Future<dynamic> cached(String name) async {
    try {
      final value = await api.store.read('${await scope()}:$name');
      return value == null ? null : jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> chats({
    String network = '',
    String query = '',
    String? cursor,
    bool needsReply = false,
  }) async {
    final params = {
      'network': network,
      'q': query,
      'cursor': ?cursor,
      if (needsReply) 'needs_reply': '1',
    };
    final result = await call(
      '/inbox/chats?${Uri(queryParameters: params).query}',
    );

    if (cursor == null && network.isEmpty && query.isEmpty && !needsReply) {
      await cache('chats', result);
    }
    return result;
  }

  Future<void> restoreState() async {
    final account = await scope();
    if (_stateScope == account) return;
    final previous = _stateScope;
    _stateScope = account;
    if (previous != null) state.reset();
    final saved = await cached('inbox_state');
    if (_stateScope == account && saved is Map) {
      try {
        state.restore(saved);
      } catch (_) {}
    }
  }

  Future<void> persistState() {
    final saved = state.snapshot();
    final account = _stateScope;
    if (account == null) return Future.value();
    _stateSave = _stateSave
        .catchError((_) {})
        .then(
          (_) => api.store.write('$account:inbox_state', jsonEncode(saved)),
        );
    return _stateSave;
  }

  Future<bool> loadChats({
    String network = '',
    String query = '',
    String? cursor,
    bool needsReply = false,
    bool append = false,
  }) async {
    await restoreState();
    final fetch = state.beginFetch();
    try {
      final result = await chats(
        network: network,
        query: query,
        cursor: cursor,
        needsReply: needsReply,
      );
      final applied = state.applyPage(result, fetch, append: append);
      if (applied) unawaited(persistState().catchError((_) {}));
      return applied;
    } catch (error) {
      state.failed(error, fetch: fetch);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> counts() => call('/inbox/counts');

  Future<void> refreshCounts({bool force = false}) async {
    final previous = _countsFetch;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
      if (!force) return;
    }
    final current = _refreshCounts();
    _countsFetch = current;
    try {
      await current;
    } finally {
      if (identical(_countsFetch, current)) _countsFetch = null;
    }
  }

  Future<void> _refreshCounts() async {
    await restoreState();
    final fetch = state.beginFetch();
    try {
      state.applyCounts(await counts(), fetch);
      unawaited(persistState().catchError((_) {}));
    } catch (error) {
      state.failed(error, fetch: fetch);
      rethrow;
    }
  }

  Future<void> markRead(int chat) async {
    state.markRead(chat);
    unawaited(persistState().catchError((_) {}));
    try {
      await read(chat);
      await refreshCounts(force: true);
    } catch (error) {
      state.failed(error);
      rethrow;
    }
  }

  Future<void> mute(int chat, bool value) async {
    final previous = state.chatById(chat)?['muted'];
    state.optimisticPatch(chat, {'muted': value});
    unawaited(persistState().catchError((_) {}));
    try {
      await pin(chat, muted: value);
    } catch (error) {
      state.optimisticPatch(chat, {'muted': previous});
      state.failed(error);
      rethrow;
    }
    await refreshCounts(force: true);
  }

  void resetSession() {
    _stateScope = null;
    state.reset();
  }

  Future<void> onPush(Map<String, dynamic> data) async {
    final chat = int.tryParse('${data['chat_id']}');
    if (chat != null && data['message_id'] != null) {
      state.incoming(chat, messageId: data['message_id']!);
    }
    state.requestRefresh();
    if (!state.inboxVisible) await refreshCounts(force: true);
  }

  Future<Map<String, dynamic>> messages(int chat, {String? cursor}) async {
    final fetch = state.beginFetch();
    final result = await call(
      '/inbox/chats/$chat/messages${cursor == null ? '' : '?cursor=${Uri.encodeQueryComponent(cursor)}'}',
    );
    if (cursor == null) {
      state.applyThread(result, fetch);
      await cache('thread:$chat', result);
    }
    return result;
  }

  Future<void> read(int chat) async {
    final fetch = state.beginFetch();
    final result = await call('/inbox/chats/$chat/read', method: 'POST');
    state.applyThread({'chat': result['data'], 'meta': result['meta']}, fetch);
  }

  Future<void> pin(int chat, {bool? pinned, bool? muted}) async {
    final fetch = state.beginFetch();
    final result = await call(
      '/inbox/chats/$chat',
      method: 'PATCH',
      body: {'pinned': ?pinned, 'muted': ?muted},
    );
    state.applyThread({'chat': result['data'], 'meta': result['meta']}, fetch);
  }

  Future<Map<String, dynamic>> prefs({Map<String, dynamic>? values}) async {
    final result = await call(
      '/me/prefs',
      method: values == null ? 'GET' : 'PUT',
      body: values,
    );
    final data = Map<String, dynamic>.from(result['data'] as Map? ?? {});
    await cache('prefs', data);
    return data;
  }

  Future<List<String>> favorites({List<String>? ids}) async {
    final result = await call(
      '/me/favorites',
      method: ids == null ? 'GET' : 'PUT',
      body: ids == null ? null : {'tool_ids': ids},
    );
    final list = (result['tool_ids'] as List? ?? []).map((e) => '$e').toList();
    await cache('favorites', list);
    return list;
  }

  Future<Map<String, dynamic>> fix(
    String text, {
    String lang = 'en',
    String? model,
  }) => call(
    '/inbox/ai/fix',
    method: 'POST',
    ai: true,
    body: {'text': text, 'lang': lang, 'model': ?model},
  );
  Future<String> compose(
    int chat,
    String tone,
    String text, {
    int? replyTo,
    String lang = 'en',
    String? model,
  }) async {
    final result = await call(
      '/inbox/ai/compose',
      method: 'POST',
      ai: true,
      body: {
        'chat_id': chat,
        'tone': tone,
        'reply_to': ?replyTo,
        'text': text,
        'lang': lang,
        'model': ?model,
      },
    );
    return '${result['text'] ?? ''}';
  }

  Future<List<String>> replies(int chat, {String? model}) async {
    final data = await call(
      '/inbox/ai/replies',
      method: 'POST',
      ai: true,
      body: {'chat_id': chat, 'model': ?model},
    );
    return (data['suggestions'] as List? ?? []).whereType<String>().toList();
  }

  Future<Map<String, dynamic>> send(
    int chat,
    String text, {
    List<int> attachments = const [],
    int? replyTo,
    String? clientId,
    String mode = 'off',
    String? model,
    String lang = 'en',
  }) => call(
    '/inbox/chats/$chat/messages',
    method: 'POST',
    body: {
      'body': text,
      'ai_fix': mode,
      'lang': lang,
      'client_id': clientId ?? SocialPostService.requestId(),
      'attachment_ids': attachments,
      'reply_to': ?replyTo,
      'model': ?model,
    },
  );
  Future<List<Map<String, dynamic>>> forward(
    String text,
    List<int> chats, {
    bool fix = false,
    String? model,
  }) async {
    final data = await call(
      '/chatbot/send-to-network',
      method: 'POST',
      body: {
        'text': text,
        'chat_ids': chats,
        'ai_fix': fix ? 'auto' : 'off',
        'model': ?model,
      },
    );
    return (data['results'] as List? ?? [])
        .whereType<Map>()
        .map(
          (e) => {
            ...Map<String, dynamic>.from(e),
            'ai_fallback': data['ai_fallback'] == true,
          },
        )
        .toList();
  }

  Future<List<Map<String, dynamic>>> sendStatus(List<int> ids) async {
    final result = await call(
      '/chatbot/network-status',
      method: 'POST',
      body: {'message_ids': ids},
    );
    return (result['data'] as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<Map<String, dynamic>> upload(
    WorkflowFile file, {
    void Function(double)? progress,
  }) async {
    if (file.bytes.length > 50 * 1024 * 1024) {
      throw const ApiFailure('Choose a file no larger than 50 MB.');
    }
    var fingerprint = 0;
    for (final byte in file.bytes) {
      fingerprint = ((fingerprint * 16777619) ^ byte) & 0x7fffffff;
    }
    final cacheKey = 'upload:${file.name}:${file.bytes.length}:$fingerprint';
    final previous = await cached(cacheKey);
    Map<String, dynamic>? start;
    if (previous is Map && previous['upload_id'] is String) {
      try {
        start = await call('/inbox/upload/${previous['upload_id']}');
        if (start['data'] is Map) {
          return Map<String, dynamic>.from(start['data'] as Map);
        }
      } on ApiFailure catch (error) {
        if (error.status != 404) rethrow;
      }
    }
    start ??= await call(
      '/inbox/upload',
      method: 'POST',
      body: {'name': file.name, 'size': file.bytes.length},
    );
    final uploadId = '${start['upload_id']}';
    await cache(cacheKey, {'upload_id': uploadId});
    var offset = (start['offset'] as num?)?.toInt() ?? 0;
    while (offset < file.bytes.length) {
      final end = (offset + 2 * 1024 * 1024).clamp(0, file.bytes.length);
      final request = http.MultipartRequest('POST', api.uri('/inbox/upload'))
        ..headers.addAll(await api.headers());
      request.headers.remove('Content-Type');
      request.fields.addAll({
        'upload_id': uploadId,
        'offset': '$offset',
        'final': end == file.bytes.length ? '1' : '0',
      });
      request.files.add(
        http.MultipartFile.fromBytes(
          'chunk',
          file.bytes.sublist(offset, end),
          filename: 'chunk.bin',
        ),
      );
      final response = await http.Response.fromStream(
        await api.client.send(request).timeout(const Duration(seconds: 9)),
      ).timeout(const Duration(seconds: 9));
      final data = api.decodeResponse(response);
      offset = end;
      progress?.call(offset / file.bytes.length);
      if (offset == file.bytes.length) {
        return Map<String, dynamic>.from(data['data'] as Map);
      }
    }
    if (offset == file.bytes.length && offset > 0) {
      final result = await call(
        '/inbox/upload',
        method: 'POST',
        body: {'upload_id': uploadId, 'offset': offset, 'final': true},
      );
      return Map<String, dynamic>.from(result['data'] as Map);
    }
    throw const ApiFailure('The selected file is empty.');
  }

  Future<void> queueOffline(
    int chat,
    String text, {
    int? replyTo,
    String? clientId,
    List<WorkflowFile> files = const [],
    String mode = 'off',
    String? model,
    String lang = 'en',
  }) async {
    final rows = (await cached('outbox') as List? ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    rows.add({
      'chat_id': chat,
      'body': text,
      'reply_to': replyTo,
      'client_id': clientId ?? SocialPostService.requestId(),
      'files': await Future.wait(files.map(persistInboxFile)),
      'ai_fix': mode,
      'model': model,
      'lang': lang,
      'status': 'offline',
      'created_at': DateTime.now().toIso8601String(),
    });
    await cache('outbox', rows);
  }

  Future<List<Map<String, dynamic>>> outbox(int chat) async =>
      (await cached('outbox') as List? ?? [])
          .whereType<Map>()
          .where((e) => e['chat_id'] == chat)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  bool _flushing = false;
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    final session = await scope();
    final sent = <String>{};
    try {
      final rows = (await cached('outbox') as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      for (final row in rows) {
        if (await scope() != session) break;
        try {
          final files = (row['files'] as List? ?? []).whereType<Map>().toList();
          final attachmentIds = <int>[];
          for (final file in files) {
            final attachment = await upload(await restoreInboxFile(file));
            attachmentIds.add(attachment['id'] as int);
          }
          await send(
            row['chat_id'] as int,
            '${row['body']}',
            clientId: '${row['client_id']}',
            replyTo: row['reply_to'] as int?,
            attachments: attachmentIds,
            mode: '${row['ai_fix'] ?? 'off'}',
            model: row['model'] as String?,
            lang: '${row['lang'] ?? 'en'}',
          );
          sent.add('${row['client_id']}');
          for (final file in files) {
            await removeInboxFile(file);
          }
        } catch (_) {}
      }
      if (await scope() == session) {
        final current = (await cached('outbox') as List? ?? [])
            .whereType<Map>();
        await cache(
          'outbox',
          current
              .where((row) => !sent.contains('${row['client_id']}'))
              .toList(),
        );
      }
    } finally {
      _flushing = false;
    }
  }
}
