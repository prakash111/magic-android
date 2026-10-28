import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'mobile_api.dart';

@pragma('vm:entry-point')
Future<void> handlePushInBackground(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: await _loadFirebaseOptions());
}

Future<FirebaseOptions> _loadFirebaseOptions() async {
  final raw = await rootBundle.loadString(
    'assets/firebase/firebase-config.json',
  );
  final configuration = jsonDecode(raw) as Map<String, dynamic>;
  final target = kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
          TargetPlatform.android => 'android',
          _ => '',
        };
  final options = configuration['platforms']?[target];
  if (options is! Map) {
    throw StateError('Firebase is not configured for this platform.');
  }
  return FirebaseOptions(
    apiKey: '${options['apiKey'] ?? ''}',
    appId: '${options['appId'] ?? ''}',
    messagingSenderId: '${options['messagingSenderId'] ?? ''}',
    projectId: '${options['projectId'] ?? ''}',
    authDomain: options['authDomain'] as String?,
    storageBucket: options['storageBucket'] as String?,
    measurementId: options['measurementId'] as String?,
    iosBundleId: options['iosBundleId'] as String?,
  );
}

class PushNotifications {
  PushNotifications._();

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static bool _available = false;
  static String _vapidKey = '';
  static MobileApi _api = MobileApi.instance;
  static StreamSubscription<String>? _refreshSubscription;

  static Future<void> initialize({
    MobileApi? api,
  }) async {
    _api = api ?? MobileApi.instance;
    if (_initialized) return;
    _initialized = true;

    try {
      final target = kIsWeb
          ? 'web'
          : switch (defaultTargetPlatform) {
              TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
              TargetPlatform.android => 'android',
              _ => '',
            };
      final configuration = jsonDecode(
        await rootBundle.loadString('assets/firebase/firebase-config.json'),
      ) as Map<String, dynamic>;
      if ((configuration['platforms'] as Map<String, dynamic>? ?? {})[target]
          is! Map) {
        return;
      }
      final firebaseOptions = await _loadFirebaseOptions();
      if (firebaseOptions.apiKey.isEmpty || firebaseOptions.appId.isEmpty) {
        return;
      }
      _vapidKey = '${configuration['vapidKey'] ?? ''}';
      await Firebase.initializeApp(options: firebaseOptions);
      FirebaseMessaging.onBackgroundMessage(handlePushInBackground);
      await _initializeLocalNotifications();
      FirebaseMessaging.onMessage.listen(_showForegroundMessage);
      _available = true;
      final token = await _readAccessToken();
      if (token != null) unawaited(registerDevice());
    } catch (_) {
      _available = false;
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _localNotifications.initialize(settings: settings);
    const channel = AndroidNotificationChannel(
      'magicai_updates',
      'MagicAI updates',
      description: 'Messages and updates from your MagicAI workspace',
      importance: Importance.high,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  static Future<void> registerDevice() async {
    if (!_available) return;
    try {
      final accessToken = await _readAccessToken();
      if (accessToken == null) return;
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken(
        vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
      );
      if (token == null || token.isEmpty) return;
      await _saveToken(token);
      _refreshSubscription ??= messaging.onTokenRefresh.listen(
        (value) => unawaited(_saveRefreshedToken(value)),
      );
    } catch (_) {
      // Push setup must not block sign-in or app startup.
    }
  }

  static Future<void> unregisterDevice() async {
    if (!_available) return;
    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
      );
      if (token != null && token.isNotEmpty && await _readAccessToken() != null) {
        await _api.request(
          '/notifications/devices',
          method: 'DELETE',
          body: {'token': token},
        );
      }
    } catch (_) {
      // A failed device removal must not prevent local sign-out.
    }
  }

  static Future<void> _saveToken(String token) async {
    if (await _readAccessToken() == null) return;
    await _api.request(
      '/notifications/devices',
      method: 'POST',
      body: {'token': token, 'platform': _platformName},
    );
  }

  static Future<void> _saveRefreshedToken(String token) async {
    try {
      await _saveToken(token);
    } catch (_) {
      // Token refresh retries on the next authenticated registration.
    }
  }

  static Future<String?> _readAccessToken() => _api.store.read('access_token');

  static String get _platformName => kIsWeb
      ? 'web'
      : switch (defaultTargetPlatform) {
          TargetPlatform.iOS || TargetPlatform.macOS => 'ios',
          TargetPlatform.android => 'android',
          _ => 'other',
        };

  static Future<void> _showForegroundMessage(RemoteMessage message) async {
    final title = message.notification?.title ?? 'MagicAI';
    final body = message.notification?.body ?? '';
    if (body.isEmpty) return;
    await _localNotifications.show(
      id: message.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'magicai_updates',
          'MagicAI updates',
          channelDescription: 'Messages and updates from your MagicAI workspace',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data['link']?.toString(),
    );
  }

}
