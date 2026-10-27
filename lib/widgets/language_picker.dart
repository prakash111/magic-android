import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

class LanguagePicker extends StatelessWidget {
  const LanguagePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final translations = AppLocalizations.watch(context);
    final colors = AppColors.of(context);
    return ListenableBuilder(
      listenable: translations,
      builder: (context, _) {
        AppLocalizations.watch(context);
        return Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: PopupMenuButton<String>(
            key: const ValueKey('app-language-picker'),
            tooltip: appTr('Language'),
            initialValue: translations.localeCode,
            enabled: !translations.refreshing,
            onOpened: () => unawaited(translations.refresh()),
            onSelected: (value) => unawaited(
              value == '__refresh'
                  ? translations.refresh()
                  : translations.select(value),
            ),
            itemBuilder: (context) {
              AppLocalizations.watch(context);
              return [
                for (final language in translations.languages)
                  PopupMenuItem(
                    value: language.code,
                    child: Row(
                      children: [
                        Expanded(child: Text(language.nativeName)),
                        const SizedBox(width: 16),
                        if (language.code == translations.localeCode)
                          Icon(Icons.check, color: colors.primary, size: 18),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: '__refresh',
                  child: Row(
                    children: [
                      const Icon(Icons.refresh, size: 18),
                      const SizedBox(width: 10),
                      Text(appTr('Refresh')),
                    ],
                  ),
                ),
                if (translations.error != null)
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      appTr(translations.error!),
                      style: TextStyle(color: colors.muted),
                    ),
                  ),
              ];
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: colors.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.language_rounded, color: colors.primary, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    translations.localeCode.replaceAll('_', '-').toUpperCase(),
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 7),
                  if (translations.refreshing)
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: colors.text,
                      ),
                    )
                  else
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: colors.text,
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
