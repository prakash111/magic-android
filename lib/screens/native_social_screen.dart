import '../services/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/mobile_api.dart';
import '../services/image_attachment_picker.dart';
import '../services/social_post_service.dart';
import 'server_screen.dart' show RetryPanel;
import 'workspace_screen.dart' show SocialAccountsScreen;

class ServerSocialScreen extends StatefulWidget {
  final MobileApi? api;
  final bool calendarInitiallyVisible;
  final int refreshVersion;
  const ServerSocialScreen({
    super.key,
    this.api,
    this.calendarInitiallyVisible = false,
    this.refreshVersion = 0,
  });
  @override
  State<ServerSocialScreen> createState() => _ServerSocialScreenState();
}

class _ServerSocialScreenState extends State<ServerSocialScreen> {
  late final _api = widget.api ?? MobileApi.instance;
  late final _service = SocialPostService(_api);
  late bool _calendar = widget.calendarInitiallyVisible;
  late String _status = _calendar ? 'scheduled' : 'all';
  DateTime _day = DateTime.now();
  List<Map<String, dynamic>>? _posts;
  List<Map<String, dynamic>> _accounts = [];
  String? _error;
  bool _loading = false;
  int _page = 1, _lastPage = 1, _generation = 0;
  static const _statuses = {
    'all': 'All posts',
    'draft': 'Drafts',
    'scheduled': 'Scheduled',
    'published': 'Published',
    'failed': 'Failed',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ServerSocialScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refreshVersion != oldWidget.refreshVersion) _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results =
          await Future.wait<Object>([
            _service.posts(
              status: _status,
              page: more ? _page + 1 : 1,
              day: _calendar ? _day : null,
            ),
            _service.accounts(),
          ]).timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw const ApiFailure(
              'Posts are taking too long to load. Please retry.',
            ),
          );
      if (!mounted || generation != _generation) return;
      final posts = results[0] as SocialPostPage;
      setState(() {
        _posts = more ? [...?_posts, ...posts.posts] : posts.posts;
        _accounts = results[1] as List<Map<String, dynamic>>;
        _page = posts.page;
        _lastPage = posts.lastPage;
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

  void _filter(String status) {
    setState(() {
      _status = status;
      _posts = null;
      if (status == 'draft') _calendar = false;
    });
    _load();
  }

  Future<void> _compose() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (localizationContext) {
          AppLocalizations.watch(localizationContext);
          return SocialPostComposer(api: _api, accounts: _accounts);
        },
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(Map post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        AppLocalizations.watch(context);
        return AlertDialog(
          title: Text(appTr('Delete post?')),
          content: Text(appTr('This removes the post from your workspace.')),
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
    try {
      await _service.delete('${post['id']}');
      if (mounted) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    if (_posts == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : RetryPanel(message: appTr(_error!), retry: _load),
      );
    }
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  appTr('Posts & scheduling'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final status in _statuses.entries)
                      ChoiceChip(
                        label: Text(appTr(status.value)),
                        selected: _status == status.key,
                        onSelected: (_) => _filter(status.key),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (localizationContext) {
                              AppLocalizations.watch(localizationContext);
                              return SocialAccountsScreen(api: _api);
                            },
                          ),
                        );
                        if (mounted) await _load();
                      },
                      icon: const Icon(Icons.hub_outlined),
                      label: Text(appTr('Connected accounts')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _status == 'draft'
                          ? null
                          : () {
                              setState(() {
                                _calendar = !_calendar;
                                _posts = null;
                              });
                              _load();
                            },
                      icon: Icon(
                        _calendar
                            ? Icons.view_list_outlined
                            : Icons.calendar_month_outlined,
                      ),
                      label: Text(
                        appTr(_calendar ? 'Show all dates' : 'Calendar'),
                      ),
                    ),
                  ],
                ),
                if (_calendar)
                  CalendarDatePicker(
                    initialDate: _day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                    onDateChanged: (day) {
                      setState(() {
                        _day = day;
                        _posts = null;
                      });
                      _load();
                    },
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading ? null : _compose,
                  icon: const Icon(Icons.add),
                  label: Text(appTr('Create post')),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
                if (_posts!.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      appTr(
                        _calendar
                            ? 'No posts on this date.'
                            : 'No ${_status == 'all' ? 'posts' : _statuses[_status]!.toLowerCase()} yet.',
                      ),
                    ),
                  ),
                for (final post in _posts!)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        post['mediaType'] == 'video'
                            ? Icons.videocam_outlined
                            : Icons.article_outlined,
                      ),
                      title: Text('${post['caption']}'),
                      subtitle: Text(
                        appTr(
                          '${post['status']} · ${(post['platforms'] as List? ?? []).join(', ')}${_postDate(post)}',
                        ),
                      ),
                      trailing: IconButton(
                        tooltip: appTr('Delete post'),
                        onPressed: _loading ? null : () => _delete(post),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ),
                  ),
                if (_page < _lastPage)
                  OutlinedButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: Text(
                      appTr(_loading ? 'Loading…' : 'Load more posts'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _postDate(Map post) {
    final date = DateTime.tryParse(
      '${post['publishedAt'] ?? post['scheduledAt']}',
    );
    return date == null
        ? ''
        : ' · ${DateFormat.yMMMd().add_jm().format(date.toLocal())}';
  }
}

class SocialPostComposer extends StatefulWidget {
  final MobileApi api;
  final List<Map<String, dynamic>> accounts;
  const SocialPostComposer({
    super.key,
    required this.api,
    required this.accounts,
  });
  @override
  State<SocialPostComposer> createState() => _SocialPostComposerState();
}

class _SocialPostComposerState extends State<SocialPostComposer> {
  late final _service = SocialPostService(widget.api);
  final _form = GlobalKey<FormState>();
  final _caption = TextEditingController(), _media = TextEditingController();
  final _selected = <String>{};
  DateTime _scheduled = DateTime.now().add(const Duration(hours: 1));
  String _mediaType = 'image', _requestId = SocialPostService.requestId();
  String? _error;
  bool _draft = true, _saving = false, _uploading = false, _generating = false;

  Future<void> _generateCaption() async {
    final selected = _available
        .where((account) => _selected.contains('${account['id']}'))
        .firstOrNull;
    if (_caption.text.trim().isEmpty || selected == null) {
      setState(
        () => _error = 'Describe your post and choose a platform first.',
      );
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final caption = await _service.caption(
        _caption.text.trim(),
        '${selected['platform']}',
      );
      if (mounted) {
        setState(() {
          _caption.text = caption;
          _changed();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _media.dispose();
    super.dispose();
  }

  void _changed() {
    _requestId = SocialPostService.requestId();
  }

  List<Map<String, dynamic>> get _available => widget.accounts
      .where((account) => _draft || account['isConnected'] == true)
      .toList();

  Future<void> _pick(String type) async {
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final file = await ImageAttachmentPicker().pick(
        moduleId: 'social_composer',
        field: type,
        video: type == 'video',
        maxBytes: (type == 'video' ? 50 : 10) * 1024 * 1024,
      );
      if (file == null) return;
      final url = await _service.upload(file.bytes, file.name, type);
      if (mounted) {
        setState(() {
          _media.text = url;
          _mediaType = type;
          _changed();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _time() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: _scheduled.isAfter(now) ? _scheduled : now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_scheduled),
    );
    if (time != null && mounted) {
      setState(() {
        _scheduled = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        );
        _changed();
      });
    }
  }

  Future<void> _save() async {
    if (_saving ||
        _uploading ||
        _generating ||
        !_form.currentState!.validate()) {
      return;
    }
    final selected = _available
        .where((item) => _selected.contains('${item['id']}'))
        .toList();
    if (selected.isEmpty) {
      setState(() => _error = 'Choose at least one account or platform.');
      return;
    }
    if (!_draft && !_scheduled.isAfter(DateTime.now())) {
      setState(() => _error = 'Choose a future publication time.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.save({
        'caption': _caption.text.trim(),
        'status': _draft ? 'draft' : 'scheduled',
        'request_id': _requestId,
        'targets': selected
            .map(
              (account) => int.tryParse('${account['id']}') != null
                  ? {'account_id': int.parse('${account['id']}')}
                  : {'platform': account['platform']},
            )
            .toList(),
        if (!_draft) 'scheduled_at': _scheduled.toUtc().toIso8601String(),
        if (_media.text.trim().isNotEmpty) ...{
          'media_url': _media.text.trim(),
          'media_type': _mediaType,
        },
      });
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          if (error is ApiFailure &&
              [400, 402, 403, 422, 429].contains(error.status)) {
            _changed();
          }
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(title: Text(appTr('Create a post'))),
      body: SafeArea(
        child: Column(
          children: [
            if (_saving || _uploading || _generating)
              const LinearProgressIndicator(),
            Expanded(
              child: Form(
                key: _form,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    TextFormField(
                      controller: _caption,
                      enabled: !_saving && !_generating,
                      minLines: 3,
                      maxLines: 6,
                      onChanged: (_) => _changed(),
                      decoration: InputDecoration(
                        labelText: appTr('Post body'),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? appTr('Write your post.')
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving || _uploading || _generating
                            ? null
                            : _generateCaption,
                        icon: const Icon(Icons.auto_awesome),
                        label: Text(
                          appTr(
                            _generating
                                ? 'Generating caption…'
                                : 'Generate AI caption',
                          ),
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: _media,
                      enabled: !_saving && !_uploading,
                      onChanged: (_) => _changed(),
                      decoration: InputDecoration(
                        labelText: appTr('Media URL (optional)'),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final url = Uri.tryParse(value.trim());
                        return url != null &&
                                url.scheme == appTr('https') &&
                                url.host.isNotEmpty &&
                                url.userInfo.isEmpty
                            ? null
                            : appTr('Use a valid HTTPS media URL.');
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      key: ValueKey(_mediaType),
                      initialValue: _mediaType,
                      decoration: InputDecoration(
                        labelText: appTr('Media type'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'image',
                          child: Text(appTr('Image')),
                        ),
                        DropdownMenuItem(
                          value: 'video',
                          child: Text(appTr('Video')),
                        ),
                      ],
                      onChanged: _saving || _uploading
                          ? null
                          : (value) => setState(() {
                              _mediaType = value!;
                              _changed();
                            }),
                    ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: _saving || _uploading
                              ? null
                              : () => _pick('image'),
                          icon: const Icon(Icons.image_outlined),
                          label: Text(appTr('Attach image')),
                        ),
                        TextButton.icon(
                          onPressed: _saving || _uploading
                              ? null
                              : () => _pick('video'),
                          icon: const Icon(Icons.video_library_outlined),
                          label: Text(appTr('Attach video')),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(appTr('Save as draft')),
                      value: _draft,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() {
                              _draft = value;
                              _selected.removeWhere(
                                (id) => !_available.any(
                                  (account) => '${account['id']}' == id,
                                ),
                              );
                              _changed();
                            }),
                    ),
                    if (!_draft)
                      OutlinedButton.icon(
                        onPressed: _saving ? null : _time,
                        icon: const Icon(Icons.schedule),
                        label: Text(
                          appTr("Publish: :value", {
                            "value": DateFormat.yMMMd().add_jm().format(
                              _scheduled,
                            ),
                          }),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      appTr(
                        _draft
                            ? 'Choose platforms or accounts'
                            : 'Choose connected accounts',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_available.isEmpty)
                      Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          appTr(
                            'Connect an account before scheduling. You can still save a draft.',
                          ),
                        ),
                      ),
                    for (final account in _available)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${account['displayName']} ${account['handle'] ?? ''}',
                        ),
                        subtitle: account['isConnected'] == true
                            ? null
                            : Text(
                                appTr('Draft only · connect before scheduling'),
                              ),
                        value: _selected.contains('${account['id']}'),
                        onChanged: _saving
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  _selected.add('${account['id']}');
                                } else {
                                  _selected.remove('${account['id']}');
                                }
                                _changed();
                              }),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          appTr(_error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || _uploading || _generating
                      ? null
                      : _save,
                  icon: const Icon(Icons.check),
                  label: Text(
                    appTr(
                      _saving
                          ? 'Saving…'
                          : _draft
                          ? 'Save draft'
                          : 'Schedule post',
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
