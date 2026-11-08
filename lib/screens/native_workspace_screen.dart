import '../services/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/mobile_api.dart';
import '../services/native_workspace_service.dart';
import '../services/social_post_service.dart';
import '../services/workspace_catalog.dart';
import 'native_module_screen.dart' show NativeSchemaScreen;
import 'native_settings_screen.dart';
import 'native_parity_screen.dart';
import 'server_screen.dart' show RetryPanel;
import 'workspace_screen.dart' show openModule, workspaceIcon;

class WorkspaceEmptyState extends StatelessWidget {
  final IconData icon;
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const WorkspaceEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .12),
              child: Icon(
                icon,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              appTr(title),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(
              appTr(message),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAction,
                child: Text(appTr(actionLabel!)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class NativeWorkspaceScreen extends StatefulWidget {
  final Map<String, dynamic> module;
  final MobileApi api;
  const NativeWorkspaceScreen({
    super.key,
    required this.module,
    required this.api,
  });
  @override
  State<NativeWorkspaceScreen> createState() => _NativeWorkspaceScreenState();
}

class _NativeWorkspaceScreenState extends State<NativeWorkspaceScreen> {
  late final _service = NativeWorkspaceService(
    widget.api,
    '${widget.module['id']}',
  );
  Map<String, dynamic>? _workspace;
  final _search = TextEditingController();
  List<Map> _records = [];
  String? _error, _currency;
  String _status = 'all';
  DateTime? _day;
  bool _loading = false;
  int _generation = 0;
  Timer? _debounce;
  final _deleteRequests = <int, String>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _service.load(
        query: _search.text,
        status: _status,
        currency: _currency,
        day: _day,
        page: more ? (_workspace?['current_page'] as int? ?? 1) + 1 : 1,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _workspace = data;
        _records = more
            ? [..._records, ...(data['data'] as List? ?? []).whereType<Map>()]
            : (data['data'] as List? ?? []).whereType<Map>().toList();
        _currency = data['currency'] as String?;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _edit(String kind, [Map? record]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return WorkspaceRecordEditor(
            service: _service,
            kind: kind,
            record: record,
            lookups: _workspace,
          );
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(String kind, Map record) async {
    final id = int.tryParse('${record['id']}');
    if (id == null) return;
    final name = record['name'] ??
        record['title'] ??
        record['number'] ??
        record['reference'] ??
        record['invoice_number'] ??
        'record #$id';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppLocalizations.watch(context);
        return AlertDialog(
          title: Text(appTr("Delete :value?", {"value": '$name'})),
          content: Text(appTr('This removes the record from your workspace.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(appTr('Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(appTr('Delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      await _service.delete(
        kind: kind,
        id: id,
        requestId: _deleteRequests.putIfAbsent(id, SocialPostService.requestId),
      );
      _deleteRequests.remove(id);
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(dynamic value, String? currency) {
    final amount = num.tryParse('$value') ?? 0;
    return NumberFormat.simpleCurrency(name: currency ?? 'USD').format(amount);
  }

  String _date(dynamic value, {bool time = false}) {
    final date = DateTime.tryParse('$value');
    return date == null
        ? appTr('Not scheduled')
        : (time ? DateFormat.yMMMd().add_jm() : DateFormat.yMMMd()).format(
            date.toLocal(),
          );
  }

  Widget _badge(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(value, style: Theme.of(context).textTheme.labelMedium),
  );
  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 12),
    child: Text(appTr(title), style: Theme.of(context).textTheme.titleLarge),
  );

  Widget _metrics(List items) => LayoutBuilder(
    builder: (context, constraints) {
      AppLocalizations.watch(context);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final metric in items.whereType<Map>())
            SizedBox(
              width: (constraints.maxWidth - 12) / 2,
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(switch (metric['icon']) {
                        'paid' => Icons.check_circle_outline,
                        'overdue' => Icons.schedule,
                        'balance' => Icons.account_balance_wallet_outlined,
                        _ => Icons.receipt_long_outlined,
                      }, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 14),
                      Text(
                        appTr((metric['label'] ?? metric['title'] ?? '').toString()),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          metric['currency'] != null
                              ? _money(
                                  metric['value'],
                                  metric['currency'] as String?,
                                )
                              : '${metric['value'] ?? 0}',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );

  Widget _invoice(Map record) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          AppLocalizations.watch(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${record['number']}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    _badge('${record['status']}'),
                  ],
                ),
                const SizedBox(height: 16),
                if ('${record['customer'] ?? ''}'.isNotEmpty)
                  Text(
                    '${record['customer']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const SizedBox(height: 16),
                Text(
                  appTr("Total: :value", {
                    "value": _money(
                      record['total'],
                      record['currency'] as String?,
                    ),
                  }),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  appTr("Balance due: :value", {
                    "value": _money(
                      record['balance'],
                      record['currency'] as String?,
                    ),
                  }),
                  style: TextStyle(
                    color: ((num.tryParse('${record['balance']}') ?? 0) > 0)
                        ? Colors.red.shade700
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  appTr("Issued :value", {
                    "value": _date(record['issue_date']),
                  }),
                ),
                if (record['due_date'] != null)
                  Text(
                    appTr("Due :value", {"value": _date(record['due_date'])}),
                  ),
                if ('${record['notes'] ?? ''}'.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('${record['notes']}'),
                ],
                const SizedBox(height: 24),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _edit('payment', {
                          'sales_invoice_id': record['id'],
                          'amount': record['balance'] ?? record['total'],
                          'currency': record['currency'],
                          'crm_company_id': record['crm_company_id'],
                          'crm_contact_id': record['crm_contact_id'],
                        });
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: Text(appTr('Record payment')),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _edit('invoice', record);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(appTr('Edit invoice')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        _delete('invoice', record);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(appTr('Delete')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${record['number']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                _badge('${record['status']}'),
                PopupMenuButton<String>(
                  enabled: !_loading,
                  onSelected: (action) {
                    if (action == 'pay') {
                      _edit('payment', {
                        'sales_invoice_id': record['id'],
                        'amount': record['balance'] ?? record['total'],
                        'currency': record['currency'],
                        'crm_company_id': record['crm_company_id'],
                        'crm_contact_id': record['crm_contact_id'],
                      });
                    } else if (action == 'edit') {
                      _edit('invoice', record);
                    } else if (action == 'delete') {
                      _delete('invoice', record);
                    }
                  },
                  itemBuilder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return [
                      PopupMenuItem(
                        value: 'pay',
                        child: Text(appTr('Record payment')),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(appTr('Edit invoice')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(appTr('Delete invoice')),
                      ),
                    ];
                  },
                ),
              ],
            ),
            if ('${record['customer'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${record['customer']}'),
            ],
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _money(record['total'], record['currency'] as String?),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                if ((num.tryParse('${record['balance']}') ?? 0) > 0)
                  Text(
                    appTr("Due: :value", {
                      "value": _money(
                        record['balance'],
                        record['currency'] as String?,
                      ),
                    }),
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
            if (record['due_date'] != null) ...[
              const SizedBox(height: 8),
              Text(
                appTr("Due :value", {"value": _date(record['due_date'])}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );

  Widget _payment(Map record) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          AppLocalizations.watch(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _money(record['amount'], record['currency'] as String?),
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                    _badge('${record['status'] ?? 'completed'}'),
                  ],
                ),
                const SizedBox(height: 16),
                if (record['payment_date'] != null)
                  Text(appTr("Date: :value", {"value": _date(record['payment_date'])})),
                if (record['payment_method'] != null)
                  Text(appTr("Method: :value", {"value": '${record['payment_method']}'.replaceAll('_', ' ').toUpperCase()})),
                if (record['invoice_number'] != null && '${record['invoice_number']}'.isNotEmpty)
                  Text(appTr("Invoice: :value", {"value": '${record['invoice_number']}'})),
                if (record['customer'] != null && '${record['customer']}'.isNotEmpty)
                  Text(appTr("Customer: :value", {"value": '${record['customer']}'})),
                if (record['reference'] != null && '${record['reference']}'.isNotEmpty)
                  Text(appTr("Reference: :value", {"value": '${record['reference']}'})),
                if (record['notes'] != null && '${record['notes']}'.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('${record['notes']}'),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _edit('payment', record);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(appTr('Edit payment')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        _delete('payment', record);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(appTr('Delete')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Colors.green.withValues(alpha: 0.12),
                  child: const Icon(Icons.payments_outlined, color: Colors.green),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _money(record['amount'], record['currency'] as String?),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      if (record['invoice_number'] != null && '${record['invoice_number']}'.isNotEmpty)
                        Text(
                          appTr("Invoice: :value", {"value": '${record['invoice_number']}'}),
                          style: Theme.of(context).textTheme.bodySmall,
                        )
                      else if (record['customer'] != null && '${record['customer']}'.isNotEmpty)
                        Text(
                          '${record['customer']}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                _badge('${record['status'] ?? 'completed'}'),
                PopupMenuButton<String>(
                  enabled: !_loading,
                  onSelected: (action) => action == 'edit'
                      ? _edit('payment', record)
                      : _delete('payment', record),
                  itemBuilder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(appTr('Edit payment')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(appTr('Delete payment')),
                      ),
                    ];
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (record['payment_date'] != null)
                  Text(
                    _date(record['payment_date']),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (record['payment_method'] != null)
                  Text(
                    '${record['payment_method']}'.replaceAll('_', ' ').toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _proposal(Map record) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          AppLocalizations.watch(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${record['title'] ?? record['number']}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    _badge('${record['status'] ?? 'draft'}'),
                  ],
                ),
                if (record['number'] != null) ...[
                  const SizedBox(height: 6),
                  Text('${record['number']}', style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                if (record['customer'] != null && '${record['customer']}'.isNotEmpty)
                  Text(
                    '${record['customer']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const SizedBox(height: 12),
                Text(
                  appTr("Total: :value", {
                    "value": _money(record['total'], record['currency'] as String?),
                  }),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (record['issue_date'] != null)
                  Text(appTr("Issued: :value", {"value": _date(record['issue_date'])})),
                if (record['valid_until'] != null)
                  Text(appTr("Valid until: :value", {"value": _date(record['valid_until'])})),
                if (record['notes'] != null && '${record['notes']}'.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('${record['notes']}'),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _edit('proposal', record);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(appTr('Edit proposal')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        _delete('proposal', record);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(appTr('Delete')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record['title'] ?? record['number']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (record['number'] != null) ...[
                        const SizedBox(height: 4),
                        Text('${record['number']}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _badge('${record['status'] ?? 'draft'}'),
                PopupMenuButton<String>(
                  enabled: !_loading,
                  onSelected: (action) => action == 'edit'
                      ? _edit('proposal', record)
                      : _delete('proposal', record),
                  itemBuilder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(appTr('Edit proposal')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(appTr('Delete proposal')),
                      ),
                    ];
                  },
                ),
              ],
            ),
            if (record['customer'] != null && '${record['customer']}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${record['customer']}'),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _money(record['total'], record['currency'] as String?),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (record['valid_until'] != null)
                  Text(
                    appTr("Until :value", {"value": _date(record['valid_until'])}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _estimate(Map record) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          AppLocalizations.watch(context);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${record['title'] ?? record['number']}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    _badge('${record['status'] ?? 'draft'}'),
                  ],
                ),
                if (record['number'] != null) ...[
                  const SizedBox(height: 6),
                  Text('${record['number']}', style: Theme.of(context).textTheme.bodySmall),
                ],
                const SizedBox(height: 16),
                if (record['customer'] != null && '${record['customer']}'.isNotEmpty)
                  Text(
                    '${record['customer']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                const SizedBox(height: 12),
                Text(
                  appTr("Total: :value", {
                    "value": _money(record['total'], record['currency'] as String?),
                  }),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (record['issue_date'] != null)
                  Text(appTr("Issued: :value", {"value": _date(record['issue_date'])})),
                if (record['valid_until'] != null)
                  Text(appTr("Valid until: :value", {"value": _date(record['valid_until'])})),
                if (record['notes'] != null && '${record['notes']}'.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('${record['notes']}'),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _edit('estimate', record);
                      },
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: Text(appTr('Edit estimate')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        _delete('estimate', record);
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(appTr('Delete')),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${record['title'] ?? record['number']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (record['number'] != null) ...[
                        const SizedBox(height: 4),
                        Text('${record['number']}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _badge('${record['status'] ?? 'draft'}'),
                PopupMenuButton<String>(
                  enabled: !_loading,
                  onSelected: (action) => action == 'edit'
                      ? _edit('estimate', record)
                      : _delete('estimate', record),
                  itemBuilder: (localizationContext) {
                    AppLocalizations.watch(localizationContext);
                    return [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(appTr('Edit estimate')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(appTr('Delete estimate')),
                      ),
                    ];
                  },
                ),
              ],
            ),
            if (record['customer'] != null && '${record['customer']}'.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${record['customer']}'),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _money(record['total'], record['currency'] as String?),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (record['valid_until'] != null)
                  Text(
                    appTr("Until :value", {"value": _date(record['valid_until'])}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _company(Map record) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(child: Icon(Icons.business_outlined)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${record['name']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if ('${record['industry'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        '${record['industry']}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_loading,
                onSelected: (action) => action == 'edit'
                    ? _edit('company', record)
                    : _delete('company', record),
                itemBuilder: (localizationContext) {
                  AppLocalizations.watch(localizationContext);
                  return [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(appTr('Edit company')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(appTr('Delete company')),
                    ),
                  ];
                },
              ),
            ],
          ),
          if ([
            record['address'],
            record['city'],
            record['state'],
            record['country'],
          ].any((value) => value != null && '$value'.trim().isNotEmpty)) ...[
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [
                          record['address'],
                          record['city'],
                          record['state'],
                          record['country'],
                        ]
                        .where(
                          (value) =>
                              value != null && '$value'.trim().isNotEmpty,
                        )
                        .join(', '),
                  ),
                ),
              ],
            ),
          ],
          if ('${record['email'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('${record['email']}'),
          ],
        ],
      ),
    ),
  );

  Widget _campaign(Map record) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(child: Icon(Icons.campaign_outlined)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record['name']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _badge('${record['target_audience']}'),
              ],
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: appTr('Delete campaign'),
            onPressed: _loading ? null : () => _delete('campaign', record),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );

  Widget _agenda(Map post) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.article_outlined),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${post['title']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (post['agent'] != null) Text('${post['agent']}'),
                const SizedBox(height: 8),
                Text(
                  _date(
                    post['published_at'] ?? post['scheduled_at'],
                    time: true,
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                _badge('${post['status']}'),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _photo(Map record) {
    final image = Uri.tryParse('${record['image_url'] ?? ''}');
    final url = image == null ? null : widget.api.origin.resolveUri(image);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (url != null &&
              url.scheme == 'https' &&
              url.userInfo.isEmpty &&
              url.path.isNotEmpty)
            Image.network(
              '$url',
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (localizationContext, error, stack) {
                AppLocalizations.watch(localizationContext);
                return const SizedBox(
                  height: 120,
                  child: Icon(Icons.image_outlined, size: 36),
                );
              },
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record['title']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                _badge('${record['status']}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _tools(List<Map> tools) => [
    for (final tool in tools)
      Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openModule(
            context,
            Map<String, dynamic>.from(tool),
            api: widget.api,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .12),
                  child: Icon(
                    workspaceIcon('${tool['id']} ${tool['title']}'),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    appTr(toolDisplayName(tool)),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  tool['available'] == true
                      ? Icons.chevron_right
                      : Icons.lock_outline,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_workspace == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : RetryPanel(message: appTr(_error!), retry: _load),
      );
    }
    final kind = '${_workspace!['kind']}';
    if (kind == 'fashion_settings') {
      return NativeParityScreen(
        module: {...widget.module, 'route_type': kind},
        api: widget.api,
      );
    }
    if (kind == 'form' || kind == 'overview') {
      return NativeSchemaScreen(module: widget.module, api: widget.api);
    }
    if (kind == 'settings') return NativeSettingsScreen(api: widget.api);
    final tools = (_workspace!['modules'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final isBlog = kind == 'blog';
    final isCalendar = isBlog && _workspace!['calendar'] == true;
    final summary = switch (kind) {
      'invoices' =>
        'Stay on top of invoices, payments and outstanding balances.',
      'payments' =>
        'Track incoming transactions, payment methods and receipts.',
      'proposals' =>
        'Create and track client proposals from pitch to agreement.',
      'estimates' =>
        'Send project cost estimates and quotes to prospective clients.',
      'companies' => 'Keep your business relationships in one place.',
      'campaigns' => 'Shape your message around the right audience.',
      'blog' => 'Plan your articles and see what’s coming next.',
      'photoshoot' => 'Create product images and explore your recent work.',
      _ =>
        'Discover the tools in ${widget.module['category'] ?? 'your workspace'}.',
    };
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appTr(toolDisplayName(widget.module)),
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            summary,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (const [
                      'invoices',
                      'payments',
                      'proposals',
                      'estimates',
                    ].contains(kind)) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _edit(switch (kind) {
                                'invoices' => 'invoice',
                                'payments' => 'payment',
                                'proposals' => 'proposal',
                                'estimates' => 'estimate',
                                _ => kind,
                              }),
                        icon: const Icon(Icons.add),
                        label: Text(
                          appTr(switch (kind) {
                            'invoices' => 'Create invoice',
                            'payments' => 'Record payment',
                            'proposals' => 'Create proposal',
                            'estimates' => 'Create estimate',
                            _ => 'Add record',
                          }),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(appTr(_error!)),
                          TextButton(
                            onPressed: _loading ? null : _load,
                            child: Text(appTr('Retry')),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (kind == 'invoices') ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 20),
                  if ((_workspace!['currencies'] as List? ?? []).length > 1)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(_currency),
                      initialValue: _currency,
                      decoration: InputDecoration(labelText: appTr('Currency')),
                      items: [
                        for (final currency
                            in _workspace!['currencies'] as List)
                          DropdownMenuItem(
                            value: '$currency',
                            child: Text('$currency'),
                          ),
                      ],
                      onChanged: _loading
                          ? null
                          : (currency) {
                              setState(() => _currency = currency);
                              _load();
                            },
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final status in const {
                        'all': 'All invoices',
                        'draft': 'Draft',
                        'sent': 'Sent',
                        'paid': 'Paid',
                        'overdue': 'Overdue',
                      }.entries)
                        ChoiceChip(
                          label: Text(appTr(status.value)),
                          selected: _status == status.key,
                          onSelected: (_) {
                            setState(() => _status = status.key);
                            _load();
                          },
                        ),
                    ],
                  ),
                ],
                if (kind == 'payments') ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final status in const {
                        'all': 'All payments',
                        'completed': 'Completed',
                        'pending': 'Pending',
                        'refunded': 'Refunded',
                        'failed': 'Failed',
                      }.entries)
                        ChoiceChip(
                          label: Text(appTr(status.value)),
                          selected: _status == status.key,
                          onSelected: (_) {
                            setState(() => _status = status.key);
                            _load();
                          },
                        ),
                    ],
                  ),
                ],
                if (kind == 'proposals') ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final status in const {
                        'all': 'All proposals',
                        'draft': 'Draft',
                        'sent': 'Sent',
                        'accepted': 'Accepted',
                        'rejected': 'Rejected',
                        'expired': 'Expired',
                      }.entries)
                        ChoiceChip(
                          label: Text(appTr(status.value)),
                          selected: _status == status.key,
                          onSelected: (_) {
                            setState(() => _status = status.key);
                            _load();
                          },
                        ),
                    ],
                  ),
                ],
                if (kind == 'estimates') ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final status in const {
                        'all': 'All estimates',
                        'draft': 'Draft',
                        'sent': 'Sent',
                        'accepted': 'Accepted',
                        'rejected': 'Rejected',
                        'expired': 'Expired',
                      }.entries)
                        ChoiceChip(
                          label: Text(appTr(status.value)),
                          selected: _status == status.key,
                          onSelected: (_) {
                            setState(() => _status = status.key);
                            _load();
                          },
                        ),
                    ],
                  ),
                ],
                if (const [
                  'invoices',
                  'payments',
                  'proposals',
                  'estimates',
                  'companies',
                  'campaigns',
                ].contains(kind)) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: appTr("Search :kind", {"kind": kind}),
                      prefixIcon: const Icon(Icons.search),
                    ),
                    onChanged: (_) {
                      _debounce?.cancel();
                      _debounce = Timer(
                        const Duration(milliseconds: 300),
                        _load,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                if (kind == 'companies' || kind == 'campaigns')
                  FilledButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _edit(
                            kind == 'companies' ? 'company' : 'campaign',
                          ),
                    icon: const Icon(Icons.add),
                    label: Text(
                      appTr(
                        kind == 'companies' ? 'New company' : 'New campaign',
                      ),
                    ),
                  ),
                ],
                if (kind == 'photoshoot') ...[
                  _section('Create a photoshoot'),
                  ..._tools(
                    tools
                        .where(
                          (tool) => tool['route_type'] == 'extension_workflow',
                        )
                        .toList(),
                  ),
                  _section('Your gallery'),
                ],
                if (isCalendar) ...[
                  CalendarDatePicker(
                    initialDate: _day ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    onDateChanged: (day) {
                      setState(() => _day = day);
                      _load();
                    },
                  ),
                  if (_day != null)
                    TextButton(
                      onPressed: () {
                        setState(() => _day = null);
                        _load();
                      },
                      child: Text(appTr('Show all dates')),
                    ),
                  _section(_day == null ? 'Publishing agenda' : _date(_day)),
                ],
                if (isBlog && _workspace!['show_agents'] == true) ...[
                  _section('Your agents'),
                  if ((_workspace!['agents'] as List? ?? []).isEmpty)
                    WorkspaceEmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: appTr('Your publishing workspace'),
                      message: appTr(
                        'Your agents and their publishing schedules will appear here.',
                      ),
                    ),
                  for (final agent
                      in (_workspace!['agents'] as List? ?? [])
                          .whereType<Map>())
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${agent['name']}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            _badge(
                              agent['is_active'] == true ? 'Active' : 'Paused',
                            ),
                            if ((agent['schedule_days'] as List? ?? [])
                                .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Text(
                                (agent['schedule_days'] as List).join(' · '),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  _section('Recent articles'),
                ],
                if (const [
                      'invoices',
                      'payments',
                      'proposals',
                      'estimates',
                      'companies',
                      'campaigns',
                      'photoshoot',
                      'blog',
                    ].contains(kind) &&
                    _records.isEmpty)
                  WorkspaceEmptyState(
                    icon: switch (kind) {
                      'invoices' => Icons.receipt_long_outlined,
                      'payments' => Icons.payments_outlined,
                      'proposals' => Icons.description_outlined,
                      'estimates' => Icons.request_quote_outlined,
                      'companies' => Icons.business_outlined,
                      'campaigns' => Icons.campaign_outlined,
                      'photoshoot' => Icons.camera_alt_outlined,
                      _ => Icons.event_note_outlined,
                    },
                    title: appTr(
                      _search.text.isNotEmpty
                          ? 'No matching results'
                          : switch (kind) {
                              'invoices' => 'No invoices yet',
                              'payments' => 'No payments yet',
                              'proposals' => 'No proposals yet',
                              'estimates' => 'No estimates yet',
                              'companies' => 'No companies yet',
                              'campaigns' => 'No campaigns yet',
                              'photoshoot' => 'No photoshoots yet',
                              _ => 'A clear calendar, a fresh start',
                            },
                    ),
                    message: appTr(
                      _search.text.isNotEmpty
                          ? 'Try another search or clear your filters.'
                          : switch (kind) {
                              'invoices' =>
                                'Your invoices will appear here, with their totals, due dates and payment status.',
                              'payments' =>
                                'Record payments and see your transaction history here.',
                              'proposals' =>
                                'Create client proposals and track them through acceptance.',
                              'estimates' =>
                                'Draft cost estimates and quotes for prospective clients.',
                              'companies' =>
                                'Add your first company to start building your network.',
                              'campaigns' =>
                                'Create a campaign to bring your audience and message together.',
                              'photoshoot' =>
                                'Create a photoshoot to see your images here.',
                              _ =>
                                'Your planned articles will appear in the agenda. Select a day to explore your publishing schedule.',
                            },
                    ),
                    actionLabel: kind == 'photoshoot'
                        ? appTr('Create photoshoot')
                        : null,
                    onAction:
                        kind == 'photoshoot' &&
                            tools.any(
                              (tool) =>
                                  tool['route_type'] == 'extension_workflow' &&
                                  tool['available'] == true,
                            )
                        ? () => openModule(
                            context,
                            Map<String, dynamic>.from(
                              tools.firstWhere(
                                (tool) =>
                                    tool['route_type'] ==
                                        'extension_workflow' &&
                                    tool['available'] == true,
                              ),
                            ),
                            api: widget.api,
                          )
                        : null,
                  ),
                for (final record in _records)
                  switch (kind) {
                    'invoices' => _invoice(record),
                    'payments' => _payment(record),
                    'proposals' => _proposal(record),
                    'estimates' => _estimate(record),
                    'companies' => _company(record),
                    'campaigns' => _campaign(record),
                    'blog' => _agenda(record),
                    'photoshoot' => _photo(record),
                    _ => const SizedBox.shrink(),
                  },
                if ((_workspace!['current_page'] as int? ?? 1) <
                    (_workspace!['last_page'] as int? ?? 1))
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton(
                      onPressed: _loading ? null : () => _load(more: true),
                      child: Text(appTr('Load more')),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class WorkspaceRecordEditor extends StatefulWidget {
  final NativeWorkspaceService service;
  final String kind;
  final Map? record;
  final Map? lookups;
  const WorkspaceRecordEditor({
    super.key,
    required this.service,
    required this.kind,
    this.record,
    this.lookups,
  });
  @override
  State<WorkspaceRecordEditor> createState() => _WorkspaceRecordEditorState();
}

class _WorkspaceRecordEditorState extends State<WorkspaceRecordEditor> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  final _selectedValues = <String, dynamic>{};
  final _dateValues = <String, DateTime?>{};
  String? _error;
  bool _saving = false;
  String _requestId = SocialPostService.requestId();

  Map<String, String> get _legacyFields => widget.kind == 'campaign'
      ? {'name': 'Campaign name', 'target_audience': 'Target audience'}
      : {
          'name': 'Company name',
          'industry': 'Industry',
          'website': 'Website',
          'email': 'Email',
          'phone': 'Phone',
          'address': 'Address',
          'city': 'City',
          'state': 'State / region',
          'country': 'Country',
          'notes': 'Notes',
        };

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final r = widget.record;
    final l = widget.lookups;
    switch (widget.kind) {
      case 'campaign':
        _controllers['name'] =
            TextEditingController(text: '${r?['name'] ?? ''}');
        _controllers['target_audience'] =
            TextEditingController(text: '${r?['target_audience'] ?? ''}');
        break;
      case 'company':
        for (final k in [
          'name',
          'industry',
          'website',
          'email',
          'phone',
          'address',
          'city',
          'state',
          'country',
          'notes',
        ]) {
          _controllers[k] = TextEditingController(text: '${r?[k] ?? ''}');
        }
        break;
      case 'invoice':
        _controllers['invoice_number'] = TextEditingController(
          text: '${r?['number'] ?? r?['invoice_number'] ?? ''}',
        );
        _controllers['total'] = TextEditingController(
          text: r?['total'] != null ? '${r!['total']}' : '',
        );
        _controllers['notes'] =
            TextEditingController(text: '${r?['notes'] ?? ''}');
        _selectedValues['currency'] =
            r?['currency'] ?? l?['currency'] ?? 'USD';
        _selectedValues['status'] = r?['status'] ?? 'draft';
        _selectedValues['crm_company_id'] =
            int.tryParse('${r?['crm_company_id'] ?? ''}');
        _selectedValues['crm_contact_id'] =
            int.tryParse('${r?['crm_contact_id'] ?? ''}');
        _selectedValues['crm_deal_id'] =
            int.tryParse('${r?['crm_deal_id'] ?? ''}');
        _dateValues['issue_date'] = r?['issue_date'] != null
            ? DateTime.tryParse('${r!['issue_date']}')
            : DateTime.now();
        _dateValues['due_date'] = r?['due_date'] != null
            ? DateTime.tryParse('${r!['due_date']}')
            : DateTime.now().add(const Duration(days: 30));
        break;
      case 'payment':
        _controllers['amount'] = TextEditingController(
          text: r?['amount'] != null ? '${r!['amount']}' : '',
        );
        _controllers['reference'] =
            TextEditingController(text: '${r?['reference'] ?? ''}');
        _controllers['notes'] =
            TextEditingController(text: '${r?['notes'] ?? ''}');
        _selectedValues['sales_invoice_id'] =
            int.tryParse('${r?['sales_invoice_id'] ?? ''}');
        _selectedValues['currency'] =
            r?['currency'] ?? l?['currency'] ?? 'USD';
        _selectedValues['status'] = r?['status'] ?? 'completed';
        _selectedValues['payment_method'] =
            r?['payment_method'] ?? 'bank_transfer';
        _selectedValues['crm_company_id'] =
            int.tryParse('${r?['crm_company_id'] ?? ''}');
        _selectedValues['crm_contact_id'] =
            int.tryParse('${r?['crm_contact_id'] ?? ''}');
        _dateValues['payment_date'] = r?['payment_date'] != null
            ? DateTime.tryParse('${r!['payment_date']}')
            : DateTime.now();
        break;
      case 'proposal':
        _controllers['title'] =
            TextEditingController(text: '${r?['title'] ?? ''}');
        _controllers['proposal_number'] = TextEditingController(
          text: '${r?['number'] ?? r?['proposal_number'] ?? ''}',
        );
        _controllers['total'] = TextEditingController(
          text: r?['total'] != null ? '${r!['total']}' : '',
        );
        _controllers['notes'] =
            TextEditingController(text: '${r?['notes'] ?? ''}');
        _selectedValues['currency'] =
            r?['currency'] ?? l?['currency'] ?? 'USD';
        _selectedValues['status'] = r?['status'] ?? 'draft';
        _selectedValues['crm_company_id'] =
            int.tryParse('${r?['crm_company_id'] ?? ''}');
        _selectedValues['crm_contact_id'] =
            int.tryParse('${r?['crm_contact_id'] ?? ''}');
        _selectedValues['crm_deal_id'] =
            int.tryParse('${r?['crm_deal_id'] ?? ''}');
        _dateValues['issue_date'] = r?['issue_date'] != null
            ? DateTime.tryParse('${r!['issue_date']}')
            : DateTime.now();
        _dateValues['valid_until'] = r?['valid_until'] != null
            ? DateTime.tryParse('${r!['valid_until']}')
            : DateTime.now().add(const Duration(days: 30));
        break;
      case 'estimate':
        _controllers['title'] =
            TextEditingController(text: '${r?['title'] ?? ''}');
        _controllers['estimate_number'] = TextEditingController(
          text: '${r?['number'] ?? r?['estimate_number'] ?? ''}',
        );
        _controllers['total'] = TextEditingController(
          text: r?['total'] != null ? '${r!['total']}' : '',
        );
        _controllers['notes'] =
            TextEditingController(text: '${r?['notes'] ?? ''}');
        _selectedValues['currency'] =
            r?['currency'] ?? l?['currency'] ?? 'USD';
        _selectedValues['status'] = r?['status'] ?? 'draft';
        _selectedValues['crm_company_id'] =
            int.tryParse('${r?['crm_company_id'] ?? ''}');
        _selectedValues['crm_contact_id'] =
            int.tryParse('${r?['crm_contact_id'] ?? ''}');
        _dateValues['issue_date'] = r?['issue_date'] != null
            ? DateTime.tryParse('${r!['issue_date']}')
            : DateTime.now();
        _dateValues['valid_until'] = r?['valid_until'] != null
            ? DateTime.tryParse('${r!['valid_until']}')
            : DateTime.now().add(const Duration(days: 30));
        break;
      default:
        _controllers['name'] =
            TextEditingController(text: '${r?['name'] ?? ''}');
        break;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> get _currencies {
    final raw = widget.lookups?['currencies'] as List? ??
        ['USD', 'EUR', 'GBP', 'TRY'];
    return raw.map((e) => '$e').toSet().toList();
  }

  List<DropdownMenuItem<int>> _optionsList(dynamic source) {
    final list = (source as List? ?? []).whereType<Map>().toList();
    return [
      for (final item in list)
        if (int.tryParse('${item['id']}') != null)
          DropdownMenuItem<int>(
            value: int.parse('${item['id']}'),
            child: Text(
              '${item['name'] ?? item['title'] ?? item['number'] ?? item['id']}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
    ];
  }

  Widget _textInput(
    String key,
    String label, {
    String? hint,
    bool required = false,
    int minLines = 1,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final controller =
        _controllers.putIfAbsent(key, () => TextEditingController());
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: TextFormField(
        controller: controller,
        enabled: !_saving,
        minLines: minLines,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: appTr(label),
          hintText: hint != null ? appTr(hint) : null,
        ),
        onChanged: (_) => _requestId = SocialPostService.requestId(),
        validator: (value) {
          final text = value?.trim() ?? '';
          if (required && text.isEmpty) {
            return appTr("Enter :field.", {"field": label.toLowerCase()});
          }
          if (required &&
              keyboardType ==
                  const TextInputType.numberWithOptions(decimal: true) &&
              num.tryParse(text) == null) {
            return appTr('Enter a valid number.');
          }
          return null;
        },
      ),
    );
  }

  Widget _dropdownField<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    bool allowClear = false,
  }) {
    var dropdownItems = [
      if (allowClear)
        DropdownMenuItem<T>(
          value: null,
          child: Text(
            appTr('None / Select…'),
            style: TextStyle(color: Theme.of(context).disabledColor),
          ),
        ),
      ...items,
    ];
    if (value != null && !dropdownItems.any((item) => item.value == value)) {
      dropdownItems = [
        DropdownMenuItem<T>(value: value, child: Text('#$value')),
        ...dropdownItems,
      ];
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: DropdownButtonFormField<T>(
        isExpanded: true,
        value: value,
        items: dropdownItems,
        decoration: InputDecoration(labelText: appTr(label)),
        onChanged: _saving
            ? null
            : (val) {
                _requestId = SocialPostService.requestId();
                onChanged(val);
              },
      ),
    );
  }

  Widget _datePickerField(String key, String label) {
    final date = _dateValues[key];
    final text = date == null
        ? appTr('Select date')
        : DateFormat.yMMMd().format(date);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: InkWell(
        onTap: _saving
            ? null
            : () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? now,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() {
                    _dateValues[key] = picked;
                    _requestId = SocialPostService.requestId();
                  });
                }
              },
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: appTr(label),
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(text),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final inputs = <String, dynamic>{
        for (final entry in _controllers.entries)
          entry.key: entry.value.text.trim(),
        for (final entry in _selectedValues.entries)
          if (entry.value != null) entry.key: entry.value,
        for (final entry in _dateValues.entries)
          if (entry.value != null)
            entry.key: DateFormat('yyyy-MM-dd').format(entry.value!),
      };
      await widget.service.save(
        kind: widget.kind,
        requestId: _requestId,
        id: int.tryParse('${widget.record?['id']}'),
        inputs: inputs,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final isSales = const [
      'invoice',
      'payment',
      'proposal',
      'estimate',
    ].contains(widget.kind);
    final title = switch (widget.kind) {
      'invoice' =>
        widget.record == null ? 'Create invoice' : 'Edit invoice',
      'payment' =>
        widget.record == null ? 'Record payment' : 'Edit payment',
      'proposal' =>
        widget.record == null ? 'Create proposal' : 'Edit proposal',
      'estimate' =>
        widget.record == null ? 'Create estimate' : 'Edit estimate',
      'company' =>
        widget.record == null ? 'New company' : 'Edit company',
      'campaign' =>
        widget.record == null ? 'New campaign' : 'Edit campaign',
      _ => '${widget.record == null ? 'New' : 'Edit'} ${widget.kind}',
    };
    final buttonLabel = switch (widget.kind) {
      'payment' => _saving
          ? 'Recording…'
          : (widget.record == null ? 'Record payment' : 'Save payment'),
      'invoice' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create invoice' : 'Save invoice'),
      'proposal' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create proposal' : 'Save proposal'),
      'estimate' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create estimate' : 'Save estimate'),
      'company' => _saving ? 'Saving…' : 'Save company',
      'campaign' => _saving ? 'Saving…' : 'Save campaign',
      _ => _saving ? 'Saving…' : 'Save',
    };

    final invoicesList = <Map>[
      ...((widget.lookups?['invoices'] ?? widget.lookups?['invoicesList'])
                  as List? ??
              [])
          .whereType<Map>(),
      if (widget.lookups?['kind'] == 'invoices' &&
          widget.lookups?['data'] is List)
        for (final inv
            in (widget.lookups!['data'] as List).whereType<Map>())
          {
            'id': inv['id'],
            'name':
                '${inv['number']} (${inv['currency'] ?? 'USD'} ${inv['total']})',
          },
    ];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(appTr(title))),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            children: [
              if (!isSales)
                for (final entry in _legacyFields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: TextFormField(
                      controller: _controllers[entry.key],
                      enabled: !_saving,
                      minLines: entry.key == 'target_audience' ||
                              entry.key == 'notes'
                          ? 3
                          : 1,
                      maxLines: entry.key == 'target_audience' ||
                              entry.key == 'notes'
                          ? 5
                          : 1,
                      keyboardType: entry.key == 'email'
                          ? TextInputType.emailAddress
                          : entry.key == 'phone'
                              ? TextInputType.phone
                              : entry.key == 'website'
                                  ? TextInputType.url
                                  : TextInputType.text,
                      decoration: InputDecoration(labelText: entry.value),
                      onChanged: (_) =>
                          _requestId = SocialPostService.requestId(),
                      validator: (value) {
                        final text = value?.trim() ?? '';
                        if ([
                              appTr('name'),
                              appTr('target_audience'),
                            ].contains(entry.key) &&
                            text.isEmpty) {
                          return 'Enter ${entry.value.toLowerCase()}.';
                        }
                        if (entry.key == appTr('email') &&
                            text.isNotEmpty &&
                            !text.contains('@')) {
                          return appTr('Enter a valid email.');
                        }
                        return null;
                      },
                    ),
                  ),
              if (widget.kind == 'invoice') ...[
                _textInput(
                  'invoice_number',
                  'Invoice number',
                  hint: 'INV-xxxxx (auto-generated if empty)',
                ),
                _textInput(
                  'total',
                  'Total amount',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  required: true,
                ),
                _dropdownField<String>(
                  label: 'Currency',
                  value: _selectedValues['currency'],
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['currency'] = v),
                ),
                _dropdownField<int>(
                  label: 'Company',
                  value: _selectedValues['crm_company_id'],
                  items: _optionsList(
                    widget.lookups?['companies'] ??
                        widget.lookups?['companiesList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_company_id'] = v),
                ),
                _dropdownField<int>(
                  label: 'Contact',
                  value: _selectedValues['crm_contact_id'],
                  items: _optionsList(
                    widget.lookups?['contacts'] ??
                        widget.lookups?['contactsList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_contact_id'] = v),
                ),
                _dropdownField<int>(
                  label: 'Deal',
                  value: _selectedValues['crm_deal_id'],
                  items: _optionsList(
                    widget.lookups?['deals'] ??
                        widget.lookups?['dealsList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_deal_id'] = v),
                ),
                _dropdownField<String>(
                  label: 'Status',
                  value: _selectedValues['status'],
                  items: [
                    for (final s in const {
                      'draft': 'Draft',
                      'sent': 'Sent',
                      'paid': 'Paid',
                      'cancelled': 'Cancelled',
                    }.entries)
                      DropdownMenuItem(
                        value: s.key,
                        child: Text(appTr(s.value)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['status'] = v),
                ),
                _datePickerField('issue_date', 'Issue date'),
                _datePickerField('due_date', 'Due date'),
                _textInput('notes', 'Notes', minLines: 2, maxLines: 4),
              ],
              if (widget.kind == 'payment') ...[
                _dropdownField<int>(
                  label: 'Invoice (optional)',
                  value: _selectedValues['sales_invoice_id'],
                  items: _optionsList(invoicesList),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['sales_invoice_id'] = v),
                ),
                _textInput(
                  'amount',
                  'Payment amount',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  required: true,
                ),
                _dropdownField<String>(
                  label: 'Currency',
                  value: _selectedValues['currency'],
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['currency'] = v),
                ),
                _dropdownField<String>(
                  label: 'Payment method',
                  value: _selectedValues['payment_method'],
                  items: [
                    for (final m in const {
                      'bank_transfer': 'Bank Transfer',
                      'credit_card': 'Credit Card',
                      'cash': 'Cash',
                      'paypal': 'PayPal',
                      'stripe': 'Stripe',
                      'other': 'Other',
                    }.entries)
                      DropdownMenuItem(
                        value: m.key,
                        child: Text(appTr(m.value)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['payment_method'] = v),
                ),
                _dropdownField<String>(
                  label: 'Status',
                  value: _selectedValues['status'],
                  items: [
                    for (final s in const {
                      'completed': 'Completed',
                      'pending': 'Pending',
                      'failed': 'Failed',
                      'refunded': 'Refunded',
                    }.entries)
                      DropdownMenuItem(
                        value: s.key,
                        child: Text(appTr(s.value)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['status'] = v),
                ),
                _textInput('reference', 'Transaction / Reference ID'),
                _datePickerField('payment_date', 'Payment date'),
                _dropdownField<int>(
                  label: 'Company',
                  value: _selectedValues['crm_company_id'],
                  items: _optionsList(
                    widget.lookups?['companies'] ??
                        widget.lookups?['companiesList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_company_id'] = v),
                ),
                _dropdownField<int>(
                  label: 'Contact',
                  value: _selectedValues['crm_contact_id'],
                  items: _optionsList(
                    widget.lookups?['contacts'] ??
                        widget.lookups?['contactsList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_contact_id'] = v),
                ),
                _textInput('notes', 'Notes', minLines: 2, maxLines: 4),
              ],
              if (widget.kind == 'proposal') ...[
                _textInput('title', 'Proposal title', required: true),
                _textInput(
                  'proposal_number',
                  'Proposal number',
                  hint: 'PRP-xxxxx (auto-generated if empty)',
                ),
                _textInput(
                  'total',
                  'Total value',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  required: true,
                ),
                _dropdownField<String>(
                  label: 'Currency',
                  value: _selectedValues['currency'],
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['currency'] = v),
                ),
                _dropdownField<int>(
                  label: 'Company',
                  value: _selectedValues['crm_company_id'],
                  items: _optionsList(
                    widget.lookups?['companies'] ??
                        widget.lookups?['companiesList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_company_id'] = v),
                ),
                _dropdownField<int>(
                  label: 'Contact',
                  value: _selectedValues['crm_contact_id'],
                  items: _optionsList(
                    widget.lookups?['contacts'] ??
                        widget.lookups?['contactsList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_contact_id'] = v),
                ),
                _dropdownField<int>(
                  label: 'Deal',
                  value: _selectedValues['crm_deal_id'],
                  items: _optionsList(
                    widget.lookups?['deals'] ??
                        widget.lookups?['dealsList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_deal_id'] = v),
                ),
                _dropdownField<String>(
                  label: 'Status',
                  value: _selectedValues['status'],
                  items: [
                    for (final s in const {
                      'draft': 'Draft',
                      'sent': 'Sent',
                      'accepted': 'Accepted',
                      'rejected': 'Rejected',
                      'expired': 'Expired',
                    }.entries)
                      DropdownMenuItem(
                        value: s.key,
                        child: Text(appTr(s.value)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['status'] = v),
                ),
                _datePickerField('issue_date', 'Issue date'),
                _datePickerField('valid_until', 'Valid until'),
                _textInput('notes', 'Notes', minLines: 2, maxLines: 4),
              ],
              if (widget.kind == 'estimate') ...[
                _textInput('title', 'Estimate title', required: true),
                _textInput(
                  'estimate_number',
                  'Estimate number',
                  hint: 'EST-xxxxx (auto-generated if empty)',
                ),
                _textInput(
                  'total',
                  'Total value',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  required: true,
                ),
                _dropdownField<String>(
                  label: 'Currency',
                  value: _selectedValues['currency'],
                  items: [
                    for (final c in _currencies)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['currency'] = v),
                ),
                _dropdownField<int>(
                  label: 'Company',
                  value: _selectedValues['crm_company_id'],
                  items: _optionsList(
                    widget.lookups?['companies'] ??
                        widget.lookups?['companiesList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_company_id'] = v),
                ),
                _dropdownField<int>(
                  label: 'Contact',
                  value: _selectedValues['crm_contact_id'],
                  items: _optionsList(
                    widget.lookups?['contacts'] ??
                        widget.lookups?['contactsList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['crm_contact_id'] = v),
                ),
                _dropdownField<String>(
                  label: 'Status',
                  value: _selectedValues['status'],
                  items: [
                    for (final s in const {
                      'draft': 'Draft',
                      'sent': 'Sent',
                      'accepted': 'Accepted',
                      'rejected': 'Rejected',
                      'expired': 'Expired',
                    }.entries)
                      DropdownMenuItem(
                        value: s.key,
                        child: Text(appTr(s.value)),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['status'] = v),
                ),
                _datePickerField('issue_date', 'Issue date'),
                _datePickerField('valid_until', 'Valid until'),
                _textInput('notes', 'Notes', minLines: 2, maxLines: 4),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    appTr(_error!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(appTr(buttonLabel)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
