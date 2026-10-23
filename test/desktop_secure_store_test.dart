import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/services/platform_bridge_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Windows persists encrypted credentials with current-user DPAPI',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      const key = 'desktop_secure_store_test';
      const value = 'private-test-session-123';
      try {
        await PlatformBridge.invokeMethod<void>('write', {
          'key': key,
          'value': value,
        });
        expect(
          await PlatformBridge.invokeMethod<String>('read', {'key': key}),
          value,
        );
        final file = File(
          '${Platform.environment['LOCALAPPDATA']}\\MagicAI\\$key',
        );
        expect(
          String.fromCharCodes(await file.readAsBytes()),
          isNot(contains(value)),
        );
        await PlatformBridge.invokeMethod<void>('delete', {'key': key});
        expect(
          await PlatformBridge.invokeMethod<String>('read', {'key': key}),
          isNull,
        );
      } finally {
        await PlatformBridge.invokeMethod<void>('delete', {'key': key});
      }
    },
    skip: !Platform.isWindows,
  );
}
