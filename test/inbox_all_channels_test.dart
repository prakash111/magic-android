import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/services/inbox_state.dart';

void main() {
  test('all chatbot networks contribute to totals and optimistic reads', () {
    final rows = [
      for (final network in ['tg', 'wa', 'ms', 'ig', 'wb'])
        <String, dynamic>{
          'id': network.hashCode,
          'network': network,
          'remote_id': 'visitor',
          'unread': 2,
          'needs_reply': true,
          'muted': false,
        },
    ];
    final counts = InboxCounts.fromChats(rows);
    expect(counts.all, 10);
    expect(counts.network('ms'), 2);
    expect(counts.network('ig'), 2);
    expect(counts.network('wb'), 2);
    expect(InboxCounts.fromJson(counts.toJson()).all, 10);
  });
}
