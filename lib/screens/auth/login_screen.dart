import 'social_provider_icon.dart';
import 'auth_links.dart';
import 'auth_verification_dialog.dart';
import '../../widgets/auth_motion.dart';

import 'package:flutter/material.dart';

import '../../theme/brand_config.dart';

import '../../services/api_service.dart';
import '../../services/mobile_api.dart';
import '../../services/workspace_service.dart';
import '../../services/storage_service.dart';
import '../../models/user_model.dart';
import '../home_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final MobileApi? api;
  const LoginScreen({super.key, required this.onThemeChanged, this.api});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _obscure = true, _signedIn = false, _awaitingMfa = false;
  List<Map<String, dynamic>> _providers = [];
  BrowserLoginFlow? _browserFlow;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    try {
      final providers = await ApiService.getSocialLoginOptions(
        client: widget.api,
      );
      if (mounted) setState(() => _providers = providers);
    } catch (_) {
      if (mounted) setState(() => _providers = []);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadProviders();
  }

  Future<void> _browserLogin([String? provider]) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _browserFlow = BrowserLoginFlow();
    try {
      final data = await _browserFlow!.login(provider: provider);
      await StorageService.saveUser(
        UserModel.fromJson(Map<String, dynamic>.from(data['user'] as Map)),
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => _signedIn = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _error;
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _browserFlow?.cancel();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      try {
        await ApiService.login(
          email: _email.text.trim(),
          password: _password.text,
          client: widget.api,
        );
      } on ApiFailure catch (failure) {
        if (failure.code != 'mfa_required' &&
            !(failure.status == 422 &&
                failure.message.toLowerCase().contains(
                  'two-factor authentication code',
                ))) {
          rethrow;
        }
        if (!mounted) return;
        setState(() => _awaitingMfa = true);
        final code = await _verifyAuthenticator();
        if (!mounted) return;
        setState(() => _awaitingMfa = false);
        if (code == null) return;
        await ApiService.login(
          email: _email.text.trim(),
          password: _password.text,
          otp: code,
          client: widget.api,
        );
      }
      if (!mounted) {
        return;
      }
      FocusScope.of(context).unfocus();
      setState(() => _signedIn = true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _verifyAuthenticator() => showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AuthVerificationDialog(),
  );

  void _enterWorkspace() => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(
      builder: (_) =>
          HomeScreen(onThemeChanged: widget.onThemeChanged, api: widget.api),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = AuthPalette.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: colors.page,
      body: AuthScene(
        child: SafeArea(
          child: _signedIn
              ? AuthSuccess(onContinue: _enterWorkspace)
              : LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(26, 36, 26, 16),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: (constraints.maxHeight - 52).clamp(
                              0,
                              double.infinity,
                            ),
                          ),
                          child: Form(
                            key: _form,
                            child: AutofillGroup(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      const Center(child: AuthMark()),
                                      const SizedBox(height: 22),
                                      AuthEntrance(
                                        index: 1,
                                        child: Text(
                                          'Welcome back',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: colors.text,
                                            fontSize: 29,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: -.4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      AuthEntrance(
                                        index: 2,
                                        child: Text(
                                          'Sign in to your AI workspace',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: colors.muted,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 28),
                                      AuthEntrance(
                                        index: 3,
                                        child: SocialLoginButtons(
                                          providers: _providers,
                                          busy: _busy,
                                          onSelected: _browserLogin,
                                        ),
                                      ),
                                      if (_providers.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Divider(
                                                  color: colors.outline,
                                                ),
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 14,
                                                    ),
                                                child: Text(
                                                  'or sign in with email',
                                                  style: TextStyle(
                                                    color: colors.muted,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Divider(
                                                  color: colors.outline,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      AuthEntrance(
                                        index: 4,
                                        horizontal: true,
                                        child: AuthInput(
                                          controller: _email,
                                          label: 'Email',
                                          icon: Icons.mail_outline_rounded,
                                          enabled: !_busy,
                                          keyboardType:
                                              TextInputType.emailAddress,
                                          textInputAction: TextInputAction.next,
                                          autofillHints: const [
                                            AutofillHints.username,
                                          ],
                                          validator: (value) =>
                                              (value?.contains('@') ?? false)
                                              ? null
                                              : 'Enter your email',
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      AuthEntrance(
                                        index: 5,
                                        horizontal: true,
                                        child: AuthInput(
                                          controller: _password,
                                          label: 'Password',
                                          icon: Icons.lock_outline_rounded,
                                          enabled: !_busy,
                                          obscure: _obscure,
                                          textInputAction: TextInputAction.done,
                                          autofillHints: const [
                                            AutofillHints.password,
                                          ],
                                          suffix: IconButton(
                                            tooltip: _obscure
                                                ? 'Show password'
                                                : 'Hide password',
                                            onPressed: _busy
                                                ? null
                                                : () => setState(
                                                    () => _obscure = !_obscure,
                                                  ),
                                            icon: Icon(
                                              _obscure
                                                  ? Icons.visibility_outlined
                                                  : Icons
                                                        .visibility_off_outlined,
                                              size: 21,
                                              color: colors.muted,
                                            ),
                                          ),
                                          validator: (value) =>
                                              (value?.isNotEmpty ?? false)
                                              ? null
                                              : 'Enter your password',
                                          onSubmitted: (_) {
                                            if (!_busy) _login();
                                          },
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => openAuthPage(
                                                  context,
                                                  widget.api ??
                                                      MobileApi.instance,
                                                  '/forgot-password',
                                                ),
                                          child: const Text('Forgot password?'),
                                        ),
                                      ),
                                      if (_error != null)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 16,
                                          ),
                                          child: Semantics(
                                            liveRegion: true,
                                            child: Text(
                                              _error!,
                                              style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error,
                                              ),
                                            ),
                                          ),
                                        ),
                                      AuthEntrance(
                                        index: 6,
                                        child: AuthPrimaryButton(
                                          label: 'Sign In',
                                          busyLabel: 'Signing in…',
                                          busy: _busy && !_awaitingMfa,
                                          onPressed: _busy ? null : _login,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      AuthEntrance(
                                        index: 7,
                                        child: OutlinedButton.icon(
                                          onPressed: _busy
                                              ? null
                                              : () => _browserLogin(),
                                          icon: const Icon(
                                            Icons.lock_outline,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Secure browser sign-in',
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(
                                              50,
                                            ),
                                            foregroundColor: colors.link,
                                            backgroundColor: colors.base.primary
                                                .withValues(alpha: .08),
                                            side: BorderSide(
                                              color: colors.base.primary
                                                  .withValues(alpha: .25),
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (_busy && _browserFlow != null)
                                        TextButton(
                                          onPressed: () =>
                                              _browserFlow?.cancel(),
                                          child: const Text('Cancel sign-in'),
                                        ),
                                    ],
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 28),
                                    child: AuthEntrance(
                                      index: 8,
                                      child: Wrap(
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'New to ${BrandConfig.name}?',
                                            style: TextStyle(
                                              color: colors.muted,
                                              fontSize: 14,
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => Navigator.push(
                                                    context,
                                                    authRoute(
                                                      context,
                                                      (_) => RegisterScreen(
                                                        onThemeChanged: widget
                                                            .onThemeChanged,
                                                        api: widget.api,
                                                      ),
                                                    ),
                                                  ),
                                            child: const Text(
                                              'Create an account',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class SocialLoginButtons extends StatelessWidget {
  final List<Map<String, dynamic>> providers;
  final bool busy;
  final ValueChanged<String> onSelected;
  const SocialLoginButtons({
    super.key,
    required this.providers,
    required this.onSelected,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final provider in providers.where(
        (provider) =>
            provider['available'] == true &&
            provider['enabled'] != false &&
            const ['google', 'facebook', 'github'].contains(provider['id']),
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              backgroundColor: AuthPalette.of(context).surface,
              foregroundColor: AuthPalette.of(context).text,
              side: BorderSide(color: AuthPalette.of(context).outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            onPressed: busy
                ? null
                : () => onSelected(provider['id'].toString()),
            icon: SocialProviderIcon('${provider['id']}'),
            label: Text(
              'Login with ${provider['id'] == 'github' ? 'Github' : provider['label']}',
            ),
          ),
        ),
    ],
  );
}
