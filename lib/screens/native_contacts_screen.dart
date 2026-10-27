import '../services/app_localizations.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/mobile_api.dart';
import 'server_screen.dart';

class NativeContactsScreen extends StatefulWidget {
  final MobileApi api;
  const NativeContactsScreen({super.key, required this.api});
  @override
  State<NativeContactsScreen> createState() => _NativeContactsScreenState();
}

class _NativeContactsScreenState extends State<NativeContactsScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map>? _contacts;
  String _filter = 'all';
  String? _error;
  int _page = 1, _lastPage = 1, _request = 0;
  bool _loadingMore = false;
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
    final request = ++_request;
    if (more) setState(() => _loadingMore = true);
    try {
      final page = more ? _page + 1 : 1;
      final data = await widget.api.request(
        '/native/contacts?query=${Uri.encodeQueryComponent(_search.text)}&filter=$_filter&page=$page',
      ) as Map;
      if (mounted && request == _request) {
        setState(() {
          final rows = (data['data'] as List).whereType<Map>().toList();
          _contacts = more ? [...?_contacts, ...rows] : rows;
          _page = page;
          _lastPage = data['last_page'] as int;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted && request == _request) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _launch(String scheme, String value) async {
    try {
      await SecureStore.invokeMethod<void>('contactAction', {
        'scheme': scheme,
        'value': value,
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              appTr('No compatible app is available on this device.'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _edit([Map? contact]) async {
    final names = [
      'first_name',
      'last_name',
      'email',
      'phone',
      'job_title',
      'notes',
    ];
    final controllers = {
      for (final name in names)
        name: TextEditingController(text: '${contact?[name] ?? ''}'),
    };
    final form = GlobalKey<FormState>();
    var status = '${contact?['status'] ?? 'active'}';
    var favorite = contact?['is_favorite'] == true;
    var saving = false;
    String? error;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        AppLocalizations.watch(sheetContext);
        return StatefulBuilder(
          builder: (context, change) {
            AppLocalizations.watch(context);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: Form(
                key: form,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        appTr(contact == null ? 'New contact' : 'Edit contact'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 18),
                      for (final name in names)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextFormField(
                            controller: controllers[name],
                            enabled: !saving,
                            maxLines: name == 'notes' ? 3 : 1,
                            keyboardType: name == 'email'
                                ? TextInputType.emailAddress
                                : name == 'phone'
                                ? TextInputType.phone
                                : TextInputType.text,
                            decoration: InputDecoration(
                              labelText: name.replaceAll('_', ' '),
                            ),
                            validator: (value) {
                              if ((name == appTr('first_name') ||
                                      name == appTr('last_name')) &&
                                  (value?.trim().isEmpty ?? true)) {
                                return appTr('Required');
                              }
                              if (name == appTr('email') &&
                                  value!.isNotEmpty &&
                                  !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                      .hasMatch(value)) {
                                return appTr('Enter a valid email');
                              }
                              return null;
                            },
                          ),
                        ),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: status,
                        decoration: InputDecoration(labelText: appTr('Status')),
                        items: [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text(appTr('Active')),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text(appTr('Inactive')),
                          ),
                        ],
                        onChanged: saving ? null : (value) => status = value!,
                      ),
                      CheckboxListTile(
                        title: Text(appTr('Favorite')),
                        value: favorite,
                        onChanged: saving
                            ? null
                            : (value) => change(() => favorite = value!),
                      ),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(appTr(error!)),
                        ),
                      FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                if (!form.currentState!.validate()) return;
                                change(() {
                                  saving = true;
                                  error = null;
                                });
                                try {
                                  await widget.api.request(
                                    '/native/contacts${contact == null ? '' : '/${contact['id']}'}',
                                    method: contact == null ? 'POST' : 'PUT',
                                    body: {
                                      for (final name in names)
                                        name: controllers[name]!.text.trim(),
                                      'status': status,
                                      'is_favorite': favorite,
                                    },
                                  );
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext, true);
                                  }
                                } catch (failure) {
                                  if (sheetContext.mounted) {
                                    change(() {
                                      error = failure.toString();
                                      saving = false;
                                    });
                                  }
                                }
                              },
                        child: Text(appTr(saving ? 'Saving…' : 'Save contact')),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    for (final controller in controllers.values) {
      controller.dispose();
    }
    if (saved == true) await _load();
  }

  Future<void> _delete(Map contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppLocalizations.watch(context);
        return AlertDialog(
          title: Text(appTr('Delete contact?')),
          content: Text(
            appTr(":value :value2 will be removed.", {
              "value": contact['first_name'],
              "value2": contact['last_name'],
            }),
          ),
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
    if (confirmed != true) return;
    try {
      await widget.api.request(
        '/native/contacts/${contact['id']}',
        method: 'DELETE',
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: appTr('Search contacts'),
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _load);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    spacing: 8,
                    children: [
                      for (final filter in [
                        'all',
                        'active',
                        'inactive',
                        'favorites',
                      ])
                        ChoiceChip(
                          label: Text(appTr(filter)),
                          selected: _filter == filter,
                          onSelected: (_) {
                            setState(() => _filter = filter);
                            _load();
                          },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: () => _edit(),
                icon: const Icon(Icons.person_add_alt_1),
                tooltip: appTr('New contact'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(appTr(_error!)),
          ),
        Expanded(
          child: _contacts == null
              ? (_error == null
                    ? const Center(child: CircularProgressIndicator())
                    : RetryPanel(message: appTr(_error!), retry: _load))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    children: [
                      if (_contacts!.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            appTr(
                              'No contacts found. Add your first contact to get started.',
                            ),
                          ),
                        ),
                      for (final contact in _contacts!)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    child: Text('${contact['initials'] ?? ''}'),
                                  ),
                                  title: Text(
                                    '${contact['first_name']} ${contact['last_name']}',
                                  ),
                                  subtitle: Text(
                                    [
                                          contact['job_title'],
                                          contact['company'],
                                          contact['email'],
                                        ]
                                        .where(
                                          (value) =>
                                              value != null &&
                                              '$value'.isNotEmpty,
                                        )
                                        .join(' · '),
                                  ),
                                  trailing: Chip(
                                    label: Text(appTr('${contact['status']}')),
                                  ),
                                  onTap: () => _edit(contact),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if ('${contact['phone'] ?? ''}'.isNotEmpty)
                                      IconButton(
                                        onPressed: () => _launch(
                                          'tel',
                                          '${contact['phone']}',
                                        ),
                                        icon: const Icon(Icons.call_outlined),
                                        tooltip: appTr('Call'),
                                      ),
                                    if ('${contact['email'] ?? ''}'.isNotEmpty)
                                      IconButton(
                                        onPressed: () => _launch(
                                          'mailto',
                                          '${contact['email']}',
                                        ),
                                        icon: const Icon(Icons.mail_outline),
                                        tooltip: appTr('Email'),
                                      ),
                                    IconButton(
                                      onPressed: () => _edit(contact),
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: appTr('Edit'),
                                    ),
                                    IconButton(
                                      onPressed: () => _delete(contact),
                                      icon: const Icon(Icons.delete_outline),
                                      tooltip: appTr('Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_page < _lastPage)
                        TextButton(
                          onPressed: _loadingMore
                              ? null
                              : () => _load(more: true),
                          child: Text(
                            appTr(_loadingMore ? 'Loading…' : 'Load more'),
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
