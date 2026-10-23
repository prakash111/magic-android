import 'dart:async';

import 'package:flutter/services.dart';

import 'mobile_api.dart';

class WorkspaceService {
  final MobileApi api;
  WorkspaceService({MobileApi? api}) : api = api ?? MobileApi.instance;

  Uri trustedUrl(dynamic value) {
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != api.origin.host ||
        uri.port != api.origin.port ||
        uri.userInfo.isNotEmpty ||
        !['/magicai-mobile/', '/mobile/'].any(uri.path.startsWith)) {
      throw const ApiFailure('The server returned an invalid workspace link.');
    }
    return uri;
  }

  Future<void> open({
    required String destination,
    String? moduleId,
    String? platform,
    String? accountId,
    String title = 'Workspace',
    bool browser = false,
  }) async {
    final data = await api.request(
      '/web/session',
      method: 'POST',
      body: {
        'destination': destination,
        'module_id': ?moduleId,
        'platform': ?platform,
        if (accountId != null) 'account_id': int.parse(accountId),
      },
    );
    await openTicket(
      Map<String, dynamic>.from(data as Map),
      title: title,
      browser: browser,
    );
  }

  Future<void> openTicket(
    Map<String, dynamic> data, {
    required String title,
    bool browser = false,
  }) async {
    final url = trustedUrl(data['url']);
    try {
      await SecureStore.invokeMethod<void>('openUrl', {'url': url.toString()});
    } on PlatformException {
      throw const ApiFailure('Unable to open this workspace. Please retry.');
    }
  }
}

class BrowserLoginFlow {
  final MobileApi api;
  final Duration pollInterval;
  bool _cancelled = false;
  BrowserLoginFlow({
    MobileApi? api,
    this.pollInterval = const Duration(seconds: 2),
  }) : api = api ?? MobileApi.instance;
  void cancel() => _cancelled = true;

  Future<Map<String, dynamic>> login({String? provider}) async {
    _cancelled = false;
    final proof = await SecureStore.invokeMapMethod<String, dynamic>(
      'createLoginProof',
    );
    if (proof?['verifier'] is! String || proof?['challenge'] is! String) {
      throw const ApiFailure('Secure sign-in is unavailable on this device.');
    }
    final flow = await api.request(
      '/auth/browser',
      method: 'POST',
      authenticated: false,
      body: {
        'code_challenge': proof!['challenge'],
        'provider': ?provider,
        'return_uri': ?proof['return_uri'],
      },
    ) as Map;
    final url = WorkspaceService(api: api).trustedUrl(flow['url']);
    await SecureStore.invokeMethod<void>('openUrl', {'url': url.toString()});
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    String? authorizationCode;
    while (!_cancelled && DateTime.now().isBefore(deadline)) {
      final returned = await SecureStore.invokeMapMethod<String, dynamic>(
        'consumeAuthReturn',
      );
      if (returned?['flow'] == flow['flow'] && returned?['code'] is String) {
        authorizationCode = returned!['code'] as String;
      }
      if (authorizationCode != null) {
        final result = await api.request(
          '/auth/browser/exchange',
          method: 'POST',
          authenticated: false,
          body: {
            'flow': flow['flow'],
            'code_verifier': proof['verifier'],
            'code': authorizationCode,
          },
        ) as Map<String, dynamic>;
        if (_cancelled) break;
        if (result['access_token'] is String) {
          await api.saveSession(result);
          return result;
        }
        if (result['status'] != 'pending') {
          throw const ApiFailure('Sign-in could not be completed.');
        }
      }
      await Future<void>.delayed(pollInterval);
    }
    throw ApiFailure(
      _cancelled ? 'Sign-in cancelled.' : 'Sign-in expired. Please retry.',
    );
  }
}
