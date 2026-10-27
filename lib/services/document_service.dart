import 'dart:convert';

import 'package:intl/intl.dart';

import 'app_localizations.dart';

import 'mobile_api.dart';

class MobileDocument {
  final Map<String, dynamic> data;
  final bool storedLocally;
  const MobileDocument(this.data, {this.storedLocally = false});

  int get id => int.tryParse('${data['id']}') ?? 0;
  bool get editable => data['editable'] != false && type == 'text';
  String get type => '${data['type'] ?? data['generator_type'] ?? 'text'}';
  String get title {
    for (final value in [
      data['title'],
      data['template_name'],
      data['ai_title'],
      data['name'],
    ]) {
      if (value is String &&
          value.trim().isNotEmpty &&
          ![
            'null',
            'undefined',
            'document',
            'untitled document',
          ].contains(value.trim().toLowerCase())) {
        return value.trim();
      }
    }
    return appTr('Untitled Document');
  }

  String get content {
    for (final value in [data['content'], data['response'], data['output']]) {
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return '';
  }

  String get promptPreview =>
      data['prompt_preview']?.toString().trim().isNotEmpty == true
      ? data['prompt_preview'].toString()
      : title;
  String get responsePreview => content
      .replaceAll(RegExp(r'[#*`]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  DateTime? get createdAt =>
      DateTime.tryParse('${data['created_at']}')?.toLocal();
  String? get revision => data['updated_at'] as String?;
}

class DocumentPage {
  final List<MobileDocument> documents;
  final int lastPage;
  final int total;
  const DocumentPage(this.documents, this.lastPage, this.total);
}

class DocumentService {
  final MobileApi api;
  DocumentService(this.api);
  static const cacheKey = 'document_snapshot_cache';

  MobileDocument _document(dynamic response) {
    final value = response is Map && response['data'] is Map
        ? response['data']
        : response;
    if (value is! Map || int.tryParse('${value['id']}') == null) {
      throw const ApiFailure('The server did not return a valid document.');
    }
    return MobileDocument(Map<String, dynamic>.from(value));
  }

  Future<DocumentPage> list({int page = 1, String? templateId}) async {
    final filter = templateId == null
        ? ''
        : '&template_id=${Uri.encodeQueryComponent(templateId)}';
    final response = await api.request(
      '/documents?page=$page&per_page=20$filter',
    );
    final rows = response is Map ? response['data'] ?? [] : response ?? [];
    if (rows is! List) {
      throw const ApiFailure('Unable to load documents. Please retry.');
    }
    final documents = rows
        .whereType<Map>()
        .map((row) => MobileDocument(Map<String, dynamic>.from(row)))
        .where((row) => row.id > 0)
        .toList();
    final last = response is Map
        ? (response['meta'] is Map
              ? response['meta']['last_page']
              : response['last_page'])
        : 1;
    final total = response is Map
        ? (response['meta'] is Map
              ? response['meta']['total']
              : response['total'])
        : null;
    return DocumentPage(
      documents,
      int.tryParse('$last') ?? 1,
      int.tryParse('$total') ?? documents.length,
    );
  }

  Future<MobileDocument> get(int id) async =>
      _document(await api.request('/documents/$id'));

  Future<MobileDocument> save({
    required int id,
    required String title,
    required String content,
    String? revision,
    bool update = false,
  }) async {
    final document = _document(
      await api.request(
        update ? '/documents/$id' : '/documents',
        method: update ? 'PUT' : 'POST',
        body: {
          if (!update) 'document_id': id,
          'title': title.trim(),
          'content': content,
          'updated_at': ?revision,
        },
      ),
    );
    var local = false;
    try {
      final cached = await snapshots();
      cached.removeWhere(
        (row) =>
            row.id == document.id ||
            row.data['user_id'] != document.data['user_id'],
      );
      cached.insert(
        0,
        MobileDocument({
          for (final key in [
            'id',
            'title',
            'content',
            'type',
            'editable',
            'user_id',
            'updated_at',
            'created_at',
            'prompt_preview',
            'template_name',
            'template_id',
          ])
            key: document.data[key],
        }),
      );
      final cachedRows = <Map<String, dynamic>>[];
      for (final row in cached.take(20)) {
        if (jsonEncode([...cachedRows, row.data]).length > 500000) break;
        cachedRows.add(row.data);
      }
      await api.store.write(cacheKey, jsonEncode(cachedRows));
      local = true;
    } catch (_) {
      // The database save remains successful if encrypted local storage fails.
    }
    return MobileDocument(document.data, storedLocally: local);
  }

  Future<void> delete(int id) async {
    await api.request('/documents/$id', method: 'DELETE');
    try {
      final cached = await snapshots();
      await api.store.write(
        cacheKey,
        jsonEncode(
          cached.where((row) => row.id != id).map((row) => row.data).toList(),
        ),
      );
    } catch (_) {
      // A local cache failure must not undo a successful server deletion.
    }
  }

  Future<List<MobileDocument>> snapshots() async {
    final value = await api.store.read(cacheKey);
    if (value == null) return [];
    final data = jsonDecode(value);
    return data is List
        ? data
              .whereType<Map>()
              .map(
                (row) => MobileDocument(
                  Map<String, dynamic>.from(row),
                  storedLocally: true,
                ),
              )
              .toList()
        : [];
  }
}

String documentTimestamp(DateTime? date, {DateTime? now}) {
  if (date == null) return appTr('Date unavailable');
  final age = (now ?? DateTime.now()).difference(date);
  if (!age.isNegative && age.inMinutes < 1) return appTr('Just now');
  if (!age.isNegative && age.inHours < 1) {
    return appTr(':count minute ago|:count minutes ago', {}, age.inMinutes);
  }
  if (!age.isNegative && age.inDays < 1) {
    return appTr(':count hour ago|:count hours ago', {}, age.inHours);
  }
  return DateFormat.yMMMd().format(date);
}

String generationTimestamp(DateTime? date) {
  if (date == null) return appTr('Date unavailable');
  final format = AppLocalizations.current.locale.languageCode == 'en'
      ? DateFormat('hh:mm a')
      : DateFormat.jm();
  return '${DateFormat.yMMMd().format(date)} • ${format.format(date)}';
}
