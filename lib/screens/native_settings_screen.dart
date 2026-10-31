import '../services/app_localizations.dart';
import '../widgets/language_picker.dart';

import 'package:flutter/material.dart';

import '../services/mobile_api.dart';
import '../services/workspace_service.dart';
import '../theme/theme_settings.dart';
import 'server_screen.dart' show RetryPanel;

class NativeSettingsScreen extends StatefulWidget {
  final MobileApi api;
  const NativeSettingsScreen({super.key, required this.api});
  @override
  State<NativeSettingsScreen> createState() => _NativeSettingsScreenState();
}

class _NativeSettingsScreenState extends State<NativeSettingsScreen> {
  Map? _profile;
  String? _error;
  bool _opening = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await widget.api.request('/auth/profile');
      if (data is! Map) throw const ApiFailure('Unable to load your account.');
      if (mounted) {
        setState(() {
          _profile = data;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _security() async {
    setState(() => _opening = true);
    try {
      await WorkspaceService(
        api: widget.api,
      ).open(destination: 'profile', title: 'Account security', browser: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_profile == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : RetryPanel(message: appTr(_error!), retry: _load),
      );
    }
    final theme = ThemeSettings.of(context);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            appTr('Your account'),
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(appTr('Manage your profile, security and preferences.')),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 28,
                    child: Icon(Icons.person_outline, size: 30),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${_profile!['name'] ?? ''} ${_profile!['surname'] ?? ''}'
                        .trim(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  SelectableText('${_profile!['email'] ?? ''}'),
                ],
              ),
            ),
          ),
          Card(
            child: ListTile(
              title: Text(appTr('Language')),
              trailing: const LanguagePicker(),
            ),
          ),
          if (theme != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DropdownButtonFormField<ThemeMode>(
                  key: ValueKey(theme.mode),
                  initialValue: theme.mode,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: appTr('Appearance'),
                    prefixIcon: Icon(Icons.palette_outlined),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(appTr('Dark')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(appTr('Light')),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(appTr('System')),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) theme.onChanged(mode);
                  },
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.shield_outlined, size: 32),
                  const SizedBox(height: 12),
                  Text(
                    appTr('Keep your account secure'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    appTr(
                      'Update your profile, password and two-factor authentication securely.',
                    ),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _opening ? null : _security,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(
                      appTr(
                        _opening ? 'Opening…' : 'Manage profile & security',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(appTr(_error!)),
            ),
        ],
      ),
    );
  }
}
