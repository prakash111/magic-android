import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/brand_config.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final Function(ThemeMode) onThemeChanged;
  const SettingsScreen({super.key, required this.onThemeChanged});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      children: [
        const ListTile(
          title: Text(BrandConfig.name),
          subtitle: Text(BrandConfig.company),
        ),
        if (BrandConfig.supportEmail.isNotEmpty)
          const ListTile(
            title: Text('Support email'),
            subtitle: Text(BrandConfig.supportEmail),
          ),
        if (BrandConfig.supportPhone.isNotEmpty)
          const ListTile(
            title: Text('Support phone'),
            subtitle: Text(BrandConfig.supportPhone),
          ),
        if (BrandConfig.copyright.isNotEmpty)
          const ListTile(title: Text(BrandConfig.copyright)),
        ListTile(
          title: const Text('Light theme'),
          onTap: () => onThemeChanged(ThemeMode.light),
        ),
        ListTile(
          title: const Text('Dark theme'),
          onTap: () => onThemeChanged(ThemeMode.dark),
        ),
        ListTile(
          title: const Text('Sign out'),
          onTap: () async {
            try {
              await ApiService.logout();
            } catch (_) {}
            if (!context.mounted) {
              return;
            }
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => LoginScreen(onThemeChanged: onThemeChanged),
              ),
              (_) => false,
            );
          },
        ),
      ],
    ),
  );
}
