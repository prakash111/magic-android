import 'social_provider_icon.dart';

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
  bool _busy = false, _obscure = true;
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            onThemeChanged: widget.onThemeChanged,
            api: widget.api,
          ),
        ),
      );
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
        final code = await _verifyAuthenticator();
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => HomeScreen(
            onThemeChanged: widget.onThemeChanged,
            api: widget.api,
          ),
        ),
      );
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

  Future<String?> _verifyAuthenticator() async {
    var code = '';
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verify your sign-in'),
        content: Form(
          key: form,
          child: TextFormField(
            onChanged: (value) => code = value,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: 'Authenticator code',
              helperText: 'Enter the code from your authenticator app',
            ),
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : 'Enter the six-digit code',
            onFieldSubmitted: (_) {
              if (form.currentState!.validate()) {
                Navigator.pop(context, code);
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, code);
              }
            },
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    return result;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    resizeToAvoidBottomInset: true,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to ${BrandConfig.name}',
                    style: Theme.of(context).textTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sign in to your AI workspace',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SocialLoginButtons(
                    providers: _providers,
                    busy: _busy,
                    onSelected: _browserLogin,
                  ),
                  if (_providers.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'or sign in with email',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (value) => (value?.contains('@') ?? false)
                        ? null
                        : 'Enter your email',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) => (value?.isNotEmpty ?? false)
                        ? null
                        : 'Enter your password',
                    onFieldSubmitted: (_) {
                      if (!_busy) {
                        _login();
                      }
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    child: Text(_busy ? 'Signing in…' : 'Sign In'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RegisterScreen(
                                onThemeChanged: widget.onThemeChanged,
                              ),
                            ),
                          ),
                    child: const Text('Create an account'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _browserLogin(),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Secure browser sign-in'),
                  ),
                  if (_busy && _browserFlow != null)
                    TextButton(
                      onPressed: () => _browserFlow?.cancel(),
                      child: const Text('Cancel sign-in'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
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
