import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:magicai_mobile/models/user_model.dart';
import 'package:magicai_mobile/services/storage_service.dart';

import 'android_ui_probe.dart';
import 'android_studio_probe.dart';

const _prefix = 'release_preferences_probe_';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (WidgetsBinding.instance.platformDispatcher.defaultRouteName ==
      '/studio-regression') {
    runApp(AndroidStudioProbe());
  } else if (WidgetsBinding.instance.platformDispatcher.defaultRouteName ==
      '/creative-regression') {
    runApp(AndroidStudioProbe(mode: 'creative'));
  } else if (WidgetsBinding.instance.platformDispatcher.defaultRouteName ==
      '/video-regression') {
    runApp(AndroidStudioProbe(mode: 'video'));
  } else if (WidgetsBinding.instance.platformDispatcher.defaultRouteName ==
      '/ui-regression') {
    final mode = await StorageService.getThemeMode();
    runApp(
      AndroidUiProbe(
        initialMode: mode == 'light' ? ThemeMode.light : ThemeMode.dark,
      ),
    );
  } else {
    runApp(const _PreferencesProbe());
  }
}

class _PreferencesProbe extends StatefulWidget {
  const _PreferencesProbe();

  @override
  State<_PreferencesProbe> createState() => _PreferencesProbeState();
}

class _PreferencesProbeState extends State<_PreferencesProbe> {
  String _status = 'Checking preferences';

  @override
  void initState() {
    super.initState();
    _verify();
  }

  void _require(bool condition, String message) {
    if (!condition) throw StateError(message);
  }

  Future<void> _verify() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final resumed = prefs.getBool('${_prefix}ready') == true;
      if (!resumed) {
        final originalUser = prefs.getString('auth_user');
        if (originalUser != null) {
          await prefs.setString('${_prefix}original_user', originalUser);
        }
        await prefs.setString('${_prefix}string', 'round-trip');
        await prefs.setInt('${_prefix}int', 42);
        await prefs.setDouble('${_prefix}double', 1.25);
        await prefs.setStringList('${_prefix}list', ['first', 'second']);
        await prefs.setString('${_prefix}remove', 'temporary');
        await prefs.remove('${_prefix}remove');
        await StorageService.saveUser(
          UserModel.fromJson({
            'id': 0,
            'name': 'Storage regression',
            'email': 'storage-probe@example.invalid',
          }),
        );
        await prefs.setBool('${_prefix}ready', true);
      }

      await prefs.reload();
      _require(
        prefs.getString('${_prefix}string') == 'round-trip',
        'String read/write failed',
      );
      _require(
        prefs.getInt('${_prefix}int') == 42,
        'Integer read/write failed',
      );
      _require(
        prefs.getDouble('${_prefix}double') == 1.25,
        'Double read/write failed',
      );
      _require(
        jsonEncode(prefs.getStringList('${_prefix}list')) ==
            '["first","second"]',
        'List read/write failed',
      );
      _require(
        !prefs.containsKey('${_prefix}remove'),
        'Preference removal failed',
      );
      _require(
        prefs.getBool('${_prefix}ready') == true,
        'Boolean read/write failed',
      );
      final user = await StorageService.getUser();
      _require(
        user?.email == 'storage-probe@example.invalid',
        'Login profile persistence failed',
      );

      if (resumed) {
        final originalUser = prefs.getString('${_prefix}original_user');
        if (originalUser == null) {
          await prefs.remove('auth_user');
        } else {
          await prefs.setString('auth_user', originalUser);
        }
        for (final key
            in prefs
                .getKeys()
                .where((key) => key.startsWith(_prefix))
                .toList()) {
          await prefs.remove(key);
        }
      }
      if (mounted) {
        setState(
          () => _status = resumed
              ? 'Preferences persisted across restart'
              : 'Preferences read and write verified',
        );
      }
      debugPrint(
        'PREFERENCES_PROBE_PASSED: ${resumed ? 'restart' : 'read-write-profile'}',
      );
    } catch (error) {
      debugPrint('PREFERENCES_PROBE_FAILED: $error');
      if (mounted) setState(() => _status = 'Preferences verification failed');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(body: Center(child: Text(_status))),
  );
}
