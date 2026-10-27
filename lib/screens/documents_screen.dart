import '../services/app_localizations.dart';

import 'package:flutter/material.dart';

import '../services/document_service.dart';
import '../services/mobile_api.dart';
import '../theme/app_colors.dart';
import '../widgets/chat_response.dart';
import '../widgets/document_actions.dart';

class DocumentsScreen extends StatefulWidget {
  final MobileApi api;
  final String? templateId;
  final int refreshVersion;
  final ValueChanged<int>? onCountChanged;
  final ValueChanged<MobileDocument>? onDocumentUpdated;
  final ValueChanged<int>? onDocumentDeleted;
  const DocumentsScreen({
    super.key,
    required this.api,
    this.templateId,
    this.refreshVersion = 0,
    this.onCountChanged,
    this.onDocumentUpdated,
    this.onDocumentDeleted,
  });
  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late final service = DocumentService(widget.api);
  List<MobileDocument> documents = [];
  bool loading = true;
  bool loadingMore = false;
  bool mutating = false;
  int page = 1;
  int lastPage = 1;
  String? error;
  int loadEpoch = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(covariant DocumentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.templateId != widget.templateId ||
        oldWidget.refreshVersion != widget.refreshVersion) {
      load();
    }
  }

  Future<void> load({bool more = false}) async {
    if (more && loadingMore) return;
    final epoch = ++loadEpoch;
    setState(() {
      if (more) {
        loadingMore = true;
      } else {
        loading = documents.isEmpty;
      }
      error = null;
    });
    try {
      final result = await service.list(
        page: more ? page + 1 : 1,
        templateId: widget.templateId,
      );
      if (mounted && epoch == loadEpoch) {
        setState(() {
          documents = more
              ? [...documents, ...result.documents]
              : result.documents;
          page = more ? page + 1 : 1;
          lastPage = result.lastPage;
        });
        widget.onCountChanged?.call(result.total);
      }
    } catch (failure) {
      if (mounted && epoch == loadEpoch) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted && epoch == loadEpoch) {
        setState(() {
          loading = false;
          loadingMore = false;
        });
      }
    }
  }

  Future<void> action(MobileDocument document, String action) async {
    if (action == 'share') {
      await shareDocumentText(context, document.content);
      return;
    }
    if (action == 'edit') {
      MobileDocument? saved;
      final edit = await editDocumentText(
        context,
        title: document.title,
        content: document.content,
        api: widget.api,
        documentId: document.id,
        onSave: (edit) async {
          saved = await service.save(
            id: document.id,
            title: edit.title,
            content: edit.content,
            revision: document.revision,
            update: true,
          );
        },
      );
      if (edit == null || !mounted || saved == null) return;
      widget.onDocumentUpdated?.call(saved!);
      await load();
      if (mounted) documentNotice(context, 'Document updated.');
    }
    if (action == 'delete' && mounted) {
      if (!await confirmDocumentDelete(context) || !mounted) return;
      setState(() => mutating = true);
      try {
        await service.delete(document.id);
        if (mounted) widget.onDocumentDeleted?.call(document.id);
        await load();
        if (mounted) documentNotice(context, 'Document deleted.');
      } catch (failure) {
        if (mounted) documentNotice(context, failure.toString());
      } finally {
        if (mounted) setState(() => mutating = false);
      }
    }
  }

  Future<void> open(MobileDocument document) async {
    await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 760),
      backgroundColor: AppColors.of(context).surface,
      builder: (localizationContext) {
        AppLocalizations.watch(localizationContext);
        return _DocumentDetail(
          api: widget.api,
          initial: document,
          onUpdated: widget.onDocumentUpdated,
          onDeleted: widget.onDocumentDeleted,
        );
      },
    );
    if (mounted) await load();
  }

  Widget _menu(MobileDocument document) => PopupMenuButton<String>(
    tooltip: appTr("Options for :value", {"value": document.title}),
    enabled: !mutating,
    onSelected: (value) => action(document, value),
    itemBuilder: (localizationContext) {
      AppLocalizations.watch(localizationContext);
      return [
        PopupMenuItem(
          value: 'share',
          child: ListTile(
            leading: Icon(Icons.share_outlined),
            title: Text(appTr('Share')),
          ),
        ),
        if (document.editable)
          PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text(appTr('Edit')),
            ),
          ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text(appTr('Delete')),
          ),
        ),
      ];
    },
  );

  Widget _historyCard(MobileDocument document) {
    final colors = AppColors.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: mutating ? null : () => open(document),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.input,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        generationTimestamp(document.createdAt),
                        style: TextStyle(color: colors.muted, fontSize: 12),
                      ),
                    ),
                  ),
                ),
                _menu(document),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              document.promptPreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.text, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              document.responsePreview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    final colors = AppColors.of(context);
    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        primary: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  appTr(
                    widget.templateId == null
                        ? 'My documents'
                        : 'Generation history',
                  ),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              IconButton(
                tooltip: appTr('Refresh documents'),
                onPressed: loading || mutating ? null : load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (mutating) const LinearProgressIndicator(),
          if (loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!loading && error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 36),
                    const SizedBox(height: 12),
                    Text(appTr(error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () =>
                          load(more: documents.isNotEmpty && page < lastPage),
                      child: Text(appTr('Retry')),
                    ),
                  ],
                ),
              ),
            ),
          if (!loading && error == null && documents.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      color: colors.primary,
                      size: 44,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      appTr(
                        widget.templateId == null
                            ? 'No saved documents yet'
                            : 'No generation history yet',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.templateId == null
                          ? 'Generate content in Explore to create your first document.'
                          : 'Generate your first result to see it here.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: load,
                      icon: const Icon(Icons.refresh),
                      label: Text(appTr('Refresh')),
                    ),
                  ],
                ),
              ),
            ),
          for (final document in documents)
            Card(
              color: colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: colors.outline),
              ),
              child: widget.templateId != null
                  ? _historyCard(document)
                  : ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: colors.input,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          document.type == 'image'
                              ? Icons.image_outlined
                              : document.type == 'audio'
                              ? Icons.audio_file_outlined
                              : Icons.description_outlined,
                          color: colors.primary,
                        ),
                      ),
                      title: Text(
                        document.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        documentTimestamp(document.createdAt),
                        style: TextStyle(color: colors.muted),
                      ),
                      onTap: mutating ? null : () => open(document),
                      trailing: _menu(document),
                    ),
            ),
          if (page < lastPage)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: OutlinedButton.icon(
                onPressed: loadingMore ? null : () => load(more: true),
                icon: const Icon(Icons.expand_more),
                label: Text(appTr(loadingMore ? 'Loading…' : 'Load more')),
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentDetail extends StatefulWidget {
  final MobileApi api;
  final MobileDocument initial;
  final ValueChanged<MobileDocument>? onUpdated;
  final ValueChanged<int>? onDeleted;
  const _DocumentDetail({
    required this.api,
    required this.initial,
    this.onUpdated,
    this.onDeleted,
  });
  @override
  State<_DocumentDetail> createState() => _DocumentDetailState();
}

class _DocumentDetailState extends State<_DocumentDetail> {
  late MobileDocument document = widget.initial;
  late final service = DocumentService(widget.api);
  bool loading = true;
  bool busy = false;
  bool changed = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final fresh = await service.get(document.id);
      if (mounted) setState(() => document = fresh);
    } catch (failure) {
      if (mounted) setState(() => error = failure.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit({String? aiAction}) async {
    MobileDocument? saved;
    final result = await editDocumentText(
      context,
      title: document.title,
      content: document.content,
      api: widget.api,
      documentId: document.id,
      initialAiAction: aiAction,
      onSave: (edit) async {
        saved = await service.save(
          id: document.id,
          title: edit.title,
          content: edit.content,
          revision: document.revision,
          update: true,
        );
      },
    );
    if (result == null || !mounted || saved == null) return;
    setState(() {
      document = saved!;
      changed = true;
    });
    widget.onUpdated?.call(saved!);
  }

  Future<void> delete() async {
    if (!await confirmDocumentDelete(context) || !mounted) return;
    setState(() => busy = true);
    try {
      await service.delete(document.id);
      if (mounted) {
        widget.onDeleted?.call(document.id);
        Navigator.pop(context, true);
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          busy = false;
          error = failure.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);
    return PopScope(
      canPop: !busy,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .9,
          child: ScaffoldMessenger(
            child: Builder(
              builder: (context) {
                AppLocalizations.watch(context);
                return Scaffold(
                  backgroundColor: AppColors.of(context).surface,
                  body: ListView(
                    primary: false,
                    padding: const EdgeInsets.all(20),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              document.title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: appTr('Close document'),
                            onPressed: busy
                                ? null
                                : () => Navigator.pop(context, changed),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        documentTimestamp(document.createdAt),
                        style: TextStyle(color: AppColors.of(context).muted),
                      ),
                      const SizedBox(height: 16),
                      if (loading || busy) const LinearProgressIndicator(),
                      if (error != null) ...[
                        Text(
                          appTr(error!),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        TextButton(
                          onPressed: busy ? null : load,
                          child: Text(appTr('Retry')),
                        ),
                      ],
                      if (!loading) ...[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => shareDocumentText(
                                      context,
                                      document.content,
                                    ),
                              icon: const Icon(Icons.share_outlined),
                              label: Text(appTr('Share')),
                            ),
                            if (document.editable)
                              FilledButton.icon(
                                onPressed: busy ? null : edit,
                                icon: const Icon(Icons.edit_outlined),
                                label: Text(appTr('Edit')),
                              ),
                            OutlinedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => copyDocumentText(
                                      context,
                                      document.content,
                                    ),
                              icon: const Icon(Icons.copy_outlined),
                              label: Text(appTr('Copy')),
                            ),
                            OutlinedButton.icon(
                              onPressed: busy ? null : delete,
                              icon: const Icon(Icons.delete_outline),
                              label: Text(appTr('Delete')),
                            ),
                          ],
                        ),
                        if (document.editable) ...[
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => edit(aiAction: 'correct'),
                                icon: const Icon(Icons.spellcheck),
                                label: Text(appTr('AI Correct')),
                              ),
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => edit(aiAction: 'refine'),
                                icon: const Icon(Icons.auto_fix_high),
                                label: Text(appTr('Make changes / Refine')),
                              ),
                              OutlinedButton.icon(
                                onPressed: busy
                                    ? null
                                    : () => edit(aiAction: 'extend'),
                                icon: const Icon(Icons.playlist_add),
                                label: Text(appTr('Addition / Extend')),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 20),
                        if (document.content.isEmpty)
                          Text(appTr('This document has no text content yet.'))
                        else
                          ChatResponse(
                            text: document.content,
                            showActions: false,
                          ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
