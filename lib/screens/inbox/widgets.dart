import 'package:flutter/material.dart';

import '../../services/app_localizations.dart';
import '../../services/inbox_service.dart';

class InboxStateView extends StatelessWidget {
  final bool loading;
  final String? error;
  final String empty;
  final VoidCallback retry;
  const InboxStateView({
    super.key,
    this.loading = false,
    this.error,
    required this.empty,
    required this.retry,
  });
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return ListView(
        children: List.generate(
          5,
          (_) => Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0x226366f1),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: 14,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                      const SizedBox(height: 10),
                      Container(
                        height: 10,
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 16),
            Text(appTr(error ?? empty), textAlign: TextAlign.center),
            if (error != null)
              TextButton(onPressed: retry, child: Text(appTr('Retry'))),
          ],
        ),
      ),
    );
  }
}

String inboxTime(Object? raw) {
  final date = DateTime.tryParse('$raw')?.toLocal();
  if (date == null) return '';
  final now = DateTime.now();
  if (now.year == date.year && now.month == date.month && now.day == date.day) {
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
  return '${date.day}/${date.month}';
}

class InboxConnectionHelp extends StatelessWidget {
  final Future<void> Function() openSettings;
  const InboxConnectionHelp({super.key, required this.openSettings});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          appTr('Connect Telegram and WhatsApp'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          appTr(
            'Connect your bot or WhatsApp Cloud API account in Marketing Bot settings. Return to the app to refresh your chats.',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: openSettings,
          icon: const Icon(Icons.settings_outlined),
          label: Text(appTr('Open connection settings')),
        ),
        const SizedBox(height: 12),
      ],
    ),
  );
}

class InboxConnectionsSheet extends StatefulWidget {
  final InboxService service;
  final Future<void> Function() openSettings;
  const InboxConnectionsSheet({
    super.key,
    required this.service,
    required this.openSettings,
  });
  @override
  State<InboxConnectionsSheet> createState() => _InboxConnectionsSheetState();
}

class _InboxConnectionsSheetState extends State<InboxConnectionsSheet> {
  late Future<List<Map<String, dynamic>>> connections;
  int? busy;
  String? status;
  @override
  void initState() {
    super.initState();
    connections = widget.service.connections();
  }

  Future<void> configure(Map<String, dynamic> connection) async {
    Map<String, dynamic> values = {'configure_webhook': true};
    if (connection['network'] == 'wa') {
      final secret = TextEditingController();
      final verify = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(appTr('WhatsApp webhook security')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  appTr(
                    'Use the App Secret from Meta App settings and a private verification token. The existing phone number and access token are reused.',
                  ),
                ),
                TextField(
                  controller: secret,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: appTr('Meta App Secret'),
                  ),
                ),
                TextField(
                  controller: verify,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: appTr('Webhook verification token'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(appTr('Cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (secret.text.trim().isNotEmpty &&
                    verify.text.trim().isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: Text(appTr('Save')),
            ),
          ],
        ),
      );
      values = {
        'app_secret': secret.text.trim(),
        'verify_token': verify.text.trim(),
      };
      secret.dispose();
      verify.dispose();
      if (confirmed != true || !mounted) return;
    }
    setState(() {
      busy = connection['id'] as int;
      status = null;
    });
    try {
      await widget.service.configureConnection(connection['id'] as int, values);
      if (mounted) {
        setState(() {
          status = appTr(
            connection['network'] == 'tg' ? 'Telegram webhook connected.' : 'Saved. Set the callback URL and verification token in Meta, then subscribe to messages.',
          );
          connections = widget.service.connections();
        });
      }
    } catch (error) {
      if (mounted) setState(() => status = error.toString());
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InboxConnectionHelp(openSettings: widget.openSettings),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: connections,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(
                    () => connections = widget.service.connections(),
                  ),
                  child: Text(appTr('Retry')),
                );
              }
              return Column(
                children: [
                  for (final connection
                      in snapshot.data ?? <Map<String, dynamic>>[])
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              '${connection['network'] == 'tg' ? 'Telegram' : 'WhatsApp'} · ${appTr('${connection['status']}')}',
                            ),
                            const SizedBox(height: 8),
                            Text(appTr('Secure webhook callback')),
                            SelectableText(
                              '${connection['webhook_url']}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            FilledButton(
                              onPressed: busy != null
                                  ? null
                                  : () => configure(connection),
                              child: Text(
                                appTr(
                                  busy == connection['id']
                                      ? 'Connecting…'
                                      : (connection['network'] == 'tg'
                                            ? 'Enable secure Telegram webhook'
                                            : 'Configure WhatsApp security'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(appTr(status!), semanticsLabel: appTr(status!)),
            ),
        ],
      ),
    ),
  );
}
