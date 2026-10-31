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
  static Timer? _retryTimer;
  static bool _registering = false;
  static const _tokenKey = 'firebase_registration_token';

  static void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(
      const Duration(seconds: 45),
      () => unawaited(registerDevice()),
    );
  }

  static Future<void> initialize({MobileApi? api}) async {
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
      if (!kIsWeb) await _initializeLocalNotifications();
      _refreshSubscription ??= FirebaseMessaging.instance.onTokenRefresh.listen(
        (value) => unawaited(_saveRefreshedToken(value)),
        onError: (Object _) => _scheduleRetry(),
      );
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
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
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
    if (!_available || _registering) return;
    _registering = true;
    _retryTimer?.cancel();
    try {
      final accessToken = await _readAccessToken();
      if (accessToken == null) return;
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.denied) return;
      final token = await messaging.getToken(
        vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
      );
      if (token == null || token.isEmpty) {
        _scheduleRetry();
        return;
      }
      await _saveToken(token);
    } catch (_) {
      _scheduleRetry();
    } finally {
      _registering = false;
    }
  }

  static Future<void> unregisterDevice() async {
    _retryTimer?.cancel();
    if (!_available) return;
    try {
      final token =
          await _api.store.read(_tokenKey) ??
          await FirebaseMessaging.instance.getToken(
            vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
          );
      if (token != null &&
          token.isNotEmpty &&
          await _readAccessToken() != null) {
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
    await _api.store.write(_tokenKey, token);
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
      _scheduleRetry();
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
    if (kIsWeb) return;
    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'MagicAI';
    final body =
        message.notification?.body ?? message.data['body']?.toString() ?? '';
    if (body.isEmpty) return;
    await _localNotifications.show(
      id: message.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'magicai_updates',
          'MagicAI updates',
          channelDescription:
              'Messages and updates from your MagicAI workspace',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: message.data['link']?.toString(),
    );
  }
}
