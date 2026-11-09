import '../services/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/mobile_api.dart';
import '../services/native_workspace_service.dart';
import '../services/social_post_service.dart';
import '../services/workspace_catalog.dart';
import 'native_module_screen.dart' show NativeSchemaScreen;
import 'native_settings_screen.dart';
import 'native_parity_screen.dart';
import 'native_phone_agent_screen.dart';
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

IconData _platformIcon(String? platform) => switch (platform?.toLowerCase()) {
  'twitter' || 'x' => Icons.alternate_email,
  'facebook' => Icons.facebook,
  'instagram' => Icons.camera_alt_outlined,
  'linkedin' => Icons.business,
  'tiktok' => Icons.music_note,
  'youtube' || 'youtube-shorts' => Icons.play_circle_outline,
  _ => Icons.share_outlined,
};

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
  final Map<String, TextEditingController> _apiKeyControllers = {};
  bool _savingApiKeys = false;
  bool _testingApiKey = false;

  TextEditingController _getApiKeyController(String providerId) =>
      _apiKeyControllers.putIfAbsent(providerId, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    for (final c in _apiKeyControllers.values) {
      c.dispose();
    }
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
      final rawList = data['data'] is List
          ? (data['data'] as List)
          : (data['data'] is Map ? (data['data']['data'] as List? ?? []) : []);
      setState(() {
        _workspace = data;
        _records = more
            ? [..._records, ...rawList.whereType<Map>()]
            : rawList.whereType<Map>().toList();
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

  Future<void> _publishPost(Map post, {String? kind}) async {
    final id = int.tryParse('${post['id']}');
    if (id == null) return;
    setState(() => _loading = true);
    try {
      await _service.publishPost(
        requestId: SocialPostService.requestId(),
        id: id,
        kind: kind ?? ('${_workspace?['kind']}' == 'social_agent' ? 'social_post' : 'blog_post'),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _duplicatePost(Map post, {String? kind}) async {
    final id = int.tryParse('${post['id']}');
    if (id == null) return;
    setState(() => _loading = true);
    try {
      await _service.duplicatePost(
        requestId: SocialPostService.requestId(),
        id: id,
        kind: kind ?? ('${_workspace?['kind']}' == 'social_agent' ? 'social_post' : 'blog_post'),
      );
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleAgent(Map agent, {String? kind}) async {
    final id = int.tryParse('${agent['id']}');
    if (id == null) return;
    setState(() => _loading = true);
    try {
      await _service.toggleAgent(
        requestId: SocialPostService.requestId(),
        id: id,
        kind: kind ?? ('${_workspace?['kind']}' == 'social_agent' ? 'social_agent' : 'blog_agent'),
      );
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
                        'calendar' => Icons.calendar_today_outlined,
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

  Widget _brandVoiceCard(Map record) {
    final name = record['name'] ?? 'Unnamed Brand';
    final tagline = record['tagline']?.toString().trim();
    final tone = record['tone_of_voice']?.toString().trim() ?? 'Professional';
    final industry = record['industry']?.toString().trim();
    final website = record['website']?.toString().trim();
    final targetAudience = record['target_audience']?.toString().trim();
    final description = record['description']?.toString().trim();
    final instructions = record['specific_instructions']?.toString().trim();
    final colorHex = record['brand_color']?.toString().trim();
    final products = (record['products'] as List? ?? []).whereType<Map>().toList();

    Color? brandColor;
    if (colorHex != null && colorHex.isNotEmpty) {
      try {
        final hex = colorHex.replaceAll('#', '');
        if (hex.length == 6) {
          brandColor = Color(int.parse('FF$hex', radix: 16));
        }
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
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
                  backgroundColor: brandColor ?? Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.record_voice_over_outlined,
                    color: brandColor != null
                        ? (brandColor.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$name',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              tone,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (tagline != null && tagline.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          tagline,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      _edit('brand_voice', record);
                    } else if (value == 'add_product') {
                      _edit('brand_product', {'company_id': record['id']});
                    } else if (value == 'delete') {
                      _delete('brand_voice', record);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(appTr('Edit brand voice'))),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'add_product',
                      child: Row(
                        children: [
                          const Icon(Icons.add_circle_outline, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(appTr('Add product / service'))),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(child: Text(appTr('Delete brand voice'), style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Chip(
                  avatar: const Icon(Icons.graphic_eq, size: 16),
                  label: Text('${appTr("Tone")}: $tone'),
                  visualDensity: VisualDensity.compact,
                ),
                if (industry != null && industry.isNotEmpty)
                  Chip(
                    avatar: const Icon(Icons.apartment, size: 16),
                    label: Text(industry),
                    visualDensity: VisualDensity.compact,
                  ),
                if (website != null && website.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.link, size: 16),
                    label: Text(website),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => SecureStore.invokeMethod<void>('openUrl', {'url': website}),
                  ),
              ],
            ),
            if (description != null && description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (targetAudience != null && targetAudience.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.groups_outlined, size: 16, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${appTr("Audience")}: $targetAudience',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (instructions != null && instructions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lightbulb_outline, size: 16, color: Theme.of(context).colorScheme.secondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${appTr("Guidelines")}: $instructions',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  appTr('Products & Services (:count)', {'count': '${products.length}'}),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _edit('brand_product', {'company_id': record['id']}),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(appTr('Add')),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
            if (products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  appTr('No products or services linked yet. Add one to target AI generation.'),
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                ),
              )
            else
              Column(
                children: [
                  for (final prod in products)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        child: Row(
                          children: [
                            Icon(
                              prod['type'] == 1 ? Icons.miscellaneous_services_outlined : Icons.inventory_2_outlined,
                              size: 18,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          '${prod['name']}',
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          prod['type'] == 1 ? appTr('Service') : appTr('Product'),
                                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if ('${prod['key_features'] ?? ''}'.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${prod['key_features']}',
                                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _edit('brand_product', prod),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              visualDensity: VisualDensity.compact,
                              color: Colors.redAccent,
                              onPressed: () => _delete('brand_product', prod),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _voiceChatbotCard(Map record) {
    final title = record['title']?.toString().trim() ?? 'Voice Bot';
    final active = record['active'] == true || record['active'] == 1;
    final language = record['language']?.toString().trim() ?? 'en';
    final voiceId = record['voice_id']?.toString().trim() ?? 'Default';
    final welcome = record['welcome_message']?.toString().trim();
    final instructions = record['instructions']?.toString().trim();
    final frameUrl = record['frame_url']?.toString().trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(
                    Icons.smart_toy_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: active
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 7,
                                  color: active ? Colors.green : Colors.orange,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  appTr(active ? 'Active' : 'Paused'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: active ? Colors.green.shade800 : Colors.orange.shade800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${appTr("Lang")}: ${language.toUpperCase()}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${appTr("Voice")}: $voiceId',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit') {
                      _edit('voice_chatbot', record);
                    } else if (value == 'toggle') {
                      await _service.mutate(
                        operation: 'toggle_active',
                        kind: 'voice_chatbot',
                        recordId: record['id'] as int?,
                        requestId: SocialPostService.requestId(),
                      );
                      _load();
                    } else if (value == 'delete') {
                      _delete('voice_chatbot', record);
                    } else if (value == 'test' && frameUrl != null && frameUrl.isNotEmpty) {
                      SecureStore.invokeMethod<void>('openUrl', {'url': frameUrl});
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit_outlined, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(appTr('Edit voice bot'))),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(active ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(appTr(active ? 'Pause bot' : 'Activate bot'))),
                        ],
                      ),
                    ),
                    if (frameUrl != null && frameUrl.isNotEmpty)
                      PopupMenuItem(
                        value: 'test',
                        child: Row(
                          children: [
                            const Icon(Icons.open_in_browser, size: 18),
                            const SizedBox(width: 10),
                            Expanded(child: Text(appTr('Open voice frame'))),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(child: Text(appTr('Delete voice bot'), style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (welcome != null && welcome.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${appTr("Welcome")}: $welcome',
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (instructions != null && instructions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${appTr("Instructions")}: $instructions',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _aiMusicCard(Map record) {
    final title = record['title']?.toString().trim() ?? 'Untitled Track';
    final prompt = record['prompt']?.toString().trim() ?? '';
    final audioUrl = record['audio_url']?.toString().trim();
    final provider = record['provider']?.toString().trim() ?? 'elevenlabs';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                  child: Icon(
                    Icons.music_note,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        provider.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (audioUrl != null && audioUrl.isNotEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () => SecureStore.invokeMethod<void>('openUrl', {'url': audioUrl}),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(appTr('Play')),
                  ),
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'delete') {
                      _delete('ai_music', record);
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          const SizedBox(width: 10),
                          Expanded(child: Text(appTr('Delete track'), style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (prompt.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                prompt,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

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

  Widget _agentCard(Map agent) {
    final isSocial = '${_workspace?['kind']}' == 'social_agent';
    final agentKind = isSocial ? 'social_agent' : 'blog_agent';
    final isActive = agent['is_active'] == true;
    final scheduleDays = (agent['schedule_days'] as List? ?? []).join(', ');
    final scheduleTimes = (agent['schedule_times'] as List? ?? []).join(', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  child: Icon(isSocial ? Icons.hub_outlined : Icons.smart_toy_outlined),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${agent['name']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${agent['frequency'] ?? 'Daily'} · ${agent['daily_post_count'] ?? 1} post/day',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_loading,
                  onSelected: (action) {
                    if (action == 'toggle') {
                      _toggleAgent(agent, kind: agentKind);
                    } else if (action == 'edit') {
                      _edit(agentKind, agent);
                    } else if (action == 'delete') {
                      _delete(agentKind, agent);
                    }
                  },
                  itemBuilder: (context) {
                    AppLocalizations.watch(context);
                    return [
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(
                          appTr(isActive ? 'Pause agent' : 'Activate agent'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(appTr('Edit agent')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(appTr('Delete agent')),
                      ),
                    ];
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _badge(isActive ? 'Active' : 'Paused'),
                if (scheduleDays.isNotEmpty)
                  Chip(
                    label: Text(
                      scheduleDays,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                if (scheduleTimes.isNotEmpty)
                  Chip(
                    label: Text(
                      scheduleTimes,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                for (final p in (agent['platforms'] as List? ?? []).whereType<Map>())
                  Chip(
                    avatar: Icon(_platformIcon('${p['platform']}'), size: 14),
                    label: Text(
                      '${p['name'] ?? p['platform']}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _agenda(Map post) {
    final isSocial = '${_workspace?['kind']}' == 'social_agent';
    final postKind = isSocial ? 'social_post' : 'blog_post';
    final status = '${post['status'] ?? 'draft'}';
    final isPublished = status == 'published';
    final platform = post['platform'] != null ? '${post['platform']}' : null;
    final postType = post['post_type'] != null ? '${post['post_type']}' : null;
    final title = post['title'] ?? post['content'] ?? '';
    final thumbnail = post['thumbnail'] != null && '${post['thumbnail']}'.isNotEmpty
        ? '${post['thumbnail']}'
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (thumbnail != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      thumbnail,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                        isSocial ? _platformIcon(platform) : Icons.article_outlined,
                        size: 32,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                ] else ...[
                  Icon(isSocial ? _platformIcon(platform) : Icons.article_outlined),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$title',
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          _badge(status),
                          if (platform != null)
                            Chip(
                              avatar: Icon(_platformIcon(platform), size: 14),
                              label: Text(
                                platform.toUpperCase(),
                                style: const TextStyle(fontSize: 10),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (postType != null)
                            Chip(
                              label: Text(
                                postType.replaceAll('_', ' '),
                                style: const TextStyle(fontSize: 10),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !_loading,
                  onSelected: (action) {
                    if (action == 'publish') {
                      _publishPost(post, kind: postKind);
                    } else if (action == 'edit') {
                      _edit(postKind, post);
                    } else if (action == 'duplicate') {
                      _duplicatePost(post, kind: postKind);
                    } else if (action == 'delete') {
                      _delete(postKind, post);
                    }
                  },
                  itemBuilder: (context) {
                    AppLocalizations.watch(context);
                    return [
                      if (!isPublished)
                        PopupMenuItem(
                          value: 'publish',
                          child: Text(appTr('Publish now')),
                        ),
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(appTr('Edit post')),
                      ),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text(appTr('Duplicate')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(appTr('Delete')),
                      ),
                    ];
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

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

  void _openMediaUrl(String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(appTr('Media playback')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(appTr('Stream or download URL:')),
            const SizedBox(height: 8),
            SelectableText(
              url,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(appTr('Link copied to clipboard'))),
              );
            },
            child: Text(appTr('Copy link')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(appTr('Close')),
          ),
        ],
      ),
    );
  }

  Widget _teamMember(Map record) {
    final name = '${record['name'] ?? 'Team Member'}';
    final email = '${record['email'] ?? ''}';
    final role = '${record['role'] ?? 'member'}';
    final status = '${record['status'] ?? 'active'}';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : 'M',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (email.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: [
                      _badge(role.toUpperCase()),
                      _badge(status),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: appTr('Remove member'),
              onPressed: _loading ? null : () => _delete('team_member', record),
            ),
          ],
        ),
      ),
    );
  }

  Widget _apiKeyCard(Map record) {
    final title = '${record['title'] ?? 'API Key'}';
    final description = '${record['description'] ?? ''}';
    final isConfigured = record['is_configured'] == true;
    final masked = '${record['key_masked'] ?? ''}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.vpn_key_outlined,
                  color: isConfigured
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                _badge(isConfigured ? 'Active' : 'Default'),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isConfigured ? masked : appTr('Using server-configured key'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            color: isConfigured ? null : Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _edit('api_keys', record),
                    icon: const Icon(Icons.edit, size: 16),
                    label: Text(appTr(isConfigured ? 'Change' : 'Set key')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeysWorkspace() {
    final providers = ((_workspace?['providers'] as List?) ??
            (_workspace?['data'] as List?) ??
            [])
        .whereType<Map>()
        .toList();
    if (providers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: Text(appTr('No API key providers available')),
          ),
        ],
      );
    }

    final defaultEngine = '${_workspace?['default_engine'] ?? 'gemini'}';

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.vpn_key_rounded,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appTr('${_workspace?['title'] ?? 'Api Keys Setting'}'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            appTr('${_workspace?['subtitle'] ?? 'Integrate your own personal OpenAI API Key and generate AI content.'}'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Chip(
                      avatar: const Icon(Icons.bolt, size: 16),
                      label: Text(
                        appTr('Active Engine: :engine', {'engine': defaultEngine.toUpperCase()}),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                      ),
                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: .15),
                      side: BorderSide.none,
                    ),
                    Chip(
                      avatar: const Icon(Icons.security, size: 16),
                      label: Text(
                        appTr('Rotated randomly per request'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      side: BorderSide.none,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final provider in providers) ...[
          _buildApiKeyProviderCard(provider, defaultEngine),
          const SizedBox(height: 16),
        ],
        FilledButton.icon(
          onPressed: _savingApiKeys ? null : _saveApiKeysSettings,
          icon: _savingApiKeys
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save),
          label: Text(
            _savingApiKeys ? appTr('Saving…') : appTr('Save'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildApiKeyProviderCard(Map provider, String defaultEngine) {
    final providerId = '${provider['id'] ?? provider['provider'] ?? 'gemini'}';
    final providerTitle = '${provider['title'] ?? (providerId == 'openai' ? 'OpenAI API Key' : (providerId == 'gemini' ? 'Google Gemini API Key' : (providerId == 'anthropic' ? 'Anthropic Claude API Key' : 'API Key')))}';
    final providerLabel = '${provider['label'] ?? (providerId == 'openai' ? 'OpenAI API Secret' : (providerId == 'gemini' ? 'Gemini API Secret' : (providerId == 'anthropic' ? 'Anthropic API Secret' : 'API Secret')))}';
    final description = '${provider['description'] ?? ''}';
    final isConfigured = provider['is_configured'] == true;
    final isDefault = provider['is_default'] == true || providerId == defaultEngine;
    final masked = '${provider['key_masked'] ?? ''}';
    final alertLimit = provider['alert_limit'] != null
        ? '${provider['alert_limit']}'
        : 'You can enter as much API KEY as you want. Click "Enter" after each api key.';
    final alertBilling = provider['alert_billing'] != null
        ? '${provider['alert_billing']}'
        : 'Please ensure that your $providerTitle key is fully functional and billing defined on your account.';

    final controller = _getApiKeyController(providerId);
    final hintText = provider['placeholder'] != null
        ? '${provider['placeholder']}'
        : (providerId == 'gemini'
            ? 'AIzaSy...'
            : (providerId == 'openai' ? 'sk-...' : 'sk-ant-...'));

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isDefault
            ? BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: .5), width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              appTr(providerTitle),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ),
                          if (isDefault) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                appTr('Default Engine'),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          appTr(description),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isConfigured)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle, size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          appTr('Active'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Text(
                    appTr('Using server-configured key'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (isConfigured) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            masked.isNotEmpty ? masked : appTr('Active key configured'),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appTr('An API key is configured. Leave this field empty to keep it unchanged.'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: controller,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: appTr(providerLabel),
                hintText: hintText,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.content_paste, size: 20),
                  tooltip: appTr('Paste from clipboard'),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null && data!.text!.isNotEmpty) {
                      controller.text = data.text!.trim();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .3),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: .2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      appTr(alertLimit),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: .3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      appTr(alertBilling),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _testingApiKey ? null : () => _testActiveApiKey(providerId),
              icon: _testingApiKey
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt, size: 18),
              label: Text(
                _testingApiKey
                    ? appTr('Testing connection…')
                    : appTr('After Saving Setting, Click Here to Test Your Api Keys'),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              ),
            ),
            if (isConfigured) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(appTr('Reset to server key?')),
                        content: Text(
                          appTr('This will remove your custom key and use the server default for :provider.', {'provider': providerTitle}),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text(appTr('Cancel')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text(appTr('Reset')),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _service.mutate(
                        kind: 'api_keys',
                        operation: 'save',
                        requestId: SocialPostService.requestId(),
                        inputs: {'clear_$providerId': true},
                      );
                      await _load();
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: Text(appTr('Reset to server key')),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveApiKeysSettings() async {
    if (_savingApiKeys) return;
    setState(() => _savingApiKeys = true);
    try {
      final inputs = <String, dynamic>{};
      for (final entry in _apiKeyControllers.entries) {
        final val = entry.value.text.trim();
        if (val.isNotEmpty) {
          if (entry.key == 'gemini') {
            inputs['gemini_api_keys'] = val;
          } else if (entry.key == 'openai') {
            inputs['api_keys'] = val;
            inputs['openai_api_keys'] = val;
          } else if (entry.key == 'anthropic') {
            inputs['anthropic_api_keys'] = val;
          } else {
            inputs['${entry.key}_api_keys'] = val;
          }
        }
      }

      final res = await _service.mutate(
        kind: 'api_keys',
        operation: 'save',
        requestId: SocialPostService.requestId(),
        inputs: inputs,
      );
      if (!mounted) return;
      for (final c in _apiKeyControllers.values) {
        c.clear();
      }
      final msg = res['message'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            msg != null
                ? appTr('$msg')
                : appTr('Settings saved successfully.'),
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appTr('Failed to save settings: :error', {'error': e.toString()})),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingApiKeys = false);
    }
  }

  Future<void> _testActiveApiKey(String provider) async {
    if (_testingApiKey) return;
    setState(() => _testingApiKey = true);
    try {
      final activeKey = _getApiKeyController(provider).text.trim();
      final res = await _service.mutate(
        kind: 'test_api_key',
        operation: 'test',
        requestId: SocialPostService.requestId(),
        inputs: {
          'provider': provider,
          if (activeKey.isNotEmpty) 'key': activeKey,
        },
      );
      if (!mounted) return;
      final msg = res['message'] ?? 'Connection test completed.';
      final isSuccess = res['success'] == true;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                isSuccess ? Icons.check_circle_outline : Icons.error_outline,
                color: isSuccess ? Colors.green : Theme.of(context).colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isSuccess ? appTr('Test Successful') : appTr('Test Failed'),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: Text(appTr('$msg')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(appTr('Close')),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(appTr('Connection test failed: :error', {'error': e.toString()})),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _testingApiKey = false);
    }
  }

  Widget _affiliateCard(Map record) {
    final amount = num.tryParse('${record['amount'] ?? 0}') ?? 0;
    final currency = (_workspace?['currency'] ?? r'$').toString();
    final status = '${record['status'] ?? 'pending'}';
    final date = _date(record['created_at']);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: const Icon(Icons.account_balance_wallet_outlined, size: 20),
        ),
        title: Text(
          '$currency${amount.toStringAsFixed(2)}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        subtitle: Text(date),
        trailing: _badge(status.toUpperCase()),
      ),
    );
  }

  Widget _integrationCard(Map record) {
    final title = '${record['title'] ?? 'Integration'}';
    final description = '${record['description'] ?? ''}';
    final isConnected = record['is_connected'] == true;
    final image = Uri.tryParse('${record['image'] ?? ''}');
    final url = image == null ? null : widget.api.origin.resolveUri(image);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: url != null && url.scheme == 'https'
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        '$url',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.extension_outlined),
                      ),
                    )
                  : const Icon(Icons.extension_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  _badge(isConnected ? 'Connected' : 'Disconnected'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaCard(Map record, String kind) {
    final title = '${record['title'] ?? record['prompt'] ?? record['name'] ?? 'Media output'}';
    final status = '${record['status'] ?? 'complete'}';
    final duration = record['duration'] ?? (record['duration_seconds'] != null ? '${record['duration_seconds']}s' : null);
    final resolution = record['resolution'] ?? record['target_resolution'];
    final tool = record['tool'] ?? record['used_ai_tool'] ?? record['model'];
    final date = _date(record['created_at']);

    final rawVideo = record['video_url'] ?? record['remote_url'] ?? record['local_path'];
    final rawThumb = record['thumbnail_url'] ?? record['cover_url'] ?? record['image_url'];
    final thumbUri = rawThumb != null ? Uri.tryParse('$rawThumb') : null;
    final resolvedThumb = thumbUri == null ? null : widget.api.origin.resolveUri(thumbUri);

    final videoUri = rawVideo != null ? Uri.tryParse('$rawVideo') : null;
    final resolvedVideo = videoUri == null ? null : widget.api.origin.resolveUri(videoUri);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (resolvedThumb != null && resolvedThumb.scheme == 'https')
            Stack(
              alignment: Alignment.center,
              children: [
                Image.network(
                  '$resolvedThumb',
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.video_library_outlined, size: 40),
                  ),
                ),
                if (resolvedVideo != null)
                  CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 24,
                    child: IconButton(
                      icon: const Icon(Icons.play_arrow, color: Colors.white),
                      onPressed: () => _openMediaUrl(resolvedVideo.toString()),
                    ),
                  ),
              ],
            )
          else if (resolvedVideo != null)
            Container(
              height: 120,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                child: FilledButton.icon(
                  onPressed: () => _openMediaUrl(resolvedVideo.toString()),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(appTr('Play video')),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _badge(status),
                    if (tool != null) _badge('$tool'),
                    if (duration != null) _badge('$duration'),
                    if (resolution != null) _badge('$resolution'),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      date,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const Spacer(),
                    if (resolvedVideo != null || resolvedThumb != null)
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: appTr('Copy link'),
                        onPressed: () {
                          final target = resolvedVideo?.toString() ?? resolvedThumb?.toString();
                          if (target != null) {
                            Clipboard.setData(ClipboardData(text: target));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(appTr('Link copied to clipboard'))),
                            );
                          }
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 18),
                      tooltip: appTr('Delete'),
                      onPressed: _loading ? null : () => _delete(kind, record),
                    ),
                  ],
                ),
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
    if (kind == 'phone_agent') {
      return NativePhoneAgentScreen(module: widget.module, api: widget.api);
    }
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
    final isSocialAgent = kind == 'social_agent';
    final isAgentWorkspace = isBlog || isSocialAgent;
    final isCalendar = isAgentWorkspace && _workspace!['calendar'] == true;
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
      'social_agent' =>
        'Manage automated agents, schedules, and cross-platform publishing.',
      'photoshoot' => 'Create product images and explore your recent work.',
      'team' => 'Manage your team members, roles and seat allocations.',
      'api_keys' => 'Configure your personal API keys for OpenAI, Anthropic and Gemini.',
      'affiliates' => 'Track your affiliate referrals, earnings, and payout requests.',
      'integration' => 'Connect external applications and manage API integrations.',
      'video_studio' => 'Unified hub for video creation, editing, dubbing, and captions.',
      'video_pro' => 'Generate cinematic AI videos from text prompts and images.',
      'video_agent' => 'Generate interactive talking agent videos and sessions.',
      'auto_edit' => 'Transform raw footage into polished, auto-edited videos.',
      'product_shot' => 'Generate studio-grade product photography with AI backgrounds.',
      'presentation' => 'Generate professional slide presentations from outlines and ideas.',
      'ai_avatar' => 'Create and customize lifelike AI talking avatars.',
      'image_pro' => 'Generate and enhance high-resolution AI artwork and photos.',
      'viral_clips' => 'Extract high-engagement viral shorts and clips from long videos.',
      'ai_influencer' => 'Create AI influencer videos and export social content.',
      'ai_persona' => 'Build custom AI personas, virtual twins, and talking heads.',
      'brand_voice' => 'Define company profiles, target audiences, and tone of voice for AI generation.',
      'voice_chatbots' => 'Manage interactive AI voice bots, system prompts, and frame widgets.',
      'ai_music' => 'Browse and play your generated AI music tracks and audio stems.',
      _ =>
        'Discover the tools in ${widget.module['category'] ?? 'your workspace'}.',
    };
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: kind == 'api_keys'
                ? _buildApiKeysWorkspace()
                : ListView(
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
                    if (kind == 'team') ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading ? null : () => _edit('team_member'),
                        icon: const Icon(Icons.person_add_outlined),
                        label: Text(appTr('Invite member')),
                      ),
                    ],
                    if (kind == 'affiliates') ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading ? null : () => _edit('affiliate_withdrawal'),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(appTr('Request payout')),
                      ),
                    ],
                    if (isAgentWorkspace && _workspace?['view_type'] != 'analytics') ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading
                            ? null
                            : () => _edit(
                                _workspace?['view_type'] == 'agents'
                                    ? (isSocialAgent ? 'social_agent' : 'blog_agent')
                                    : (isSocialAgent ? 'social_post' : 'blog_post'),
                              ),
                        icon: const Icon(Icons.add),
                        label: Text(
                          appTr(
                            _workspace?['view_type'] == 'agents'
                                ? 'New agent'
                                : 'New post',
                          ),
                        ),
                      ),
                    ],
                    if (kind == 'brand_voice') ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading ? null : () => _edit('brand_voice'),
                        icon: const Icon(Icons.add),
                        label: Text(appTr('New brand voice')),
                      ),
                    ],
                    if (kind == 'voice_chatbots') ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: _loading ? null : () => _edit('voice_chatbot'),
                        icon: const Icon(Icons.add),
                        label: Text(appTr('New voice bot')),
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
                if (isAgentWorkspace && (_workspace!['metrics'] as List? ?? []).isNotEmpty) ...[
                  _metrics(_workspace!['metrics'] as List),
                  const SizedBox(height: 16),
                ],
                if (isAgentWorkspace && _workspace?['view_type'] == 'dashboard') ...[
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .35),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  appTr(isSocialAgent ? 'Social Media Agent Status' : 'BlogPilot Status'),
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _workspace?['default_agent'] != null
                                      ? appTr("Active agent: :name (:status)", {
                                          "name": '${_workspace!['default_agent']['name']}',
                                          "status": '${(_workspace!['generation_status'] as Map?)?['status'] ?? 'Idle'}',
                                        })
                                      : appTr('No active agent configured yet.'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          _badge(
                            '${(_workspace?['generation_status'] as Map?)?['status'] ?? 'Idle'}'.toUpperCase(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (isAgentWorkspace && _workspace?['view_type'] == 'analytics') ...[
                  _section('Publication Trend (Last 12 Months)'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          for (final pt in (_workspace!['chart'] as List? ?? []).whereType<Map>())
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      '${pt['label']}',
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: (num.tryParse('${pt['value']}') ?? 0) > 0
                                            ? ((num.tryParse('${pt['value']}') ?? 0) / 20).clamp(0.05, 1.0)
                                            : 0.0,
                                        minHeight: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 32,
                                    child: Text(
                                      '${pt['value'] ?? 0}',
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
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
                if (isAgentWorkspace && !isCalendar && _workspace?['view_type'] != 'analytics') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _search,
                    decoration: InputDecoration(
                      hintText: appTr(
                        _workspace?['view_type'] == 'agents'
                            ? 'Search agents…'
                            : (isSocialAgent ? 'Search posts…' : 'Search articles…'),
                      ),
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
                  if (_workspace?['view_type'] != 'agents') ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final status in const {
                          'all': 'All posts',
                          'draft': 'Draft',
                          'scheduled': 'Scheduled',
                          'published': 'Published',
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
                  const SizedBox(height: 16),
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
                if (kind == 'video_studio') ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 16),
                  _section('Video Studio Tools'),
                  ..._tools(
                    tools
                        .where(
                          (tool) => !['workspace', 'schema', 'server_form'].contains(tool['route_type']),
                        )
                        .toList(),
                  ),
                  _section('Recent video outputs'),
                ],
                if (kind == 'affiliates') ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 16),
                  if (_workspace?['referral_url'] != null)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appTr('Your Referral Link'),
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_workspace!['referral_url']}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 18),
                                  tooltip: appTr('Copy link'),
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: '${_workspace!['referral_url']}'));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(appTr('Referral link copied'))),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  _section('Withdrawals history'),
                ],
                if (const [
                  'team',
                  'api_keys',
                  'integration',
                  'video_pro',
                  'video_agent',
                  'auto_edit',
                  'product_shot',
                  'presentation',
                  'ai_avatar',
                  'image_pro',
                  'viral_clips',
                  'ai_influencer',
                  'ai_persona',
                  'brand_voice',
                  'voice_chatbots',
                  'ai_music',
                ].contains(kind)) ...[
                  _metrics(_workspace!['metrics'] as List? ?? []),
                  const SizedBox(height: 16),
                  _section(switch (kind) {
                    'team' => 'Team members',
                    'api_keys' => 'AI Model providers',
                    'integration' => 'Connected integrations',
                    'product_shot' => 'Product photography outputs',
                    'presentation' => 'Generated presentations',
                    'ai_avatar' => 'Avatar videos',
                    'image_pro' => 'Generated image gallery',
                    'viral_clips' => 'Viral short clips',
                    'ai_influencer' => 'Influencer video exports',
                    'ai_persona' => 'Custom AI personas',
                    'brand_voice' => 'Brand Voices',
                    'voice_chatbots' => 'Configured Voice Bots',
                    'ai_music' => 'Generated Audio Tracks',
                    _ => 'Recent outputs',
                  }),
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
                if (isAgentWorkspace && _workspace!['show_agents'] == true && _workspace?['view_type'] != 'agents') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _section('Your agents'),
                      TextButton.icon(
                        onPressed: _loading ? null : () => _edit(isSocialAgent ? 'social_agent' : 'blog_agent'),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(appTr('New agent')),
                      ),
                    ],
                  ),
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
                    _agentCard(agent),
                  _section(isSocialAgent ? 'Recent posts' : 'Recent articles'),
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
                      'social_agent',
                      'brand_voice',
                      'voice_chatbots',
                      'ai_music',
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
                      'brand_voice' => Icons.record_voice_over_outlined,
                      'voice_chatbots' => Icons.smart_toy_outlined,
                      'ai_music' => Icons.music_note_outlined,
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
                              'blog' => isCalendar
                                  ? 'A clear calendar, a fresh start'
                                  : (_workspace?['view_type'] == 'agents'
                                      ? 'No agents configured'
                                      : 'No articles found'),
                              'social_agent' => isCalendar
                                  ? 'A clear calendar, a fresh start'
                                  : (_workspace?['view_type'] == 'agents'
                                      ? 'No agents configured'
                                      : 'No posts found'),
                              'brand_voice' => 'No brand voices yet',
                              'voice_chatbots' => 'No voice bots configured',
                              'ai_music' => 'No music generated yet',
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
                              'blog' => isCalendar
                                  ? 'Your planned articles will appear in the agenda. Select a day to explore your publishing schedule.'
                                  : (_workspace?['view_type'] == 'agents'
                                      ? 'Create your first AI BlogPilot agent to start auto-generating articles.'
                                      : 'Your planned articles will appear here.'),
                              'social_agent' => isCalendar
                                  ? 'Your planned articles will appear in the agenda. Select a day to explore your publishing schedule.'
                                  : (_workspace?['view_type'] == 'agents'
                                      ? 'Create your first Social Media Agent to automate cross-platform publishing.'
                                      : 'Your scheduled and published posts will appear here.'),
                              'brand_voice' =>
                                'Create a company profile with target audience and tone to guide AI content generation.',
                              'voice_chatbots' =>
                                'Create your first interactive AI voice bot to handle voice calls and audio sessions.',
                              'ai_music' =>
                                'Generate original AI music and sound tracks using text prompts.',
                              _ =>
                                'Your planned articles will appear in the agenda. Select a day to explore your publishing schedule.',
                            },
                    ),
                    actionLabel: kind == 'brand_voice'
                        ? appTr('Create brand voice')
                        : (kind == 'voice_chatbots'
                            ? appTr('New voice bot')
                            : (kind == 'photoshoot'
                                ? appTr('Create photoshoot')
                                : (isAgentWorkspace && !isCalendar
                                    ? appTr(
                                        _workspace?['view_type'] == 'agents'
                                            ? 'Create agent'
                                            : 'Create post',
                                      )
                                    : null))),
                    onAction: kind == 'brand_voice'
                        ? () => _edit('brand_voice')
                        : (kind == 'voice_chatbots'
                            ? () => _edit('voice_chatbot')
                            : (kind == 'photoshoot' &&
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
                                : (isAgentWorkspace && !isCalendar
                                    ? () => _edit(
                                        _workspace?['view_type'] == 'agents'
                                            ? (isSocialAgent ? 'social_agent' : 'blog_agent')
                                            : (isSocialAgent ? 'social_post' : 'blog_post'),
                                      )
                                    : null))),
                  ),
                for (final record in _records)
                  switch (kind) {
                    'invoices' => _invoice(record),
                    'payments' => _payment(record),
                    'proposals' => _proposal(record),
                    'estimates' => _estimate(record),
                    'companies' => _company(record),
                    'campaigns' => _campaign(record),
                    'brand_voice' => _brandVoiceCard(record),
                    'voice_chatbots' => _voiceChatbotCard(record),
                    'ai_music' => _aiMusicCard(record),
                    'blog' || 'social_agent' => _workspace?['view_type'] == 'agents'
                        ? _agentCard(record)
                        : _agenda(record),
                    'photoshoot' => _photo(record),
                    'team' => _teamMember(record),
                    'api_keys' => _apiKeyCard(record),
                    'affiliates' => _affiliateCard(record),
                    'integration' => _integrationCard(record),
                    'video_studio' ||
                    'video_pro' ||
                    'video_agent' ||
                    'auto_edit' ||
                    'product_shot' ||
                    'presentation' ||
                    'ai_avatar' ||
                    'image_pro' ||
                    'viral_clips' ||
                    'ai_influencer' ||
                    'ai_persona' =>
                      _mediaCard(record, kind),
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
      case 'blog_agent':
        _controllers['name'] =
            TextEditingController(text: '${r?['name'] ?? ''}');
        _controllers['selected_topics'] = TextEditingController(
          text: r?['selected_topics'] is List
              ? (r!['selected_topics'] as List).join(', ')
              : '${r?['selected_topics'] ?? ''}',
        );
        _controllers['daily_post_count'] = TextEditingController(
          text: '${r?['daily_post_count'] ?? 1}',
        );
        _selectedValues['language'] = r?['language'] ?? 'en';
        _selectedValues['tone'] = r?['tone'] ?? 'professional';
        _selectedValues['article_length'] = r?['article_length'] ?? 'medium';
        _selectedValues['frequency'] = r?['frequency'] ?? 'daily';
        _selectedValues['is_active'] = r?['is_active'] ?? true;
        break;
      case 'blog_post':
        _controllers['title'] =
            TextEditingController(text: '${r?['title'] ?? ''}');
        _controllers['content'] =
            TextEditingController(text: '${r?['content'] ?? ''}');
        _controllers['tags'] = TextEditingController(
          text: r?['tags'] is List
              ? (r!['tags'] as List).join(', ')
              : '${r?['tags'] ?? ''}',
        );
        _selectedValues['status'] = r?['status'] ?? 'draft';
        _selectedValues['agent_id'] =
            int.tryParse('${r?['agent_id'] ?? ''}');
        _dateValues['scheduled_at'] = r?['scheduled_at'] != null
            ? DateTime.tryParse('${r!['scheduled_at']}')
            : null;
        break;
      case 'social_agent':
        _controllers['name'] =
            TextEditingController(text: '${r?['name'] ?? ''}');
        _controllers['target_audience'] = TextEditingController(
          text: r?['target_audience'] is List
              ? (r!['target_audience'] as List).join(', ')
              : '${r?['target_audience'] ?? ''}',
        );
        _controllers['daily_post_count'] = TextEditingController(
          text: '${r?['daily_post_count'] ?? 1}',
        );
        _selectedValues['platform_ids'] = r?['platform_ids'] is List
            ? List<int>.from(
                (r!['platform_ids'] as List)
                    .map((e) => int.tryParse('$e'))
                    .whereType<int>(),
              )
            : <int>[];
        _selectedValues['language'] = r?['language'] ?? 'en';
        _selectedValues['tone'] = r?['tone'] ?? 'professional';
        _selectedValues['frequency'] = r?['frequency'] ?? 'daily';
        _selectedValues['is_active'] = r?['is_active'] ?? true;
        break;
      case 'social_post':
        _controllers['content'] =
            TextEditingController(text: '${r?['content'] ?? ''}');
        _selectedValues['post_type'] = r?['post_type'] ?? 'text';
        _selectedValues['status'] = r?['status'] ?? 'draft';
        final platforms = (widget.lookups?['platforms'] as List? ?? [])
            .whereType<Map>()
            .toList();
        final agents = ((widget.lookups?['agents'] ??
                widget.lookups?['agentsList']) as List? ?? [])
            .whereType<Map>()
            .toList();
        _selectedValues['platform_id'] =
            int.tryParse('${r?['platform_id'] ?? ''}') ??
                (platforms.isNotEmpty
                    ? int.tryParse('${platforms.first['id']}')
                    : null);
        _selectedValues['agent_id'] =
            int.tryParse('${r?['agent_id'] ?? ''}') ??
                (agents.isNotEmpty
                    ? int.tryParse('${agents.first['id']}')
                    : null);
        _dateValues['scheduled_at'] = r?['scheduled_at'] != null
            ? DateTime.tryParse('${r!['scheduled_at']}')
            : null;
        break;
      case 'team_member':
        _controllers['email'] =
            TextEditingController(text: '${r?['email'] ?? ''}');
        _selectedValues['role'] = r?['role'] ?? 'member';
        break;
      case 'api_keys':
        _controllers['openai_key'] = TextEditingController(text: '');
        _controllers['anthropic_key'] = TextEditingController(text: '');
        _controllers['gemini_key'] = TextEditingController(text: '');
        break;
      case 'affiliate_withdrawal':
        _controllers['amount'] = TextEditingController(text: '');
        _controllers['bank_account'] =
            TextEditingController(text: '${l?['bank_account'] ?? ''}');
        break;
      case 'affiliate_invite':
        _controllers['to_mail'] = TextEditingController(text: '');
        break;
      case 'brand_voice':
        _controllers['name'] =
            TextEditingController(text: '${r?['name'] ?? ''}');
        _controllers['description'] =
            TextEditingController(text: '${r?['description'] ?? ''}');
        _controllers['tagline'] =
            TextEditingController(text: '${r?['tagline'] ?? ''}');
        _controllers['target_audience'] =
            TextEditingController(text: '${r?['target_audience'] ?? ''}');
        _controllers['industry'] =
            TextEditingController(text: '${r?['industry'] ?? ''}');
        _controllers['website'] =
            TextEditingController(text: '${r?['website'] ?? ''}');
        _controllers['brand_color'] =
            TextEditingController(text: '${r?['brand_color'] ?? '#6366F1'}');
        _controllers['specific_instructions'] =
            TextEditingController(text: '${r?['specific_instructions'] ?? ''}');
        _selectedValues['tone_of_voice'] =
            r?['tone_of_voice'] ?? (l?['voice_tones'] as List?)?.first ?? 'Professional';
        break;
      case 'brand_product':
        _controllers['name'] =
            TextEditingController(text: '${r?['name'] ?? ''}');
        _controllers['key_features'] =
            TextEditingController(text: '${r?['key_features'] ?? ''}');
        _selectedValues['type'] = r?['type'] ?? 0;
        _selectedValues['company_id'] =
            int.tryParse('${r?['company_id'] ?? l?['company_id'] ?? ''}');
        break;
      case 'voice_chatbot':
        _controllers['title'] =
            TextEditingController(text: '${r?['title'] ?? ''}');
        _controllers['voice_id'] =
            TextEditingController(text: '${r?['voice_id'] ?? ''}');
        _controllers['welcome_message'] =
            TextEditingController(text: '${r?['welcome_message'] ?? ''}');
        _controllers['instructions'] =
            TextEditingController(text: '${r?['instructions'] ?? ''}');
        _selectedValues['language'] = r?['language'] ?? 'en';
        _selectedValues['active'] = r?['active'] ?? true;
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
    final isLegacy = const [
      'company',
      'campaign',
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
      'blog_agent' =>
        widget.record == null ? 'Create blog agent' : 'Edit blog agent',
      'blog_post' =>
        widget.record == null ? 'Create blog post' : 'Edit blog post',
      'social_agent' =>
        widget.record == null ? 'Create social agent' : 'Edit social agent',
      'social_post' =>
        widget.record == null ? 'Create social post' : 'Edit social post',
      'team_member' => 'Invite team member',
      'api_keys' => 'Configure API keys',
      'affiliate_withdrawal' => 'Request affiliate payout',
      'affiliate_invite' => 'Invite affiliate partner',
      'brand_voice' =>
        widget.record == null ? 'Create brand voice' : 'Edit brand voice',
      'brand_product' =>
        widget.record == null ? 'Add product / service' : 'Edit product / service',
      'voice_chatbot' =>
        widget.record == null ? 'Create voice bot' : 'Edit voice bot',
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
      'blog_agent' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create agent' : 'Save agent'),
      'blog_post' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create post' : 'Save post'),
      'social_agent' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create agent' : 'Save agent'),
      'social_post' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create post' : 'Save post'),
      'team_member' => _saving ? 'Sending…' : 'Send invitation',
      'api_keys' => _saving ? 'Saving…' : 'Save keys',
      'affiliate_withdrawal' => _saving ? 'Submitting…' : 'Submit request',
      'affiliate_invite' => _saving ? 'Sending…' : 'Send invite',
      'brand_voice' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create brand voice' : 'Save brand voice'),
      'brand_product' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Add product' : 'Save product'),
      'voice_chatbot' => _saving
          ? 'Saving…'
          : (widget.record == null ? 'Create voice bot' : 'Save voice bot'),
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
              if (isLegacy)
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
              if (widget.kind == 'blog_agent') ...[
                _textInput(
                  'name',
                  'Agent name',
                  hint: 'e.g. Tech & AI Writer',
                  required: true,
                ),
                _textInput(
                  'selected_topics',
                  'Topics / Keywords',
                  hint: 'e.g. AI tools, productivity, automation (comma separated)',
                  minLines: 2,
                  maxLines: 3,
                ),
                _dropdownField<String>(
                  label: 'Language',
                  value: _selectedValues['language'],
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Spanish')),
                    DropdownMenuItem(value: 'fr', child: Text('French')),
                    DropdownMenuItem(value: 'de', child: Text('German')),
                    DropdownMenuItem(value: 'tr', child: Text('Turkish')),
                    DropdownMenuItem(value: 'it', child: Text('Italian')),
                    DropdownMenuItem(value: 'pt', child: Text('Portuguese')),
                    DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                    DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                    DropdownMenuItem(value: 'zh', child: Text('Chinese')),
                    DropdownMenuItem(value: 'ja', child: Text('Japanese')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['language'] = v),
                ),
                _dropdownField<String>(
                  label: 'Tone of voice',
                  value: _selectedValues['tone'],
                  items: const [
                    DropdownMenuItem(value: 'professional', child: Text('Professional')),
                    DropdownMenuItem(value: 'casual', child: Text('Casual / Conversational')),
                    DropdownMenuItem(value: 'informative', child: Text('Informative / Educational')),
                    DropdownMenuItem(value: 'humorous', child: Text('Humorous / Witty')),
                    DropdownMenuItem(value: 'engaging', child: Text('Engaging / Storytelling')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['tone'] = v),
                ),
                _dropdownField<String>(
                  label: 'Article length',
                  value: _selectedValues['article_length'],
                  items: const [
                    DropdownMenuItem(value: 'short', child: Text('Short (~500 words)')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium (~1000 words)')),
                    DropdownMenuItem(value: 'long', child: Text('Long (~1500+ words)')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['article_length'] = v),
                ),
                _dropdownField<String>(
                  label: 'Posting frequency',
                  value: _selectedValues['frequency'],
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom schedule')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['frequency'] = v),
                ),
                _textInput(
                  'daily_post_count',
                  'Daily post count',
                  keyboardType: TextInputType.number,
                ),
              ],
              if (widget.kind == 'blog_post') ...[
                _textInput(
                  'title',
                  'Post title',
                  hint: 'Enter article headline',
                  required: true,
                ),
                _textInput(
                  'content',
                  'Post content',
                  hint: 'Article content or draft overview…',
                  minLines: 4,
                  maxLines: 8,
                ),
                _dropdownField<int>(
                  label: 'Author Agent (optional)',
                  value: _selectedValues['agent_id'],
                  items: _optionsList(
                    widget.lookups?['agents'] ??
                        widget.lookups?['agentsList'],
                  ),
                  allowClear: true,
                  onChanged: (v) =>
                      setState(() => _selectedValues['agent_id'] = v),
                ),
                _dropdownField<String>(
                  label: 'Status',
                  value: _selectedValues['status'],
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'scheduled', child: Text('Scheduled')),
                    DropdownMenuItem(value: 'published', child: Text('Published')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['status'] = v),
                ),
                _datePickerField('scheduled_at', 'Schedule publication date'),
                _textInput(
                  'tags',
                  'Tags',
                  hint: 'ai, technology, news (comma separated)',
                ),
              ],
              if (widget.kind == 'social_agent') ...[
                _textInput(
                  'name',
                  'Agent name',
                  hint: 'e.g. Social Growth Agent',
                  required: true,
                ),
                if ((widget.lookups?['platforms'] as List? ?? []).isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      appTr('Connected platforms'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final p in (widget.lookups?['platforms'] as List).whereType<Map>())
                          FilterChip(
                            avatar: Icon(_platformIcon('${p['platform']}'), size: 16),
                            label: Text('${p['name'] ?? p['platform']}'),
                            selected: (_selectedValues['platform_ids'] as List? ?? []).contains(p['id']),
                            onSelected: (selected) {
                              setState(() {
                                final list = List<int>.from(_selectedValues['platform_ids'] as List? ?? []);
                                final pid = int.tryParse('${p['id']}');
                                if (pid != null) {
                                  if (selected) {
                                    list.add(pid);
                                  } else {
                                    list.remove(pid);
                                  }
                                }
                                _selectedValues['platform_ids'] = list;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ],
                _textInput(
                  'target_audience',
                  'Target audience',
                  hint: 'e.g. Tech founders, startup creators (comma separated)',
                  minLines: 2,
                  maxLines: 3,
                ),
                _dropdownField<String>(
                  label: 'Language',
                  value: _selectedValues['language'],
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Spanish')),
                    DropdownMenuItem(value: 'fr', child: Text('French')),
                    DropdownMenuItem(value: 'de', child: Text('German')),
                    DropdownMenuItem(value: 'tr', child: Text('Turkish')),
                    DropdownMenuItem(value: 'it', child: Text('Italian')),
                    DropdownMenuItem(value: 'pt', child: Text('Portuguese')),
                    DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                    DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                    DropdownMenuItem(value: 'zh', child: Text('Chinese')),
                    DropdownMenuItem(value: 'ja', child: Text('Japanese')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['language'] = v),
                ),
                _dropdownField<String>(
                  label: 'Tone of voice',
                  value: _selectedValues['tone'],
                  items: const [
                    DropdownMenuItem(value: 'professional', child: Text('Professional')),
                    DropdownMenuItem(value: 'casual', child: Text('Casual / Conversational')),
                    DropdownMenuItem(value: 'informative', child: Text('Informative / Educational')),
                    DropdownMenuItem(value: 'humorous', child: Text('Humorous / Witty')),
                    DropdownMenuItem(value: 'engaging', child: Text('Engaging / Storytelling')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['tone'] = v),
                ),
                _dropdownField<String>(
                  label: 'Posting frequency',
                  value: _selectedValues['frequency'],
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('Daily')),
                    DropdownMenuItem(value: 'weekly', child: Text('Weekly')),
                    DropdownMenuItem(value: 'custom', child: Text('Custom schedule')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['frequency'] = v),
                ),
                _textInput(
                  'daily_post_count',
                  'Daily post count',
                  keyboardType: TextInputType.number,
                ),
              ],
              if (widget.kind == 'social_post') ...[
                _textInput(
                  'content',
                  'Post content',
                  hint: 'Write your post caption or message…',
                  minLines: 4,
                  maxLines: 8,
                  required: true,
                ),
                _dropdownField<int>(
                  label: 'Platform',
                  value: _selectedValues['platform_id'],
                  items: _optionsList(widget.lookups?['platforms']),
                  allowClear: false,
                  onChanged: (v) =>
                      setState(() => _selectedValues['platform_id'] = v),
                ),
                _dropdownField<int>(
                  label: 'Author Agent',
                  value: _selectedValues['agent_id'],
                  items: _optionsList(
                    widget.lookups?['agents'] ??
                        widget.lookups?['agentsList'],
                  ),
                  allowClear: false,
                  onChanged: (v) =>
                      setState(() => _selectedValues['agent_id'] = v),
                ),
                _dropdownField<String>(
                  label: 'Post type',
                  value: _selectedValues['post_type'],
                  items: const [
                    DropdownMenuItem(value: 'text', child: Text('Text')),
                    DropdownMenuItem(value: 'single_image', child: Text('Single Image')),
                    DropdownMenuItem(value: 'carousel', child: Text('Carousel')),
                    DropdownMenuItem(value: 'video', child: Text('Video')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['post_type'] = v),
                ),
                _dropdownField<String>(
                  label: 'Status',
                  value: _selectedValues['status'],
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('Draft')),
                    DropdownMenuItem(value: 'scheduled', child: Text('Scheduled')),
                    DropdownMenuItem(value: 'published', child: Text('Published')),
                  ],
                  onChanged: (v) =>
                      setState(() => _selectedValues['status'] = v),
                ),
                _datePickerField('scheduled_at', 'Schedule publication date'),
              ],
              if (widget.kind == 'team_member') ...[
                _textInput(
                  'email',
                  'Member email',
                  keyboardType: TextInputType.emailAddress,
                  required: true,
                ),
                _dropdownField<String>(
                  label: 'Role',
                  value: _selectedValues['role'] ?? 'member',
                  items: const [
                    DropdownMenuItem(value: 'member', child: Text('Member')),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: (v) => setState(() => _selectedValues['role'] = v),
                ),
              ],
              if (widget.kind == 'api_keys') ...[
                _textInput(
                  'openai_key',
                  'OpenAI API Key',
                  hint: 'sk-...',
                ),
                _textInput(
                  'anthropic_key',
                  'Anthropic Claude API Key',
                  hint: 'sk-ant-...',
                ),
                _textInput(
                  'gemini_key',
                  'Google Gemini API Key',
                  hint: 'AIza...',
                ),
              ],
              if (widget.kind == 'affiliate_withdrawal') ...[
                _textInput(
                  'amount',
                  'Withdrawal amount',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  required: true,
                ),
                _textInput(
                  'bank_account',
                  'Payout details / Bank account info',
                  maxLines: 3,
                ),
              ],
              if (widget.kind == 'affiliate_invite') ...[
                _textInput(
                  'to_mail',
                  'Partner email address',
                  keyboardType: TextInputType.emailAddress,
                  required: true,
                ),
              ],
              if (widget.kind == 'brand_voice') ...[
                _textInput(
                  'name',
                  'Company / Brand Name',
                  hint: 'Acme Corp',
                  required: true,
                ),
                _textInput(
                  'description',
                  'Description',
                  hint: 'What does your company do?',
                  minLines: 3,
                  maxLines: 5,
                  required: true,
                ),
                _textInput(
                  'tagline',
                  'Tagline',
                  hint: 'Innovating tomorrow, today',
                ),
                _dropdownField<String>(
                  label: 'Tone of voice',
                  value: _selectedValues['tone_of_voice']?.toString(),
                  items: [
                    for (final tone in (widget.lookups?['voice_tones'] as List? ?? [
                      'Professional',
                      'Funny',
                      'Casual',
                      'Excited',
                      'Witty',
                      'Sarcastic',
                      'Feminine',
                      'Masculine',
                      'Bold',
                      'Dramatic',
                      'Grumpy',
                      'Secretive',
                    ]))
                      DropdownMenuItem(
                        value: '$tone',
                        child: Text(appTr('$tone')),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedValues['tone_of_voice'] = v),
                ),
                _textInput(
                  'industry',
                  'Industry',
                  hint: 'Technology, Healthcare, Fashion...',
                ),
                _textInput(
                  'website',
                  'Website',
                  hint: 'https://example.com',
                  keyboardType: TextInputType.url,
                ),
                _textInput(
                  'target_audience',
                  'Target Audience',
                  hint: 'e.g. Small business owners, tech-savvy millennials',
                  minLines: 2,
                  maxLines: 4,
                ),
                _textInput(
                  'brand_color',
                  'Brand Color Hex',
                  hint: '#6366F1',
                ),
                _textInput(
                  'specific_instructions',
                  'Specific Guidelines / Instructions',
                  hint: 'e.g. Never use words like cheap; focus on quality.',
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
              if (widget.kind == 'brand_product') ...[
                _textInput(
                  'name',
                  'Product or Service Name',
                  hint: 'e.g. CloudSync Pro',
                  required: true,
                ),
                _dropdownField<int>(
                  label: 'Type',
                  value: _selectedValues['type'] as int? ?? 0,
                  items: [
                    DropdownMenuItem(value: 0, child: Text(appTr('Product'))),
                    DropdownMenuItem(value: 1, child: Text(appTr('Service'))),
                  ],
                  onChanged: (v) => setState(() => _selectedValues['type'] = v ?? 0),
                ),
                _textInput(
                  'key_features',
                  'Key Features',
                  hint: 'Describe top features, benefits, and specifications...',
                  minLines: 3,
                  maxLines: 5,
                  required: true,
                ),
              ],
              if (widget.kind == 'voice_chatbot') ...[
                _textInput(
                  'title',
                  'Voice Bot Title',
                  hint: 'Customer Support Bot',
                  required: true,
                ),
                _dropdownField<String>(
                  label: 'Language',
                  value: _selectedValues['language']?.toString() ?? 'en',
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'es', child: Text('Spanish')),
                    DropdownMenuItem(value: 'fr', child: Text('French')),
                    DropdownMenuItem(value: 'de', child: Text('German')),
                    DropdownMenuItem(value: 'it', child: Text('Italian')),
                    DropdownMenuItem(value: 'pt', child: Text('Portuguese')),
                    DropdownMenuItem(value: 'hi', child: Text('Hindi')),
                    DropdownMenuItem(value: 'tr', child: Text('Turkish')),
                    DropdownMenuItem(value: 'ar', child: Text('Arabic')),
                    DropdownMenuItem(value: 'zh', child: Text('Chinese')),
                    DropdownMenuItem(value: 'ja', child: Text('Japanese')),
                  ],
                  onChanged: (v) => setState(() => _selectedValues['language'] = v),
                ),
                _textInput(
                  'voice_id',
                  'Voice ID / Model',
                  hint: 'e.g. 21m00Tcm4TlvDq8ikWAM or alloy',
                ),
                _textInput(
                  'welcome_message',
                  'Welcome Greeting',
                  hint: 'Hello! How can I assist you today?',
                  minLines: 2,
                  maxLines: 3,
                ),
                _textInput(
                  'instructions',
                  'System Prompt / Instructions',
                  hint: 'You are a helpful customer concierge...',
                  minLines: 4,
                  maxLines: 8,
                ),
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
