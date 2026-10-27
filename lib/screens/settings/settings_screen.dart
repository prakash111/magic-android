import '../../services/app_localizations.dart';
import '../../widgets/language_picker.dart';

import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/brand_config.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Function(ThemeMode) onThemeChanged;
  const SettingsScreen({super.key, required this.onThemeChanged});
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      appBar: AppBar(title: Text(appTr('Settings'))),
      body: ListView(
        children: [
          ListTile(
            title: Text(appTr('Language')),
            trailing: const LanguagePicker(),
          ),
          const ListTile(
            title: Text(BrandConfig.name),
            subtitle: Text(BrandConfig.company),
          ),
          if (BrandConfig.supportEmail.isNotEmpty)
            ListTile(
              title: Text(appTr('Support email')),
              subtitle: Text(BrandConfig.supportEmail),
            ),
          if (BrandConfig.supportPhone.isNotEmpty)
            ListTile(
              title: Text(appTr('Support phone')),
              subtitle: Text(BrandConfig.supportPhone),
            ),
          if (BrandConfig.copyright.isNotEmpty)
            const ListTile(title: Text(BrandConfig.copyright)),
          ListTile(
            title: Text(appTr('Light theme')),
            onTap: () => onThemeChanged(ThemeMode.light),
          ),
          ListTile(
            title: Text(appTr('Dark theme')),
            onTap: () => onThemeChanged(ThemeMode.dark),
          ),
          ListTile(
            title: Text(appTr('Sign out')),
            onTap: () async {
              try {
                await ApiService.logout();
              } catch (_) {}
              if (!context.mounted) {
                return;
              }
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return LoginScreen(onThemeChanged: onThemeChanged);
                  },
                ),
                (_) => false,
              );
            },
          ),
        ],
      ),
    );
  }
}
