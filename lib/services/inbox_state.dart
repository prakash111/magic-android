import 'package:flutter/foundation.dart';

int inboxNumber(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed < 0) {
    throw const FormatException('Invalid inbox count');
  }
  return parsed;
}

bool inboxFlag(Object? value) => value == true || value == 1 || value == '1';

typedef InboxFetch = ({int revision, int sequence});

@immutable
class InboxCounts {
  final int telegram,
      whatsapp,
      messenger,
      instagram,
      web,
      needsReply,
      chatsTotal;
  const InboxCounts({
    required this.telegram,
    required this.whatsapp,
    this.messenger = 0,
    this.instagram = 0,
    this.web = 0,
    required this.needsReply,
    required this.chatsTotal,
  });
  int get all => telegram + whatsapp + messenger + instagram + web;
  factory InboxCounts.fromJson(Map data) {
    final counts = InboxCounts(
      telegram: inboxNumber(data['telegram']),
      whatsapp: inboxNumber(data['whatsapp']),
      messenger: inboxNumber(data['messenger'] ?? 0),
      instagram: inboxNumber(data['instagram'] ?? 0),
      web: inboxNumber(data['web'] ?? 0),
      needsReply: inboxNumber(data['needs_reply']),
      chatsTotal: inboxNumber(data['chats_total']),
    );
    if (inboxNumber(data['all']) != counts.all) {
      throw const FormatException('Inbox totals do not match');
    }
    return counts;
  }
  factory InboxCounts.fromChats(Iterable<Map<String, dynamic>> chats) {
    var telegram = 0,
        whatsapp = 0,
        messenger = 0,
        instagram = 0,
        web = 0,
        needsReply = 0,
        total = 0;
    final seen = <String>{};
    for (final chat in chats) {
      if (!seen.add(InboxState.chatKey(chat))) continue;
      total++;
      if (inboxFlag(chat['needs_reply'])) needsReply++;
      if (inboxFlag(chat['muted'])) continue;
      final unread = inboxNumber(
        chat['unread'] ?? chat['unread_count'] ?? chat['unreadCount'],
      );
      if (chat['network'] == 'tg') telegram += unread;
      if (chat['network'] == 'wa') whatsapp += unread;
      if (chat['network'] == 'ms') messenger += unread;
      if (chat['network'] == 'ig') instagram += unread;
      if (chat['network'] == 'wb') web += unread;
    }
    return InboxCounts(
      telegram: telegram,
      whatsapp: whatsapp,
      messenger: messenger,
      instagram: instagram,
      web: web,
      needsReply: needsReply,
      chatsTotal: total,
    );
  }
  Map<String, int> toJson() => {
    'all': all,
    'telegram': telegram,
    'whatsapp': whatsapp,
    'messenger': messenger,
    'instagram': instagram,
    'web': web,
    'needs_reply': needsReply,
    'chats_total': chatsTotal,
  };
  int network(String value) => switch (value) {
    'tg' => telegram,
    'wa' => whatsapp,
    'ms' => messenger,
    'ig' => instagram,
    'wb' => web,
    _ => all,
  };
  static String badge(int value, {bool cap = false}) =>
      cap && value > 99 ? '99+' : '$value';
}

class InboxState extends ChangeNotifier {
  final Map<String, Map<String, dynamic>> _known = {};
  List<String> _visible = [];
  InboxCounts? counts;
  String? countsError, cursor;
  int _revision = 0, _sequence = 0, _applied = 0;
  int refreshSignal = 0;
  final Set<String> _incomingIds = {};
  int _inboxViews = 0;
  bool get inboxVisible => _inboxViews > 0;
  void attachInbox() => _inboxViews++;
  void detachInbox() => _inboxViews = (_inboxViews - 1).clamp(0, 1000);
  bool get countsLoading => counts == null && countsError == null;
  List<Map<String, dynamic>> get chats => [
    for (final key in _visible)
      if (_known[key] != null) _known[key]!,
  ];
  static String chatKey(Map chat) =>
      '${chat['network']}:${chat['remote_id'] ?? chat['remote_chat_id'] ?? chat['id']}';
  Map<String, dynamic>? chatById(int id) =>
      _known.values.where((chat) => '${chat['id']}' == '$id').firstOrNull;
  InboxFetch beginFetch() => (revision: _revision, sequence: ++_sequence);
  bool _accept(InboxFetch fetch) =>
      fetch.revision == _revision && fetch.sequence >= _applied;
  Map<String, dynamic> _normalize(Map raw) => {
    ...Map<String, dynamic>.from(raw),
    'unread': inboxNumber(
      raw['unread'] ?? raw['unread_count'] ?? raw['unreadCount'],
    ),
    'muted': inboxFlag(raw['muted']),
    'needs_reply': inboxFlag(raw['needs_reply']),
    'is_group': inboxFlag(raw['is_group']),
  };

  bool applyPage(Map result, InboxFetch fetch, {bool append = false}) {
    if (!_accept(fetch)) return false;
    final meta = result['meta'];
    if (meta is! Map) {
      throw const FormatException(
        'Inbox totals are unavailable. Retry to synchronize.',
      );
    }
    final nextCounts = InboxCounts.fromJson(meta);
    final rows = (result['data'] as List)
        .whereType<Map>()
        .map(_normalize)
        .toList();
    final visible = append ? [..._visible] : <String>[];
    for (final row in rows) {
      final key = chatKey(row);
      _known[key] = row;
      if (!visible.contains(key)) visible.add(key);
    }
    _visible = visible;
    cursor = result['next_cursor'] as String?;
    counts = nextCounts;
    countsError = null;
    _applied = fetch.sequence;
    notifyListeners();
    return true;
  }

  bool applyCounts(Map data, InboxFetch fetch) {
    if (!_accept(fetch)) return false;
    counts = InboxCounts.fromJson(data);
    countsError = null;
    _applied = fetch.sequence;
    notifyListeners();
    return true;
  }

  void applyThread(Map data, InboxFetch fetch) {
    if (!_accept(fetch) || data['meta'] is! Map || data['chat'] is! Map) return;
    final nextCounts = InboxCounts.fromJson(data['meta'] as Map);
    final row = _normalize(data['chat'] as Map);
    _known[chatKey(row)] = row;
    counts = nextCounts;
    countsError = null;
    _applied = fetch.sequence;
    notifyListeners();
  }

  void rememberChat(Map<String, dynamic> row) {
    _known.putIfAbsent(chatKey(row), () => _normalize(row));
  }

  void optimisticPatch(int id, Map<String, dynamic> patch) {
    final old = chatById(id);
    if (old == null) return;
    final next = _normalize({...old, ...patch});
    if (next['unread'] == old['unread'] &&
        next['muted'] == old['muted'] &&
        next['needs_reply'] == old['needs_reply']) {
      return;
    }
    _known[chatKey(old)] = next;
    final previous = counts;
    if (previous != null) {
      final delta =
          (next['muted'] == true ? 0 : next['unread'] as int) -
          (old['muted'] == true ? 0 : old['unread'] as int);
      counts = InboxCounts(
        telegram: (previous.telegram + (old['network'] == 'tg' ? delta : 0))
            .clamp(0, 9007199254740991),
        whatsapp: (previous.whatsapp + (old['network'] == 'wa' ? delta : 0))
            .clamp(0, 9007199254740991),
        messenger: (previous.messenger + (old['network'] == 'ms' ? delta : 0))
            .clamp(0, 9007199254740991),
        instagram: (previous.instagram + (old['network'] == 'ig' ? delta : 0))
            .clamp(0, 9007199254740991),
        web: (previous.web + (old['network'] == 'wb' ? delta : 0)).clamp(
          0,
          9007199254740991,
        ),
        needsReply:
            (previous.needsReply +
                    (next['needs_reply'] == true ? 1 : 0) -
                    (old['needs_reply'] == true ? 1 : 0))
                .clamp(0, 9007199254740991),
        chatsTotal: previous.chatsTotal,
      );
    }
    _revision++;
    notifyListeners();
  }

  void markRead(int id) =>
      optimisticPatch(id, {'unread': 0, 'needs_reply': false});

  bool removeChat(int id) {
    final chat = chatById(id);
    if (chat == null) return false;
    final key = chatKey(chat);
    _known.remove(key);
    _visible.remove(key);
    final previous = counts;
    if (previous != null) {
      final unread = chat['muted'] == true ? 0 : chat['unread'] as int;
      counts = InboxCounts(
        telegram: (previous.telegram - (chat['network'] == 'tg' ? unread : 0))
            .clamp(0, 9007199254740991),
        whatsapp: (previous.whatsapp - (chat['network'] == 'wa' ? unread : 0))
            .clamp(0, 9007199254740991),
        messenger: (previous.messenger - (chat['network'] == 'ms' ? unread : 0))
            .clamp(0, 9007199254740991),
        instagram: (previous.instagram - (chat['network'] == 'ig' ? unread : 0))
            .clamp(0, 9007199254740991),
        web: (previous.web - (chat['network'] == 'wb' ? unread : 0))
            .clamp(0, 9007199254740991),
        needsReply: (previous.needsReply - (chat['needs_reply'] == true ? 1 : 0))
            .clamp(0, 9007199254740991),
        chatsTotal: (previous.chatsTotal - 1).clamp(0, 9007199254740991),
      );
    }
    _revision++;
    notifyListeners();
    return true;
  }

  bool incoming(int chatId, {required Object messageId}) {
    final old = chatById(chatId);
    final event = '$chatId:$messageId';
    if (old == null ||
        _incomingIds.contains(event) ||
        '${old['last_message_id']}' == '$messageId') {
      return false;
    }
    _incomingIds.add(event);
    if (_incomingIds.length > 512) _incomingIds.remove(_incomingIds.first);
    optimisticPatch(chatId, {
      'unread': (old['unread'] as int) + 1,
      'needs_reply': true,
    });
    chatById(chatId)!['last_message_id'] = messageId;
    return true;
  }

  void failed(Object error, {InboxFetch? fetch}) {
    if (fetch != null && !_accept(fetch)) return;
    countsError = error.toString();
    notifyListeners();
  }

  void requestRefresh() {
    _revision++;
    refreshSignal++;
    notifyListeners();
  }

  Map<String, dynamic> snapshot() => {
    'meta': counts?.toJson(),
    'data': chats,
    'next_cursor': cursor,
  };
  void restore(Map data) {
    if (counts != null || data['meta'] is! Map) return;
    applyPage(data, beginFetch());
  }

  void reset() {
    _known.clear();
    _incomingIds.clear();
    _visible = [];
    counts = null;
    countsError = null;
    cursor = null;
    _revision++;
    notifyListeners();
  }
}
