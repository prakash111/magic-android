import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:magicai_mobile/services/mobile_api.dart';

class MemorySecureStore extends SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Map<String, dynamic> license([Map<String, dynamic> changes = const {}]) => {
  'status': 'success',
  'valid': true,
  'app': 'magicai',
  'features': ['chat', 'seo'],
  'session_token': 'server-session',
  'session_expires_at': DateTime.now()
      .toUtc()
      .add(const Duration(minutes: 5))
      .toIso8601String(),
  ...changes,
};
http.Response jsonResponse(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => MobileApi.failure.value = null);
  test('installation identifier persists and credentials travel only to the MagicAI origin', () async {
    final store = MemorySecureStore();
    store.values['access_token'] = 'private-token';
    final client = MockClient((request) async {
      expect(request.url.host, 'magicai.example.test');
      if (request.url.path.endsWith('/license')) {
        final body = jsonDecode(request.body) as Map;
        expect(body['app_identifier'], 'magicai');
        expect(body['instance_hash'], matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(body.containsKey('license_key'), isFalse);
        expect(request.headers.containsKey('authorization'), isFalse);
        return jsonResponse(license());
      }
      expect(request.headers['Authorization'], 'Bearer private-token');
      expect(request.headers['X-Mobile-Session'], 'server-session');
      expect(request.headers['X-Instance-Hash'], store.values['instance_hash']);
      return jsonResponse({'words': 12});
    });
    final api = MobileApi(client: client, store: store);
    expect(await api.request('/credits'), {'words': 12});
    expect(await api.instanceHash, store.values['instance_hash']);
    expect(() => api.uri('//another-app.example'), throwsA(isA<ApiFailure>()));
    expect(() => api.uri('/../auth'), throwsA(isA<ApiFailure>()));
  });
  for (final changes in [
    <String, dynamic>{'app': 'pos'},
    {'valid': false},
    {'valid': 'true'},
    {'session_token': ''},
    {'features': 'chat'},
    {'session_expires_at': 'invalid'},
    {'session_expires_at': '2020-01-01T00:00:00Z'},
  ]) {
    test('invalid license handshake locks access: $changes', () async {
      final api = MobileApi(
        client: MockClient((_) async => jsonResponse(license(changes))),
        store: MemorySecureStore(),
      );
      await expectLater(api.bootstrap(), throwsA(isA<ApiFailure>()));
      expect(MobileApi.failure.value?.code, 'license_invalid');
    });
  }
  test('network failures cannot fabricate successful output', () async {
    final api = MobileApi(
      client: MockClient((_) async => throw http.ClientException('offline')),
      store: MemorySecureStore(),
    );
    await expectLater(api.bootstrap(), throwsA(isA<ApiFailure>()));
    expect(MobileApi.failure.value?.code, 'license_invalid');
  });
  test('a rejected login stays on the credential form', () async {
    final api = MobileApi(
      client: MockClient(
        (request) async => request.url.path.endsWith('/license')
            ? jsonResponse(license())
            : jsonResponse({'message': 'Invalid credentials'}, 401),
      ),
      store: MemorySecureStore(),
    );
    await expectLater(
      api.request(
        '/auth/login',
        method: 'POST',
        authenticated: false,
        body: {'email': 'test@example.com', 'password': 'wrong'},
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(MobileApi.failure.value, isNull);
  });
  test('an expired authenticated session is cleared', () async {
    final store = MemorySecureStore()..values['access_token'] = 'old-token';
    final api = MobileApi(
      client: MockClient(
        (request) async => request.url.path.endsWith('/license')
            ? jsonResponse(license())
            : jsonResponse({'message': 'Unauthenticated'}, 401),
      ),
      store: store,
    );
    await expectLater(api.request('/credits'), throwsA(isA<ApiFailure>()));
    await Future<void>.delayed(Duration.zero);
    expect(store.values['access_token'], isNull);
    expect(MobileApi.failure.value?.status, 401);
  });
  test('near expiry rotates a token once before issuing a request', () async {
    final store = MemorySecureStore();
    store.values.addAll({
      'access_token': 'old-token',
      'access_expires_at': DateTime.now()
          .toUtc()
          .add(const Duration(minutes: 1))
          .toIso8601String(),
    });
    var rotations = 0;
    final api = MobileApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license')) {
          return jsonResponse(license());
        }
        if (request.url.path.endsWith('/auth/refresh')) {
          rotations++;
          return jsonResponse({
            'access_token': 'new-token',
            'expires_at': DateTime.now()
                .toUtc()
                .add(const Duration(days: 1))
                .toIso8601String(),
          });
        }
        expect(request.headers['Authorization'], 'Bearer new-token');
        return jsonResponse({'words': 10});
      }),
      store: store,
    );
    await api.bootstrap();
    await Future.wait([api.request('/credits'), api.request('/credits')]);
    expect(rotations, 1);
  });
  test('stream decoder handles fragmented UTF-8 and SSE boundaries', () async {
    final store = MemorySecureStore()..values['access_token'] = 'token';
    final api = MobileApi(
      client: MockClient.streaming((request, _) async {
        if (request.url.path.endsWith('/license')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode(license()))),
            200,
          );
        }
        final bytes = utf8.encode(
          'data: {"delta":"Hello 🌍"}\n\ndata: {"delta":"!"}\n\ndata: {"done":true}\n\n',
        );
        return http.StreamedResponse(
          Stream.fromIterable(bytes.map((byte) => [byte])),
          200,
        );
      }),
      store: store,
    );
    expect(
      await api.stream('/chat/conversations/1/stream').join(),
      'Hello 🌍!',
    );
  });
  test('truncated streams and provider errors are reported', () async {
    for (final output in [
      'data: {"delta":"partial"}\n\n',
      'data: {"error":"Provider failed"}\n\n',
    ]) {
      final store = MemorySecureStore()..values['access_token'] = 'token';
      final api = MobileApi(
        client: MockClient(
          (request) async => request.url.path.endsWith('/license')
              ? jsonResponse(license())
              : http.Response(output, 200),
        ),
        store: store,
      );
      await expectLater(
        api.stream('/chat/conversations/1/stream').join(),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
  test(
    'legacy writer streams preserve content and detect completion',
    () async {
      final store = MemorySecureStore()..values['access_token'] = 'token';
      final api = MobileApi(
        client: MockClient(
          (request) async => request.url.path.endsWith('/license')
              ? jsonResponse(license())
              : http.Response('Hello<br/>world\ndata: [DONE]\n\n', 200),
        ),
        store: store,
      );
      expect(
        await api.stream('/writer/1/stream', legacy: true).join(),
        'Hello\nworld',
      );
    },
  );
  test('credit exhaustion and provider validation stay actionable', () async {
    final store = MemorySecureStore()..values['access_token'] = 'token';
    final api = MobileApi(
      client: MockClient(
        (request) async => request.url.path.endsWith('/license')
            ? jsonResponse(license())
            : jsonResponse({
                'errors': ['Insufficient credits to generate audio.'],
              }, 429),
      ),
      store: store,
    );
    await expectLater(
      api.request('/tools/mobile-audio/run', method: 'POST'),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.message,
          'message',
          'Insufficient credits to generate audio.',
        ),
      ),
    );
    expect(MobileApi.failure.value, isNull);
  });
}
