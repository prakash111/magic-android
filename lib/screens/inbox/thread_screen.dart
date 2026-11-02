import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/app_localizations.dart';
import '../../services/inbox_service.dart';
import '../../services/mobile_api.dart';
import '../../services/extension_workflow_service.dart';
import '../../services/image_attachment_picker.dart';
import '../../services/ai_model_selection.dart';
import '../../services/social_post_service.dart';
import '../../widgets/avatar_with_badge.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/attachment_tray.dart';
import '../../widgets/ai_review_card.dart';
import 'widgets.dart';

class ThreadScreen extends StatefulWidget {
  final InboxService service;
  final Map<String, dynamic> chat;
  const ThreadScreen({super.key, required this.service, required this.chat});
  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen>
    with WidgetsBindingObserver {
  final input = TextEditingController(), scroll = ScrollController();
  Timer? poll;
  bool loading = true,
      busy = false,
      active = true,
      fetching = false,
      smart = true;
  String? error, aiError, model, cursor;
  String mode = 'off';
  List<Map<String, dynamic>> messages = [];
  List<String> suggestions = [];
  List<WorkflowFile> files = [];
  Map<String, dynamic>? reply, review;
  double? progress;
  int? suggestedFor;
  String _clientId = SocialPostService.requestId();
  int get id => widget.chat['id'] as int;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service.state.rememberChat(widget.chat);
    widget.service.state.addListener(stateChanged);
    unawaited(widget.service.markRead(id).catchError((_) {}));
    load();
    settings();
    poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (active && (ModalRoute.of(context)?.isCurrent ?? true)) {
        load(silent: true);
      }
    });
  }

  void stateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> settings() async {
    try {
      final cached = await widget.service.cached('prefs');
      if (mounted && cached is Map) {
        setState(() {
          mode = '${cached['ai_fix_mode'] ?? 'off'}';
          smart = cached['smart_replies'] != false;
        });
      }
      final data = await widget.service.prefs();
      if (mounted) {
        setState(() {
          mode = '${data['ai_fix_mode'] ?? 'off'}';
          smart = data['smart_replies'] != false;
        });
      }
      final selection = AiModelSelection(widget.service.api);
      model = await selection.resolve(
        await selection.models().timeout(const Duration(seconds: 9)),
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active) load(silent: true);
  }

  Future<void> load({bool silent = false, bool more = false}) async {
    if (fetching) return;
    fetching = true;
    try {
      unawaited(widget.service.flush().catchError((_) {}));
      final data = await widget.service.messages(
        id,
        cursor: more ? cursor : null,
      );
      if (!mounted) return;
      final rows = (data['data'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final pending = await widget.service.outbox(id);
      if (!mounted) return;
      final atBottom =
          !scroll.hasClients ||
          scroll.position.maxScrollExtent - scroll.offset < 100;
      setState(() {
        messages = more
            ? [...rows, ...messages]
            : [
                ...rows,
                ...pending.map((e) => {...e, 'direction': 'out'}),
              ];
        cursor = data['next_cursor'] as String?;
        error = null;
        loading = false;
      });
      if (!more && atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
        });
      }
      if (active && (ModalRoute.of(context)?.isCurrent ?? true)) {
        unawaited(widget.service.markRead(id).catchError((_) {}));
      }
      final incoming = rows.where((m) => m['direction'] == 'in').lastOrNull;
      if (smart && incoming != null && incoming['id'] != suggestedFor) {
        suggestedFor = incoming['id'] as int;
        unawaited(loadSuggestions());
      }
    } catch (e) {
      final cached = await widget.service.cached('thread:$id');
      final pending = await widget.service.outbox(id);
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
          if (messages.isEmpty && cached is Map) {
            messages = (cached['data'] as List? ?? [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
          final ids = messages.map((e) => e['client_id']).toSet();
          messages.addAll(
            pending
                .where((e) => !ids.contains(e['client_id']))
                .map((e) => {...e, 'direction': 'out'}),
          );
        });
      }
    } finally {
      fetching = false;
    }
  }

  Future<void> loadSuggestions() async {
    try {
      final items = await widget.service.replies(id, model: model);
      if (mounted) setState(() => suggestions = items);
    } catch (e) {
      if (mounted) setState(() => aiError = e.toString());
    }
  }

  Future<void> chooseAttachment() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Wrap(
        children: [
          for (final item in [
            ('photo', Icons.photo_outlined, 'Photo'),
            ('camera', Icons.camera_alt_outlined, 'Camera'),
            ('video', Icons.videocam_outlined, 'Video'),
            ('document', Icons.description_outlined, 'Document'),
          ])
            ListTile(
              leading: Icon(item.$2),
              title: Text(appTr(item.$3)),
              onTap: () => Navigator.pop(context, item.$1),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    try {
      WorkflowFile? file;
      if (choice == 'camera' || choice == 'photo') {
        final selected = await ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          requestFullMetadata: false,
        );
        if (selected != null) {
          file = await ImageAttachmentPicker.cache(
            selected,
            maxBytes: 10 * 1024 * 1024,
          );
        }
      } else {
        final result = await SecureStore.invokeMethod<Map>('pickFile', {
          'accept': choice == 'video' ? 'video/mp4,video/quicktime' : 'application/pdf,application/msword,application/vnd.openxmlformats-officedocument.wordprocessingml.document,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/zip,text/plain',
        });
        if (result != null) {
          file = WorkflowFile(
            '${result['name']}',
            List<int>.from(result['bytes'] as List),
            mimeType: result['mimeType'] as String?,
          );
        }
      }
      if (file != null && mounted) {
        if (files.length >= 10) {
          throw const ApiFailure('Choose up to 10 attachments.');
        }
        setState(() => files.add(file!));
      }
    } catch (e) {
      notice(e.toString());
    }
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(appTr(text))));
    }
  }

  Future<void> send({String? text, bool reviewed = false}) async {
    if (busy) return;
    final body = text ?? input.text;
    if (body.trim().isEmpty && files.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
      aiError = null;
    });
    final attachmentIds = <int>[];
    try {
      if (!reviewed && mode == 'ask' && body.trim().length >= 5) {
        try {
          final fixed = await widget.service.fix(
            body,
            lang: MobileApi.languageCode ?? 'en',
            model: model,
          );
          if ((fixed['changes'] as List? ?? []).isNotEmpty) {
            if (mounted) {
              setState(
                () => review = {'original': body, 'text': fixed['text']},
              );
            }
            return;
          }
        } catch (e) {
          notice(
            '${appTr('AI unavailable. Sending as typed.')} ${e.toString()}',
          );
        }
      }
      for (final file in files) {
        final uploaded = await widget.service.upload(
          file,
          progress: (value) {
            if (mounted) setState(() => progress = value);
          },
        );
        attachmentIds.add(uploaded['id'] as int);
      }
      final sentResult = await widget.service.send(
        id,
        body,
        attachments: attachmentIds,
        replyTo: reply?['id'] as int?,
        clientId: _clientId,
        mode: !reviewed && mode == 'auto' ? 'auto' : 'off',
        model: model,
        lang: MobileApi.languageCode ?? 'en',
      );
      if (sentResult['ai_fallback'] == true) {
        notice('AI unavailable. Your message was sent as typed.');
      }
      if (mounted) {
        setState(() {
          input.clear();
          _clientId = SocialPostService.requestId();
          files = [];
          reply = null;
          review = null;
          progress = null;
        });
      }
      await load(silent: true);
    } catch (e) {
      if (e is ApiFailure && e.status == 0) {
        try {
          await widget.service.queueOffline(
            id,
            body,
            replyTo: reply?['id'] as int?,
            clientId: _clientId,
            files: files,
            mode: mode == 'auto' ? 'auto' : 'off',
            model: model,
            lang: MobileApi.languageCode ?? 'en',
          );
          if (mounted) {
            input.clear();
            _clientId = SocialPostService.requestId();
            setState(() {
              reply = null;
              files = [];
              review = null;
              messages.add({
                'body': body,
                'direction': 'out',
                'status': 'offline',
                'created_at': DateTime.now().toIso8601String(),
              });
            });
            notice('Message saved offline. It will retry automatically.');
          }
        } catch (storageError) {
          if (mounted) setState(() => error = storageError.toString());
        }
      } else {
        if (mounted) setState(() => error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
        });
      }
    }
  }

  Future<void> aiSheet() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  appTr('Write with AI'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(appTr('AI uses your selected model and plan credits.')),
                if (reply != null)
                  Text(
                    '${appTr('Replying to')}: ${reply!['body']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tone in [
                      ('friendly', 'Friendly'),
                      ('professional', 'Professional'),
                      ('short', 'Short'),
                      ('translate', 'Translate'),
                      ('improve', 'Improve what I wrote'),
                    ])
                      ActionChip(
                        label: Text(
                          tone.$1 == 'translate'
                              ? appTr('Translate to :language', {
                                  'language': AppLocalizations
                                      .current
                                      .language
                                      .nativeName,
                                })
                              : appTr(tone.$2),
                        ),
                        onPressed: () => Navigator.pop(context, tone.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(appTr('AI fix before send')),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final value in ['off', 'ask', 'auto'])
                      ChoiceChip(
                        label: Text(
                          appTr(
                            value == 'off'
                                ? 'Off'
                                : value == 'ask'
                                ? 'Ask'
                                : 'Auto',
                          ),
                        ),
                        selected: mode == value,
                        onSelected: (_) async {
                          setState(() => mode = value);
                          update(() {});
                          try {
                            await widget.service.prefs(
                              values: {'ai_fix_mode': value},
                            );
                          } catch (e) {
                            notice(e.toString());
                          }
                        },
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(appTr('Show AI reply suggestions')),
                  value: smart,
                  onChanged: (value) async {
                    setState(() => smart = value);
                    update(() {});
                    try {
                      await widget.service.prefs(
                        values: {'smart_replies': value},
                      );
                      if (value) loadSuggestions();
                    } catch (e) {
                      notice(e.toString());
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => busy = true);
    try {
      final result = await widget.service.compose(
        id,
        choice,
        input.text,
        replyTo: reply?['id'] as int?,
        lang: MobileApi.languageCode ?? 'en',
        model: model,
      );
      if (mounted) setState(() => input.text = result);
    } catch (e) {
      notice(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> messageAction(
    Map<String, dynamic> message,
    String action,
  ) async {
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(text: '${message['body'] ?? ''}'));
      notice('Copied to clipboard');
      return;
    }
    setState(() => reply = message);
    if (action == 'ai') await aiSheet();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.service.state.removeListener(stateChanged);
    poll?.cancel();
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    final chat = widget.service.state.chatById(id) ?? widget.chat;
    final group = chat['is_group'] == true;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            AvatarWithBadge(
              name: '${chat['title']}',
              network: '${chat['network']}',
              url: chat['photo_url'] as String?,
              radius: 19,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${chat['title']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (group && chat['members'] != null)
                    Text(
                      appTr(':count members', {'count': chat['members']}),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: appTr('Mute notifications'),
            onPressed: () async {
              try {
                await widget.service.mute(id, chat['muted'] != true);
              } catch (e) {
                notice(e.toString());
              }
            },
            icon: Icon(
              chat['muted'] == true
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_outlined,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: loading && messages.isEmpty
                ? InboxStateView(loading: true, empty: '', retry: load)
                : messages.isEmpty
                ? InboxStateView(
                    error: error,
                    empty: 'No messages yet. Start the conversation.',
                    retry: load,
                  )
                : ListView.builder(
                    controller: scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount:
                        messages.length +
                        (cursor == null ? 0 : 1) +
                        (progress == null ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (cursor != null) {
                        if (index == 0) {
                          return TextButton(
                            onPressed: () => load(more: true),
                            child: Text(appTr('Load earlier messages')),
                          );
                        }
                        index--;
                      }
                      if (index == messages.length) {
                        return MessageBubble(
                          network: '${chat['network']}',
                          message: {
                            'direction': 'out',
                            'body': input.text,
                            'status': 'sending',
                            'upload_progress': progress,
                            'created_at': DateTime.now().toIso8601String(),
                            'attachments': files
                                .map(
                                  (file) => {
                                    'name': file.name,
                                    'size': file.bytes.length,
                                    'kind':
                                        file.mimeType?.startsWith('image/') ==
                                            true
                                        ? 'photo'
                                        : 'document',
                                  },
                                )
                                .toList(),
                          },
                        );
                      }
                      final message = messages[index];
                      final date = DateTime.tryParse('${message['created_at']}')
                          ?.toLocal();
                      final previous = index == 0
                          ? null
                          : DateTime.tryParse(
                              '${messages[index - 1]['created_at']}',
                            )?.toLocal();
                      final newDate =
                          date != null &&
                          (previous == null ||
                              DateUtils.dateOnly(date) !=
                                  DateUtils.dateOnly(previous));
                      final next = index + 1 < messages.length
                          ? messages[index + 1]
                          : null;
                      return Column(
                        children: [
                          if (newDate)
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Chip(
                                label: Text(
                                  '${date.day}/${date.month}/${date.year}',
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          MessageBubble(
                            message: message,
                            network: '${chat['network']}',
                            group: group,
                            showAvatar:
                                next == null ||
                                next['sender_remote_id'] !=
                                    message['sender_remote_id'] ||
                                next['direction'] != message['direction'],
                            onAction: (action) =>
                                messageAction(message, action),
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (error != null && messages.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      appTr(error!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(onPressed: load, child: Text(appTr('Retry'))),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: .2),
                  ),
                ),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .52,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (smart && suggestions.isNotEmpty)
                        SizedBox(
                          height: 52,
                          child: ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            scrollDirection: Axis.horizontal,
                            itemCount: suggestions.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) => ActionChip(
                              avatar: const Icon(Icons.auto_awesome, size: 14),
                              label: Text(suggestions[index]),
                              onPressed: () => setState(
                                () => input.text = suggestions[index],
                              ),
                            ),
                          ),
                        ),
                      if (reply != null)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.reply),
                          title: Text(
                            '${reply!['sender_name'] ?? appTr('Reply')}',
                            maxLines: 1,
                          ),
                          subtitle: Text(
                            '${reply!['body']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: appTr('Cancel reply'),
                            onPressed: () => setState(() => reply = null),
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      AttachmentTray(
                        files: files,
                        progress: progress,
                        onRemove: busy
                            ? null
                            : (index) => setState(() => files.removeAt(index)),
                      ),
                      if (review != null)
                        AiReviewCard(
                          original: '${review!['original']}',
                          corrected: '${review!['text']}',
                          onCorrected: () =>
                              send(text: '${review!['text']}', reviewed: true),
                          onOriginal: () => send(
                            text: '${review!['original']}',
                            reviewed: true,
                          ),
                          onEdit: () => setState(() => review = null),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton(
                              tooltip: appTr('Attach file'),
                              onPressed: busy ? null : chooseAttachment,
                              icon: const Icon(Icons.attach_file),
                            ),
                            Expanded(
                              child: TextField(
                                controller: input,
                                minLines: 1,
                                maxLines: 5,
                                maxLength: 10000,
                                enabled: !busy,
                                decoration: InputDecoration(
                                  hintText: appTr('Write a message'),
                                  counterText: '',
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: appTr('Write with AI'),
                              onPressed: busy ? null : aiSheet,
                              icon: const Icon(Icons.auto_awesome),
                            ),
                            IconButton.filled(
                              tooltip: appTr('Send'),
                              onPressed: busy ? null : send,
                              icon: busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          appTr(
                            mode == 'off'
                                ? 'AI fix is off'
                                : mode == 'ask'
                                ? 'AI checks spelling before sending'
                                : 'AI fixes mistakes automatically',
                          ),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      if (aiError != null)
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            appTr(aiError!),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
