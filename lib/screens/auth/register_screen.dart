import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/mobile_api.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_motion.dart';
import '../home_screen.dart';
import 'auth_links.dart';

class RegisterScreen extends StatefulWidget {
  final Function(ThemeMode) onThemeChanged;
  final MobileApi? api;
  const RegisterScreen({super.key, required this.onThemeChanged, this.api});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final form = GlobalKey<FormState>();
  final first = TextEditingController(), last = TextEditingController();
  final email = TextEditingController(),
      password = TextEditingController(),
      confirm = TextEditingController();
  final inputFocus = List.generate(5, (_) => FocusNode());
  bool obscure = true, busy = false, agreed = false, registered = false;
  String? error;
  static bool validEmail(String value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());
  List<bool> get rules => [
    password.text.length >= 8,
    RegExp('[a-z]').hasMatch(password.text) &&
        RegExp('[A-Z]').hasMatch(password.text),
    RegExp(r'\d').hasMatch(password.text),
  ];
  int get strength => password.text.isEmpty
      ? 0
      : rules.where((value) => value).length +
            (RegExp(r'[^a-zA-Z0-9]').hasMatch(password.text) &&
                    password.text.length >= 8
                ? 1
                : 0);
  double get progress =>
      [
        first.text.trim().isNotEmpty,
        last.text.trim().isNotEmpty,
        validEmail(email.text),
        password.text.length >= 8,
        confirm.text.isNotEmpty && confirm.text == password.text,
        agreed,
      ].where((value) => value).length /
      6;
  void changed(String _) => setState(() {});

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ApiService.register(
        name: first.text.trim(),
        surname: last.text.trim(),
        email: email.text.trim(),
        password: password.text,
        client: widget.api,
      );
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      setState(() => registered = true);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    for (final controller in [first, last, email, password, confirm]) {
      controller.dispose();
    }
    for (final node in inputFocus) {
      node.dispose();
    }
    super.dispose();
  }

  Widget strengthMeter(AuthPalette colors) {
    final labels = ['Enter a password', 'Weak', 'Fair', 'Good', 'Strong'];
    final tint = [
      colors.muted,
      AppTheme.error,
      AppTheme.warning,
      colors.base.glowHighlight,
      colors.success,
    ][strength];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Semantics(
          label: appTr("Password strength: :value", {
            "value": appTr(labels[strength]),
          }),
          child: Row(
            children: List.generate(
              4,
              (index) => Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: index == 3 ? 0 : 6),
                  child: AnimatedContainer(
                    duration: Duration(
                      milliseconds: MediaQuery.disableAnimationsOf(context)
                          ? 0
                          : 300,
                    ),
                    height: 4,
                    decoration: BoxDecoration(
                      color: index < strength ? tint : colors.outline,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              appTr('Password strength'),
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
            Text(
              appTr(labels[strength]),
              style: TextStyle(
                color: tint,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: List.generate(
            3,
            (index) => AnimatedContainer(
              duration: Duration(
                milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 250,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
              decoration: BoxDecoration(
                color: rules[index]
                    ? colors.success.withValues(alpha: .09)
                    : colors.surface,
                border: Border.all(
                  color: rules[index]
                      ? colors.success.withValues(alpha: .35)
                      : colors.outline,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    rules[index] ? Icons.check_rounded : Icons.circle_outlined,
                    size: 13,
                    color: rules[index] ? colors.success : colors.muted,
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      appTr(
                        [
                          '8+ characters',
                          'Upper & lower case',
                          'A number',
                        ][index],
                      ),
                      style: TextStyle(
                        color: rules[index] ? colors.success : colors.muted,
                        fontSize: 11,
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
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final colors = AuthPalette.of(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: colors.page,
      body: AuthScene(
        child: SafeArea(
          child: registered
              ? AuthSuccess(
                  title: appTr('You’re all set'),
                  onContinue: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (localizationContext) {
                        AppLocalizations.watch(localizationContext);
                        return HomeScreen(
                          onThemeChanged: widget.onThemeChanged,
                          api: widget.api,
                        );
                      },
                    ),
                    (_) => false,
                  ),
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 18, 26, 20),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Form(
                        key: form,
                        child: AutofillGroup(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: AuthEntrance(
                                  child: IconButton.filledTonal(
                                    tooltip: appTr('Back to sign in'),
                                    onPressed: busy
                                        ? null
                                        : () => Navigator.pop(context),
                                    style: IconButton.styleFrom(
                                      backgroundColor: colors.surface,
                                      foregroundColor: colors.text,
                                      side: BorderSide(color: colors.outline),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                    ),
                                    icon: const Icon(Icons.arrow_back_rounded),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              AuthEntrance(
                                index: 1,
                                child: Text(
                                  appTr('Create your account'),
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
                                  appTr(
                                    'Unlock the full suite of AI generation, SEO & social tools.',
                                  ),
                                  style: TextStyle(
                                    color: colors.muted,
                                    fontSize: 14.5,
                                    height: 1.45,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              AuthEntrance(
                                index: 3,
                                child: Column(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(5),
                                      child: TweenAnimationBuilder<double>(
                                        duration: Duration(
                                          milliseconds:
                                              MediaQuery.disableAnimationsOf(
                                                context,
                                              )
                                              ? 0
                                              : 500,
                                        ),
                                        curve: Curves.easeOutCubic,
                                        tween: Tween(end: progress),
                                        builder:
                                            (localizationContext, value, _) {
                                              AppLocalizations.watch(
                                                localizationContext,
                                              );
                                              return LinearProgressIndicator(
                                                value: value,
                                                minHeight: 6,
                                                backgroundColor: colors.outline,
                                                color: colors.cyan,
                                                semanticsLabel: appTr(
                                                  'Account form completion',
                                                ),
                                              );
                                            },
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            appTr(
                                              progress == 1
                                                  ? 'Ready to create your account'
                                                  : progress >= .5
                                                  ? 'Almost there'
                                                  : 'Let’s get started',
                                            ),
                                            style: TextStyle(
                                              color: colors.muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          '${(progress * 100).round()}%',
                                          style: TextStyle(
                                            color: colors.link,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 22),
                              AuthEntrance(
                                index: 4,
                                horizontal: true,
                                child: LayoutBuilder(
                                  builder: (localizationContext, constraints) {
                                    AppLocalizations.watch(localizationContext);
                                    final names = [
                                      AuthInput(
                                        controller: first,
                                        focusNode: inputFocus[0],
                                        onSubmitted: (_) =>
                                            inputFocus[1].requestFocus(),
                                        label: appTr('First Name'),
                                        enabled: !busy,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.givenName,
                                        ],
                                        onChanged: changed,
                                        validator: (value) =>
                                            value == null ||
                                                value.trim().isEmpty
                                            ? appTr('Required')
                                            : null,
                                      ),
                                      AuthInput(
                                        controller: last,
                                        focusNode: inputFocus[1],
                                        onSubmitted: (_) =>
                                            inputFocus[2].requestFocus(),
                                        label: appTr('Last Name'),
                                        enabled: !busy,
                                        textInputAction: TextInputAction.next,
                                        autofillHints: const [
                                          AutofillHints.familyName,
                                        ],
                                        onChanged: changed,
                                        validator: (value) =>
                                            value == null ||
                                                value.trim().isEmpty
                                            ? appTr('Required')
                                            : null,
                                      ),
                                    ];
                                    if (constraints.maxWidth < 300 ||
                                        MediaQuery.textScalerOf(context)
                                                .scale(14) >
                                            18) {
                                      return Column(
                                        children: [
                                          names[0],
                                          const SizedBox(height: 14),
                                          names[1],
                                        ],
                                      );
                                    }
                                    return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: names[0]),
                                        const SizedBox(width: 12),
                                        Expanded(child: names[1]),
                                      ],
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 14),
                              AuthEntrance(
                                index: 5,
                                horizontal: true,
                                child: AuthInput(
                                  controller: email,
                                  focusNode: inputFocus[2],
                                  onSubmitted: (_) =>
                                      inputFocus[3].requestFocus(),
                                  label: appTr('Email address'),
                                  icon: Icons.mail_outline_rounded,
                                  enabled: !busy,
                                  keyboardType: TextInputType.emailAddress,
                                  autofillHints: const [AutofillHints.email],
                                  textInputAction: TextInputAction.next,
                                  onChanged: changed,
                                  validator: (value) => validEmail(value ?? '')
                                      ? null
                                      : appTr('Enter a valid email address.'),
                                  suffix: validEmail(email.text)
                                      ? Icon(
                                          Icons.check_rounded,
                                          color: colors.success,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 14),
                              AuthEntrance(
                                index: 6,
                                horizontal: true,
                                child: AuthInput(
                                  controller: password,
                                  focusNode: inputFocus[3],
                                  onSubmitted: (_) =>
                                      inputFocus[4].requestFocus(),
                                  label: appTr('Password'),
                                  icon: Icons.lock_outline_rounded,
                                  enabled: !busy,
                                  obscure: obscure,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  onChanged: changed,
                                  validator: (value) =>
                                      value == null || value.length < 8
                                      ? appTr('Use at least 8 characters.')
                                      : null,
                                  suffix: IconButton(
                                    tooltip: appTr(
                                      obscure
                                          ? 'Show password'
                                          : 'Hide password',
                                    ),
                                    onPressed: busy
                                        ? null
                                        : () => setState(
                                            () => obscure = !obscure,
                                          ),
                                    icon: Icon(
                                      obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: colors.muted,
                                      size: 21,
                                    ),
                                  ),
                                ),
                              ),
                              strengthMeter(colors),
                              const SizedBox(height: 16),
                              AuthEntrance(
                                index: 7,
                                horizontal: true,
                                child: AuthInput(
                                  controller: confirm,
                                  focusNode: inputFocus[4],
                                  label: appTr('Confirm password'),
                                  icon: Icons.lock_outline_rounded,
                                  enabled: !busy,
                                  obscure: obscure,
                                  textInputAction: TextInputAction.done,
                                  autofillHints: const [
                                    AutofillHints.newPassword,
                                  ],
                                  onChanged: changed,
                                  validator: (value) =>
                                      value == null || value.isEmpty
                                      ? appTr('Please confirm your password.')
                                      : value != password.text
                                      ? appTr('Passwords do not match.')
                                      : null,
                                  onSubmitted: (_) => submit(),
                                  suffix:
                                      confirm.text.isNotEmpty &&
                                          confirm.text == password.text
                                      ? Icon(
                                          Icons.check_rounded,
                                          color: colors.success,
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(height: 12),
                              FormField<bool>(
                                initialValue: false,
                                validator: (value) => value == true
                                    ? null
                                    : appTr(
                                        'Please accept the terms and privacy policy.',
                                      ),
                                builder: (field) {
                                  AppLocalizations.watch(field.context);
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Checkbox(
                                            value: agreed,
                                            onChanged: busy
                                                ? null
                                                : (value) {
                                                    field.didChange(value);
                                                    setState(
                                                      () => agreed =
                                                          value ?? false,
                                                    );
                                                  },
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                          ),
                                          Expanded(
                                            child: Wrap(
                                              crossAxisAlignment:
                                                  WrapCrossAlignment.center,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 12,
                                                      ),
                                                  child: Text(
                                                    appTr('I agree to the '),
                                                    style: TextStyle(
                                                      color: colors.muted,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () => openAuthPage(
                                                    context,
                                                    widget.api ??
                                                        MobileApi.instance,
                                                    '/terms',
                                                  ),
                                                  child: Text(
                                                    appTr('Terms of Service'),
                                                  ),
                                                ),
                                                Text(
                                                  appTr('and'),
                                                  style: TextStyle(
                                                    color: colors.muted,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () => openAuthPage(
                                                    context,
                                                    widget.api ??
                                                        MobileApi.instance,
                                                    '/privacy-policy',
                                                  ),
                                                  child: Text(
                                                    appTr('Privacy Policy'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (field.hasError)
                                        Text(
                                          appTr(field.errorText!),
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 16),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      appTr(error!),
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error,
                                      ),
                                    ),
                                  ),
                                ),
                              AuthEntrance(
                                index: 8,
                                child: AuthPrimaryButton(
                                  label: appTr('Create Account'),
                                  busy: busy,
                                  busyLabel: 'Creating your account…',
                                  onPressed: submit,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(
                                    appTr('Already have an account?'),
                                    style: TextStyle(
                                      color: colors.muted,
                                      fontSize: 14,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => Navigator.pop(context),
                                    child: Text(appTr('Sign In')),
                                  ),
                                ],
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
    );
  }
}
