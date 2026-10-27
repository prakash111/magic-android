import 'dart:async';
import 'dart:convert';

import 'image_attachment_picker.dart';

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../theme/brand_config.dart';
import 'platform_bridge_io.dart'
    if (dart.library.js_interop) 'platform_bridge_web.dart';

class ApiFailure implements Exception {
  final String message;
  final int status;
  final String code;
  const ApiFailure(this.message, {this.status = 0, this.code = ''});
  @override
  String toString() => message;
}

class SecureStore {
  static const channel = MethodChannel('com.magicai.mobile/secure');
  static Future<T?> invokeMethod<T>(
    String method, [
    Map<String, dynamic>? args,
  ]) => PlatformBridge.invokeMethod<T>(method, args);
  static Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Map<String, dynamic>? args,
  ]) => PlatformBridge.invokeMapMethod<K, V>(method, args);
  Future<String?> read(String key) => invokeMethod<String>('read', {
    'key': key,
  }).timeout(const Duration(seconds: 5));
  Future<void> write(String key, String value) => invokeMethod<void>('write', {
    'key': key,
    'value': value,
  }).timeout(const Duration(seconds: 5));
  Future<void> delete(String key) => invokeMethod<void>('delete', {
    'key': key,
  }).timeout(const Duration(seconds: 5));
}

class TenantSecureStore extends SecureStore {
  final SecureStore delegate;
  final String authority;
  late final String _prefix = _namespace(authority);

  TenantSecureStore(this.delegate, Uri origin)
    : authority = '${origin.scheme}://${origin.authority}';

  static String _namespace(String value) {
    var hash = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    for (final byte in utf8.encode(value)) {
      hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
    }
    return 'tenant_${hash.toRadixString(16)}_';
  }

  Future<void> _verifyAuthority() async {
    final key = '${_prefix}origin';
    if (await delegate.read(key) != authority) {
      await delegate.delete('${_prefix}access_token');
      await delegate.delete('${_prefix}access_expires_at');
      await delegate.write(key, authority);
    }
  }

  @override
  Future<String?> read(String key) async {
    await _verifyAuthority();
    return delegate.read('$_prefix$key');
  }

  @override
  Future<void> write(String key, String value) async {
    await _verifyAuthority();
    await delegate.write('$_prefix$key', value);
  }

  @override
  Future<void> delete(String key) async {
    await _verifyAuthority();
    await delegate.delete('$_prefix$key');
  }
}

class MobileApi {
  static String? languageCode;
  static final instance = MobileApi();
  static final failure = ValueNotifier<ApiFailure?>(null);
  final http.Client client;
  final SecureStore store;
  final Uri origin;
  String? _session;
  DateTime? _sessionExpiry;
  Future<void>? _handshake;
  Future<void>? _refresh;

  MobileApi({http.Client? client, SecureStore? store, Uri? origin})
    : client = client ?? http.Client(),
      store =
          store ??
          TenantSecureStore(
            SecureStore(),
            origin ?? Uri.parse(BrandConfig.serverUrl),
          ),
      origin = origin ?? Uri.parse(BrandConfig.serverUrl);

  Future<String> get instanceHash async {
    var hash = await store.read('instance_hash');
    if (hash == null) {
      final random = Random.secure();
      hash = List.generate(
        32,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await store.write('instance_hash', hash);
    }
    return hash;
  }

  Uri uri(String path) {
    if (origin.scheme != 'https' ||
        origin.host.isEmpty ||
        origin.userInfo.isNotEmpty ||
        origin.hasQuery ||
        origin.hasFragment ||
        (origin.path.isNotEmpty && origin.path != '/')) {
      throw const ApiFailure(
        'Build with a valid HTTPS MAGICAI_SERVER_URL for your MagicAI installation.',
      );
    }
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        path.contains('://') ||
        path.contains('..')) {
      throw const ApiFailure('Invalid server action.');
    }
    return origin.resolve('/api/mobile/v1$path');
  }

  Future<void> bootstrap() async {
    if (_handshake != null) return _handshake;
    final pending = _verify();
    _handshake = pending;
    try {
      await pending;
    } finally {
      _handshake = null;
    }
  }

  Future<void> _silentBootstrap() async {
    if (_handshake != null) return _handshake;
    final pending = _verify(notifyFailure: false);
    _handshake = pending;
    try {
      await pending;
    } finally {
      _handshake = null;
    }
  }

  Future<void> _verify({bool notifyFailure = true}) async {
    _session = null;
    _sessionExpiry = null;
    try {
      final response = await client
          .post(
            uri('/license'),
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'app_identifier': 'magicai',
              'instance_hash': await instanceHash,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = _decode(
        response,
        notifyAuth: false,
        notifyLicense: notifyFailure,
      );
      if (data is! Map ||
          data['valid'] != true ||
          data['status'] != 'success' ||
          data['app'] != 'magicai' ||
          data['session_token'] is! String ||
          (data['session_token'] as String).isEmpty ||
          data['features'] is! List) {
        throw const ApiFailure(
          'License handshake could not be verified.',
          code: 'license_invalid',
        );
      }
      _sessionExpiry = DateTime.parse(data['session_expires_at'] as String)
          .toUtc();
      if (!_sessionExpiry!.isAfter(DateTime.now().toUtc())) {
        throw const ApiFailure('License Invalid / Expired');
      }
      _session = data['session_token'] as String;
    } catch (error) {
      debugPrint(
        'MagicAI startup check: ${error.runtimeType}'
        '${error is PlatformException ? ' (${error.code})' : ''}',
      );
      final problem = ApiFailure(
        error is ApiFailure ? error.message : 'Unable to connect to the server. Please check your internet connection and try again.',
        code: 'license_invalid',
      );
      if (notifyFailure) failure.value = problem;
      throw problem;
    }
  }

  Future<Map<String, String>> headers({
    bool authenticated = true,
    bool notifyAuthFailure = true,
    bool notifyLicenseFailure = true,
  }) async {
    if (_session == null ||
        _sessionExpiry == null ||
        DateTime.now()
            .toUtc()
            .add(const Duration(seconds: 10))
            .isAfter(_sessionExpiry!)) {
      await (notifyLicenseFailure ? bootstrap() : _silentBootstrap());
    }
    if (authenticated) {
      await _refreshIfNeeded(notifyAuthFailure: notifyAuthFailure);
    }
    final token = authenticated ? await store.read('access_token') : null;
    if (authenticated && (token == null || token.isEmpty)) {
      throw const ApiFailure('Please sign in.', status: 401);
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (languageCode != null)
        'Accept-Language': languageCode!.replaceAll('_', '-'),
      'X-Mobile-Session': _session!,
      'X-Instance-Hash': await instanceHash,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<void> _refreshIfNeeded({bool notifyAuthFailure = true}) async {
    final pending = _refresh ??= _checkAndRotate(
      notifyAuthFailure: notifyAuthFailure,
    );
    try {
      await pending;
    } finally {
      if (identical(_refresh, pending)) {
        _refresh = null;
      }
    }
  }

  Future<void> _checkAndRotate({bool notifyAuthFailure = true}) async {
    final expiry = DateTime.tryParse(
      await store.read('access_expires_at') ?? '',
    );
    if (expiry == null ||
        expiry.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 5)),
        )) {
      return;
    }
    await _rotate(notifyAuthFailure: notifyAuthFailure);
  }

  Future<void> _rotate({bool notifyAuthFailure = true}) async {
    final token = await store.read('access_token');
    final response = await client
        .post(
          uri('/auth/refresh'),
          headers: {
            'Accept': 'application/json',
            'X-Mobile-Session': _session!,
            'X-Instance-Hash': await instanceHash,
            'Authorization': 'Bearer $token',
          },
        )
        .timeout(const Duration(seconds: 20));
    final data = _decode(
      response,
      notifyAuth: notifyAuthFailure,
    ) as Map<String, dynamic>;
    await saveSession(data);
  }

  Future<void> saveSession(Map<String, dynamic> data) async {
    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ApiFailure('Server did not return an access token.');
    }
    await store.write('access_token', token);
    if (data['expires_at'] is String) {
      await store.write('access_expires_at', data['expires_at'] as String);
    }
    failure.value = null;
  }

  Future<void> clearSession() async {
    await store.delete('access_token');
    await store.delete('access_expires_at');
    await store.delete('document_snapshot_cache');
    try {
      await SecureStore.invokeMethod<void>('clearWebSession')
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Platforms without visual editors have no embedded session to clear.
    }
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool authenticated = true,
    bool notifyAuthFailure = true,
    bool notifyLicenseFailure = true,
  }) async {
    try {
      final readOnly =
          method == 'GET' ||
          (method == 'POST' &&
              ((path == '/native/screen' && body?['action'] == null) ||
                  path == '/native/workspace' ||
                  (path == '/native/chat-tools' &&
                      body?['operation'] == 'list') ||
                  (path == '/native/extension' &&
                      body?['operation'] == 'load') ||
                  (const ['/native/workflow', '/native/media'].contains(path) &&
                      [
                        'describe',
                        'history',
                        'status',
                      ].contains(body?['operation']))));
      Future<dynamic> execute() async {
        final request = http.Request(method, uri(path))
          ..headers.addAll(
            await headers(
              authenticated: authenticated,
              notifyAuthFailure: notifyAuthFailure,
              notifyLicenseFailure: notifyLicenseFailure,
            ),
          );
        if (body != null) request.body = jsonEncode(body);
        final response = await http.Response.fromStream(
          await client.send(request).timeout(const Duration(seconds: 30)),
        ).timeout(const Duration(seconds: 120));
        return _decode(
          response,
          notifyAuth: authenticated && notifyAuthFailure,
          notifyLicense: notifyLicenseFailure,
        );
      }

      return await execute().timeout(
        readOnly ? const Duration(seconds: 10) : const Duration(seconds: 150),
      );
    } on ApiFailure {
      rethrow;
    } on TimeoutException {
      throw const ApiFailure('The server took too long. Please retry.');
    } catch (_) {
      throw const ApiFailure(
        'Unable to connect. Check your connection and retry.',
      );
    }
  }

  Future<String> uploadImage(List<int> bytes, String name) async {
    final mime = ImageAttachmentPicker.imageMimeType(bytes);
    if (bytes.isEmpty || mime == null) {
      throw const ApiFailure('Choose a valid JPEG, PNG or WebP image.');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw const ApiFailure('Choose an image no larger than 10 MB.');
    }
    final upload = http.MultipartRequest(
      'POST',
      uri('/social-media/attachments'),
    );
    upload.headers.addAll(await headers());
    upload.headers.remove('Content-Type');
    upload.files.add(
      http.MultipartFile.fromBytes(
        'image',
        bytes,
        filename: name,
        contentType: http.MediaType.parse(mime),
      ),
    );
    try {
      final response = await http.Response.fromStream(
        await client.send(upload).timeout(const Duration(seconds: 30)),
      ).timeout(const Duration(seconds: 60));
      final result = _decode(response);
      if (result is! Map || result['url'] is! String) {
        throw const ApiFailure('The image upload did not complete.');
      }
      return result['url'] as String;
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('Unable to upload the image. Please retry.');
    }
  }

  dynamic decodeResponse(http.Response response) => _decode(response);

  dynamic _decode(
    http.Response response, {
    bool notifyAuth = true,
    bool notifyLicense = true,
  }) {
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw ApiFailure(
        'Unexpected server response (${response.statusCode}).',
        status: response.statusCode,
      );
    }
    if (response.statusCode >= 200 &&
        response.statusCode < 300 &&
        !(data is Map && data['status'] == 'error')) {
      return data;
    }
    var message = data is Map
        ? (data['message'] ?? data['error'])?.toString()
        : null;
    if (data is Map &&
        data['errors'] is Map &&
        (data['errors'] as Map).isNotEmpty) {
      final errors = (data['errors'] as Map).values.first;
      message = errors is List ? errors.first.toString() : errors.toString();
    }
    if (data is Map &&
        data['errors'] is List &&
        (data['errors'] as List).isNotEmpty) {
      message = (data['errors'] as List).first.toString();
    }
    if (kDebugMode) {
      debugPrint(
        'Mobile API error: HTTP ${response.statusCode}; code=${data is Map ? data['code'] ?? '' : ''}; validation_fields=${data is Map && data['errors'] is Map ? (data['errors'] as Map).keys.join(',') : ''}',
      );
    }
    final problem = ApiFailure(
      message ?? 'Request failed (${response.statusCode}).',
      status: response.statusCode,
      code: data is Map ? data['code']?.toString() ?? '' : '',
    );
    if (response.statusCode == 401 && notifyAuth) {
      unawaited(clearSession().catchError((Object _) {}));
      failure.value = problem;
    } else if (problem.code == 'license_invalid' && notifyLicense) {
      failure.value = problem;
    }
    throw problem;
  }

  Stream<String> stream(
    String path, {
    Map<String, dynamic>? body,
    bool legacy = false,
  }) async* {
    final request = http.Request('POST', uri(path))
      ..headers.addAll(await headers());
    request.headers['Accept'] = 'application/json, text/event-stream';
    request.body = jsonEncode(body ?? {});
    late http.StreamedResponse response;
    try {
      response = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw const ApiFailure('Unable to connect. Please retry.');
    }
    if (response.statusCode != 200) {
      _decode(await http.Response.fromStream(response));
      return;
    }
    var completed = false;
    try {
      await for (final line
          in response.stream
              .timeout(const Duration(seconds: 120))
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (line.startsWith('error:')) {
          final detail = line.substring(6).trim();
          throw ApiFailure(
            detail.isEmpty
                ? 'The AI provider could not complete this request. Please retry.'
                : detail,
          );
        }
        if (line == 'data: [DONE]') {
          completed = true;
          break;
        }
        if (line.startsWith('data: ')) {
          final event = jsonDecode(line.substring(6));
          if (event is Map && event['error'] != null) {
            throw ApiFailure(event['error'].toString());
          }
          if (event is Map && event['done'] == true) {
            completed = true;
            break;
          }
          if (event is Map && event['delta'] is String) {
            yield event['delta'] as String;
          }
        } else if (legacy && line.isNotEmpty) {
          yield line.replaceAll('<br/>', '\n');
        }
      }
    } on ApiFailure {
      rethrow;
    } catch (_) {
      throw const ApiFailure('The response was interrupted. Please retry.');
    }
    if (!completed) {
      throw const ApiFailure('The response was interrupted before completion.');
    }
  }
}
