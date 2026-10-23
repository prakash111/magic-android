import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/services.dart';

@JS('crypto.getRandomValues')
external JSUint8Array _random(JSUint8Array bytes);
@JS('crypto.subtle.digest')
external JSPromise<JSArrayBuffer> _digest(
  JSString algorithm,
  JSUint8Array data,
);
@JS('window.open')
external JSObject? _open(JSString url, JSString target, JSString features);
@JS('window.location.origin')
external JSString get _origin;
@JS('window.addEventListener')
external void _listen(JSString event, JSFunction listener);
@JS('window.opener')
external JSObject? get _opener;
@JS('window.opener.postMessage')
external void _post(JSAny message, JSString origin);
@JS('window.location.href')
external JSString get _href;
@JS('window.close')
external void _close();
@JS('document.createElement')
external JSObject _element(JSString tag);

extension type _Input(JSObject _) implements JSObject {
  external set type(JSString value);
  external set accept(JSString value);
  external set onchange(JSFunction fn);
  external set oncancel(JSFunction fn);
  external JSArray<_File>? get files;
  external void click();
}

extension type _File(JSObject _) implements JSObject {
  external JSString get name;
  external JSNumber get size;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

extension type _Message(JSObject _) implements JSObject {
  external JSString get origin;
  external JSAny? get data;
}

extension type _Popup(JSObject _) implements JSObject {
  external set location(JSString url);
  external void close();
}

class PlatformBridge {
  static _Popup? _authWindow;
  static final Map<String, String> _memory = {};
  static Map<String, dynamic>? _returned;
  static bool _listening = false;
  static void handleReturn() {
    final uri = Uri.parse(_href.toDart);
    if (uri.path.endsWith('/auth/complete') &&
        uri.queryParameters['code'] != null &&
        _opener != null) {
      _post(
        jsonEncode({
          'flow': uri.queryParameters['flow'],
          'code': uri.queryParameters['code'],
        }).toJS,
        _origin,
      );
      _close();
    }
  }

  static Future<T?> invokeMethod<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final args = arguments ?? {};
    dynamic result;
    if (method == 'read') {
      result = _memory['${args['key']}'];
    } else if (method == 'write') {
      _memory['${args['key']}'] = '${args['value']}';
    } else if (method == 'delete') {
      _memory.remove('${args['key']}');
    } else if (method == 'openUrl') {
      final uri = Uri.parse('${args['url']}');
      if (uri.scheme != 'https') throw PlatformException(code: 'invalid_url');
      if (_authWindow != null) {
        _authWindow!.location = '$uri'.toJS;
      } else {
        _open('$uri'.toJS, '_blank'.toJS, 'noopener'.toJS);
      }
    } else if (method == 'createLoginProof') {
      final popup = _open('about:blank'.toJS, '_blank'.toJS, ''.toJS);
      if (popup == null) {
        throw PlatformException(
          code: 'popup',
          message: 'Allow the sign-in popup to continue.',
        );
      }
      _authWindow = _Popup(popup);
      if (!_listening) {
        _listening = true;
        _listen(
          'message'.toJS,
          ((JSObject event) {
            final message = _Message(event);
            if (message.origin.toDart == _origin.toDart &&
                message.data.isA<JSString>()) {
              try {
                _returned = Map<String, dynamic>.from(
                  jsonDecode((message.data as JSString).toDart) as Map,
                );
              } catch (_) {}
            }
          }).toJS,
        );
      }
      final bytes = _random(Uint8List(32).toJS).toDart;
      final verifier = base64UrlEncode(bytes).replaceAll('=', '');
      final hash = await _digest(
        'SHA-256'.toJS,
        Uint8List.fromList(utf8.encode(verifier)).toJS,
      ).toDart;
      result = {
        'verifier': verifier,
        'challenge': base64UrlEncode(hash.toDart.asUint8List())
            .replaceAll('=', ''),
        'return_uri': '${_origin.toDart}/auth/complete',
      };
    } else if (method == 'consumeAuthReturn') {
      result = _returned;
      _returned = null;
      if (result != null) {
        _authWindow?.close();
        _authWindow = null;
      }
    } else if (method == 'pickFile' || method == 'pickImage') {
      final completer = Completer<Map<String, dynamic>?>();
      final input = _Input(_element('input'.toJS))
        ..type = 'file'.toJS
        ..accept =
            '${args['accept'] ?? (method == 'pickImage' ? 'image/*' : '*/*')}'
                .toJS;
      input.onchange = (() {
        final file = input.files?.toDart.firstOrNull;
        if (file == null) {
          completer.complete(null);
          return;
        }
        if (file.size.toDartInt > 50 * 1024 * 1024) {
          completer.completeError(PlatformException(code: 'file_too_large'));
          return;
        }
        file.arrayBuffer().toDart.then(
          (bytes) => completer.complete({
            'name': file.name.toDart,
            'bytes': bytes.toDart.asUint8List(),
          }),
        );
      }).toJS;
      input.oncancel = (() {
        if (!completer.isCompleted) completer.complete(null);
      }).toJS;
      input.click();
      result = await completer.future;
    } else if (method != 'clearWebSession') {
      throw PlatformException(
        code: 'unsupported',
        message: 'This editor is not yet available for Web.',
      );
    }
    return result as T?;
  }

  static Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Map<String, dynamic>? args,
  ]) async => (await invokeMethod<Map>(method, args))?.cast<K, V>();
}
