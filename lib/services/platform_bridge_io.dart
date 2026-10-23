import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlatformBridge {
  static void handleReturn() {}
  static const channel = MethodChannel('com.magicai.mobile/secure');
  static HttpServer? _callback;
  static Map<String, dynamic>? _returned;
  static bool get _mobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
  static Future<String> _run(
    String program,
    List<String> args, {
    String? input,
  }) async {
    final process = await Process.start(program, args);
    if (input != null) process.stdin.write(input);
    await process.stdin.close();
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.drain<void>();
    final code = await process.exitCode.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        process.kill();
        return -1;
      },
    );
    await errors;
    final value = await output;
    if (code != 0) {
      throw PlatformException(
        code: 'platform_unavailable',
        message: 'The system secure store or file picker is unavailable.',
      );
    }
    return value.trim();
  }

  static Future<T?> invokeMethod<T>(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    if (_mobile) return channel.invokeMethod<T>(method, arguments);
    final args = arguments ?? {};
    dynamic value;
    final key = '${args['key'] ?? ''}';
    if (['read', 'write', 'delete'].contains(method)) {
      if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(key)) {
        throw PlatformException(code: 'invalid_key');
      }
      if (Platform.isMacOS) {
        return channel.invokeMethod<T>(method, arguments);
      } else if (Platform.isLinux) {
        final commands = method == 'read'
            ? ['lookup', 'application', 'magicai', 'key', key]
            : method == 'delete'
            ? ['clear', 'application', 'magicai', 'key', key]
            : [
                'store',
                '--label=MagicAI',
                'application',
                'magicai',
                'key',
                key,
              ];
        try {
          final result = await _run(
            'secret-tool',
            commands,
            input: method == 'write' ? '${args['value']}' : null,
          );
          if (method == 'read' && result.isNotEmpty) value = result;
        } on PlatformException {
          if (method == 'write') rethrow;
        }
      } else {
        final directory = Directory(
          '${Platform.environment['LOCALAPPDATA']}\\MagicAI',
        );
        await directory.create(recursive: true);
        final path = '${directory.path}\\$key';
        final encodedPath = base64Encode(utf8.encode(path));
        final script =
            "Add-Type -AssemblyName System.Security; \$p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$encodedPath')); ${method == 'read'
                ? "if(Test-Path -LiteralPath \$p){[Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes(\$p),\$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))}"
                : method == 'delete'
                ? "if(Test-Path -LiteralPath \$p){Remove-Item -LiteralPath \$p}"
                : "\$v=[Convert]::FromBase64String([Console]::In.ReadToEnd());[IO.File]::WriteAllBytes(\$p,[Security.Cryptography.ProtectedData]::Protect(\$v,\$null,[Security.Cryptography.DataProtectionScope]::CurrentUser))"}";
        final result = await _run(
          'powershell',
          ['-NoProfile', '-NonInteractive', '-Command', script],
          input: method == 'write'
              ? base64Encode(utf8.encode('${args['value']}'))
              : null,
        );
        if (method == 'read' && result.isNotEmpty) value = result;
      }
    } else if (method == 'openUrl') {
      final uri = Uri.parse('${args['url']}');
      if (uri.scheme != 'https') throw PlatformException(code: 'invalid_url');
      if (Platform.isWindows) {
        await _run('rundll32', ['url.dll,FileProtocolHandler', '$uri']);
      } else {
        await _run(Platform.isMacOS ? 'open' : 'xdg-open', ['$uri']);
      }
    } else if (method == 'createLoginProof') {
      await _callback?.close(force: true);
      _callback = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _returned = null;
      _callback!.listen((request) async {
        if (request.uri.path == '/auth/complete') {
          _returned = {
            'code': request.uri.queryParameters['code'],
            'flow': request.uri.queryParameters['flow'],
          };
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<!doctype html><title>MagicAI</title><p>You can return to MagicAI.</p>',
          );
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });
      final verifier = base64UrlEncode(
        List.generate(32, (_) => Random.secure().nextInt(256)),
      ).replaceAll('=', '');
      String challenge;
      if (Platform.isWindows) {
        challenge = await _run('powershell', [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          "[Convert]::ToBase64String([Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::ASCII.GetBytes('$verifier'))).TrimEnd('=').Replace('+','-').Replace('/','_')",
        ]);
      } else {
        final process = await Process.start('openssl', [
          'dgst',
          '-sha256',
          '-binary',
        ]);
        process.stdin.write(verifier);
        await process.stdin.close();
        final bytes = await process.stdout.fold<List<int>>(
          [],
          (out, bytes) => out..addAll(bytes),
        );
        if (await process.exitCode != 0) {
          throw PlatformException(code: 'proof_unavailable');
        }
        challenge = base64UrlEncode(bytes).replaceAll('=', '');
      }
      value = {
        'verifier': verifier,
        'challenge': challenge,
        'return_uri': 'http://127.0.0.1:${_callback!.port}/auth/complete',
      };
    } else if (method == 'consumeAuthReturn') {
      value = _returned;
      _returned = null;
      if (value != null) {
        await _callback?.close(force: true);
        _callback = null;
      }
    } else if (method == 'pickFile' || method == 'pickImage') {
      final path = Platform.isMacOS
          ? await _run('osascript', ['-e', 'POSIX path of (choose file)'])
          : Platform.isWindows
          ? await _run('powershell', [
              '-NoProfile',
              '-Command',
              'Add-Type -AssemblyName System.Windows.Forms; \$d=New-Object System.Windows.Forms.OpenFileDialog;if(\$d.ShowDialog() -eq "OK"){\$d.FileName}',
            ])
          : await _run('zenity', ['--file-selection']);
      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.length() > 50 * 1024 * 1024) {
          throw PlatformException(code: 'file_too_large');
        }
        value = {
          'name': file.uri.pathSegments.last,
          'bytes': await file.readAsBytes(),
        };
      }
    } else if (method != 'clearWebSession') {
      throw PlatformException(
        code: 'unsupported',
        message: 'This visual editor is not available on this platform yet.',
      );
    }
    return value as T?;
  }

  static Future<Map<K, V>?> invokeMapMethod<K, V>(
    String method, [
    Map<String, dynamic>? args,
  ]) async => (await invokeMethod<Map>(method, args))?.cast<K, V>();
}
