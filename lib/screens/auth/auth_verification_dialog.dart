import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../widgets/auth_motion.dart';

class AuthVerificationDialog extends StatefulWidget {
  const AuthVerificationDialog({super.key});
  @override
  State<AuthVerificationDialog> createState() => _AuthVerificationDialogState();
}

class _AuthVerificationDialogState extends State<AuthVerificationDialog> {
  final fields = List.generate(6, (_) => TextEditingController());
  final focus = List.generate(6, (_) => FocusNode());
  String? error;
  void update(int index, String value) {
    setState(() => error = null);
    if (value.length > 1) {
      final start = value.length == 6 ? 0 : index;
      for (var i = 0; i < value.length && start + i < 6; i++) {
        fields[start + i].text = value[i];
      }
      focus[(start + value.length).clamp(0, 5)].requestFocus();
    } else if (value.isNotEmpty && index < 5) {
      focus[index + 1].requestFocus();
    }
  }

  void submit() {
    final code = fields.map((field) => field.text).join();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      setState(() => error = 'Enter all six digits.');
      return;
    }
    Navigator.pop(context, code);
  }

  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    for (final node in focus) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final colors = AuthPalette.of(context);
    return Dialog(
      backgroundColor: colors.page,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: colors.outline),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colors.base.primary.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colors.base.primary.withValues(alpha: .3),
                    ),
                  ),
                  child: Icon(
                    Icons.verified_user_outlined,
                    color: colors.link,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                appTr('Verify your sign-in'),
                style: TextStyle(
                  color: colors.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                appTr('Enter the 6-digit code from your authenticator app.'),
                style: TextStyle(color: colors.muted, height: 1.5),
              ),
              const SizedBox(height: 24),
              AutofillGroup(
                child: Row(
                  children: List.generate(
                    6,
                    (index) => Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: index == 5 ? 0 : 6),
                        child: Semantics(
                          label: appTr("Authenticator code digit :value of 6", {
                            "value": index + 1,
                          }),
                          child: TextField(
                            key: ValueKey('auth-code-$index'),
                            controller: fields[index],
                            focusNode: focus[index],
                            autofocus: index == 0,
                            autofillHints: index == 0
                                ? const [AutofillHints.oneTimeCode]
                                : null,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 18,
                              ),
                              filled: true,
                              fillColor: colors.surface,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (value) => update(index, value),
                            onSubmitted: (_) => submit(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    appTr(error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              AuthPrimaryButton(label: appTr('Verify'), onPressed: submit),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(appTr('Cancel')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
