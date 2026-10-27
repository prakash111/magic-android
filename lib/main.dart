import 'dart:async';

import 'services/image_attachment_picker.dart';

import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'screens/auth/login_screen.dart';
import 'services/mobile_api.dart';
import 'services/app_localizations.dart';
import 'services/framework_localizations.dart';

import 'package:flutter/cupertino.dart' show CupertinoLocalizations;

import 'services/platform_bridge_io.dart'
    if (dart.library.js_interop) 'services/platform_bridge_web.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'theme/brand_config.dart';
import 'theme/theme_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(ImageAttachmentPicker.recoverLostSelection());
  PlatformBridge.handleReturn();
  runApp(const MagicAIMobileApp(initialTheme: 'dark'));
}

class MagicAIMobileApp extends StatefulWidget {
  final String initialTheme;
  final MobileApi? api;
  final Future<String> Function()? loadTheme;
  final AppLocalizations? localizations;

  const MagicAIMobileApp({
    super.key,
    required this.initialTheme,
    this.api,
    this.loadTheme,
    this.localizations,
  });

  @override
  State<MagicAIMobileApp> createState() => _MagicAIMobileAppState();
}

class _MagicAIMobileAppState extends State<MagicAIMobileApp>
    with WidgetsBindingObserver {
  late final AppLocalizations _localizations;
  late final AppLocalizations _previousLocalizations;
  late ThemeMode _themeMode;
  bool _themeChanged = false;
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _previousLocalizations = AppLocalizations.current;
    _localizations = widget.localizations ?? AppLocalizations(api: widget.api);
    AppLocalizations.current = _localizations;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_localizations.initialize());
    _themeMode = widget.initialTheme == 'light'
        ? ThemeMode.light
        : widget.initialTheme == 'system'
        ? ThemeMode.system
        : ThemeMode.dark;
    WidgetsBinding.instance.addPostFrameCallback((_) => _restoreTheme());
  }

  Future<void> _restoreTheme() async {
    try {
      final saved = await (widget.loadTheme ?? StorageService.getThemeMode)()
          .timeout(const Duration(seconds: 2));
      if (!mounted || _themeChanged) return;
      setState(
        () => _themeMode = switch (saved) {
          'light' => ThemeMode.light,
          'system' => ThemeMode.system,
          _ => ThemeMode.dark,
        },
      );
    } catch (_) {
      // Theme preferences must never block the first frame or sign-in.
    }
  }

  void _updateTheme(ThemeMode mode) {
    _themeChanged = true;
    setState(() => _themeMode = mode);
    StorageService.setThemeMode(mode.name).catchError((Object _) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_localizations.refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(AppLocalizations.current, _localizations)) {
      AppLocalizations.current = _previousLocalizations;
    }
    if (widget.localizations == null) _localizations.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    return ListenableBuilder(
      listenable: _localizations,
      builder: (context, _) {
        AppLocalizations.watch(context);
        return MaterialApp(
          locale: _localizations.locale,
          supportedLocales: _localizations.languages.isEmpty
              ? [_localizations.locale]
              : _localizations.languages.map((language) => language.locale),
          localizationsDelegates: [
            AppTranslationsDelegate(_localizations),
            ServerLocalizationsDelegate<MaterialLocalizations>(
              () => const ServerMaterialLocalizations(),
              _localizations.revision,
            ),
            ServerLocalizationsDelegate<CupertinoLocalizations>(
              () => const ServerCupertinoLocalizations(),
              _localizations.revision,
            ),
            ServerLocalizationsDelegate<WidgetsLocalizations>(
              () => const ServerWidgetsLocalizations(),
              _localizations.revision,
            ),
          ],
          themeAnimationDuration: Duration.zero,
          title: BrandConfig.name,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _themeMode,
          builder: (context, child) {
            AppLocalizations.watch(context);
            return ThemeSettings(
              mode: _themeMode,
              onChanged: _updateTheme,
              child: ValueListenableBuilder<ApiFailure?>(
                valueListenable: MobileApi.failure,
                builder: (context, problem, _) {
                  AppLocalizations.watch(context);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Offstage(offstage: problem != null, child: child!),
                      if (problem != null)
                        Scaffold(
                          body: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    appTr(
                                      problem.status == 401
                                          ? 'Session expired'
                                          : 'No Internet Connection',
                                    ),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    appTr(
                                      problem.status == 401 ? problem.message : 'Unable to connect to the server. Please check your internet connection and try again.',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  FilledButton(
                                    onPressed: () async {
                                      if (problem.status == 401) {
                                        MobileApi.failure.value = null;
                                        navigatorKey.currentState
                                            ?.pushAndRemoveUntil(
                                              MaterialPageRoute(
                                                builder: (localizationContext) {
                                                  AppLocalizations.watch(
                                                    localizationContext,
                                                  );
                                                  return LoginScreen(
                                                    onThemeChanged:
                                                        _updateTheme,
                                                    api: widget.api,
                                                  );
                                                },
                                              ),
                                              (_) => false,
                                            );
                                      } else {
                                        try {
                                          await (widget.api ??
                                                  MobileApi.instance)
                                              .bootstrap()
                                              .timeout(
                                                const Duration(seconds: 30),
                                              );
                                          MobileApi.failure.value = null;
                                          navigatorKey.currentState
                                              ?.pushAndRemoveUntil(
                                                MaterialPageRoute(
                                                  builder:
                                                      (localizationContext) {
                                                        AppLocalizations.watch(
                                                          localizationContext,
                                                        );
                                                        return SplashScreen(
                                                          onThemeChanged:
                                                              _updateTheme,
                                                          api: widget.api,
                                                        );
                                                      },
                                                ),
                                                (_) => false,
                                              );
                                        } catch (_) {}
                                      }
                                    },
                                    child: Text(
                                      appTr(
                                        problem.status == 401
                                            ? 'Sign in'
                                            : 'Retry',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
          navigatorKey: navigatorKey,
          home: SplashScreen(onThemeChanged: _updateTheme, api: widget.api),
        );
      },
    );
  }
}
