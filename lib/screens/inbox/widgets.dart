import 'package:flutter/material.dart';

import '../../services/app_localizations.dart';

class InboxStateView extends StatelessWidget {
  final bool loading;
  final String? error;
  final String empty;
  final VoidCallback retry;
  final String? actionLabel;
  final VoidCallback? action;
  const InboxStateView({
    super.key,
    this.loading = false,
    this.error,
    required this.empty,
    required this.retry,
    this.actionLabel,
    this.action,
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
            if (error == null && actionLabel != null && action != null)
              TextButton(onPressed: action, child: Text(appTr(actionLabel!))),
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
