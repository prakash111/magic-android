import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/services/inbox_service.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/screens/inbox/inbox_screen.dart';
import 'package:magicai_mobile/widgets/magic_bottom_navigation.dart';

import 'unified_inbox_test.dart' as fixture;

List<Map<String, dynamic>> twoChats({int unread = 3}) => [
  {
    'id': 1,
    'network': 'tg',
    'remote_id': 'group-101',
    'title': 'Alpha group',
    'is_group': true,
    'unread': unread,
    'needs_reply': unread > 0,
    'muted': false,
  },
  {
    'id': 2,
    'network': 'tg',
    'remote_id': 'group-202',
    'title': 'Beta group',
    'is_group': true,
    'unread': 0,
    'needs_reply': false,
    'muted': false,
  },
];
Map<String, dynamic> page(
  List<Map<String, dynamic>> rows, {
  Map<String, int>? meta,
}) => {'data': rows, 'meta': meta ?? InboxCounts.fromChats(rows).toJson()};
InboxState stateWith(
  List<Map<String, dynamic>> rows, {
  Map<String, int>? meta,
}) {
  final state = InboxState();
  state.applyPage(page(rows, meta: meta), state.beginFetch());
  return state;
}

class CountService extends fixture.FakeInboxService {
  bool fail = false;
  Completer<Map<String, dynamic>>? blocked;
  CountService(List<Map<String, dynamic>> rows) {
    chatRows
      ..clear()
      ..addAll(rows);
  }
  @override
  Future<Map<String, dynamic>> chats({
    String network = '',
    String query = '',
    String? cursor,
    bool needsReply = false,
  }) async {
    if (fail) throw const ApiFailure('Connection unavailable');
    if (blocked != null) return blocked!.future;
    return super.chats(
      network: network,
      query: query,
      cursor: cursor,
      needsReply: needsReply,
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final fonts = Platform.environment['INBOX_FONT_DIR'];
    if (fonts == null) return;
    final loader = FontLoader('Roboto');
    for (final file in ['Roboto-Regular.ttf', 'Roboto-Bold.ttf']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(await File('$fonts/$file').readAsBytes()),
        ),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('$fonts/MaterialIcons-Regular.otf').readAsBytes(),
          ),
        ),
      );
    await icons.load();
  });
  test(
    'mixed network totals exclude muted rows and normalize numeric strings',
    () {
      final rows = twoChats();
      rows.add({
        'id': 3,
        'network': 'wa',
        'remote_id': 'wa-1',
        'unread': '104',
        'muted': '0',
        'needs_reply': '1',
      });
      rows.add({
        'id': 4,
        'network': 'tg',
        'remote_id': 'muted',
        'unread': '99',
        'muted': '1',
        'needs_reply': false,
      });
      final counts = InboxCounts.fromChats(rows);
      expect(counts.toJson(), {
        'all': 107,
        'telegram': 3,
        'whatsapp': 104,
        'messenger': 0,
        'instagram': 0,
        'web': 0,
        'needs_reply': 2,
        'chats_total': 4,
      });
      expect(
        InboxCounts.fromJson({
          'all': '107',
          'telegram': '3',
          'whatsapp': '104',
          'needs_reply': '2',
          'chats_total': '4',
        }).all,
        107,
      );
      expect(InboxCounts.badge(counts.all, cap: true), '99+');
      expect(InboxCounts.badge(99, cap: true), '99');
      expect(InboxCounts.fromChats(twoChats(unread: 0)).all, 0);
    },
  );
  test('server totals cover chats beyond the first page and remain global under filters', () {
    final state = stateWith(
      [twoChats().first],
      meta: {
        'all': 143,
        'telegram': 140,
        'whatsapp': 3,
        'needs_reply': 4,
        'chats_total': 37,
      },
    );
    expect(state.chats.length, 1);
    expect(state.counts!.all, 143);
    state.markRead(1);
    expect(state.counts!.all, 140);
    expect(state.counts!.needsReply, 3);
    state.applyPage(
      page(
        [],
        meta: {
          'all': 140,
          'telegram': 137,
          'whatsapp': 3,
          'needs_reply': 3,
          'chats_total': 37,
        },
      ),
      state.beginFetch(),
    );
    expect(state.chats, isEmpty);
    expect(state.counts!.all, 140);
  });
  test(
    'optimistic read and mute preserve row unread and correct global sums',
    () {
      final rows = twoChats();
      rows[1]['network'] = 'wa';
      rows[1]['unread'] = 2;
      final state = stateWith(rows);
      state.optimisticPatch(1, {'muted': true});
      expect(state.counts!.all, 2);
      expect(state.chatById(1)!['unread'], 3);
      state.optimisticPatch(1, {'muted': false});
      expect(state.counts!.all, 5);
      state.markRead(1);
      expect(state.counts!.all, 2);
      expect(state.counts!.telegram, 0);
      expect(state.counts!.needsReply, 0);
    },
  );
  test(
    'old requests cannot undo optimistic reads or later server responses',
    () {
      final state = stateWith(twoChats());
      final old = state.beginFetch();
      state.markRead(1);
      expect(state.applyPage(page(twoChats()), old), isFalse);
      expect(state.counts!.all, 0);
      final older = state.beginFetch();
      final newest = state.beginFetch();
      state.applyCounts({
        'all': 4,
        'telegram': 4,
        'whatsapp': 0,
        'needs_reply': 1,
        'chats_total': 2,
      }, newest);
      expect(
        state.applyCounts({
          'all': 3,
          'telegram': 3,
          'whatsapp': 0,
          'needs_reply': 1,
          'chats_total': 2,
        }, older),
        isFalse,
      );
      expect(state.counts!.all, 4);
    },
  );
  test('incoming events increment once and never derive missing page totals from zero', () {
    final state = stateWith(twoChats(unread: 0));
    expect(state.incoming(1, messageId: 'new-1'), isTrue);
    expect(state.counts!.all, 1);
    expect(state.counts!.needsReply, 1);
    expect(state.incoming(1, messageId: 'new-1'), isFalse);
    expect(state.counts!.all, 1);
    expect(state.incoming(1, messageId: 'new-2'), isTrue);
    expect(state.incoming(1, messageId: 'new-1'), isFalse);
    expect(state.counts!.all, 2);
    expect(state.incoming(99, messageId: 'unloaded'), isFalse);
    expect(state.counts!.all, 2);
  });
  test('remote identity deduplicates rows while equal titles with distinct ids remain', () {
    final rows = twoChats();
    rows[1]['title'] = 'Alpha group';
    final state = stateWith([
      rows[0],
      {...rows[0], 'id': 88},
      rows[1],
    ]);
    expect(state.chats.length, 2);
    expect(state.chats.map(InboxState.chatKey).toSet().length, 2);
  });
  test(
    'invalid or missing metadata never turns last known totals into zero',
    () {
      final state = stateWith(twoChats());
      expect(
        () => state.applyPage({'data': twoChats()}, state.beginFetch()),
        throwsFormatException,
      );
      state.failed('Offline');
      expect(state.counts!.all, 3);
      expect(state.countsError, 'Offline');
      expect(
        () => state.applyCounts({'all': 'not-a-number'}, state.beginFetch()),
        throwsFormatException,
      );
      expect(state.counts!.all, 3);
    },
  );
  test('persisted aggregate counts survive a new service instance', () async {
    final service = CountService(twoChats());
    await service.loadChats();
    await service.persistState();
    final restarted = InboxService(service.api);
    await restarted.restoreState();
    expect(restarted.state.counts!.all, 3);
    expect(restarted.state.chats.length, 2);
    await service.markRead(1);
    await service.persistState();
    final reopened = InboxService(service.api);
    await reopened.restoreState();
    expect(reopened.state.counts!.all, 0);
    expect(reopened.state.counts!.needsReply, 0);
  });
  testWidgets('zero badges are hidden with plain labels and no check icon', (
    tester,
  ) async {
    await fixture.mount(
      tester,
      InboxScreen(service: CountService(twoChats(unread: 0))),
    );
    for (final key in ['', 'tg', 'wa']) {
      expect(find.byKey(ValueKey('inbox-tab-badge-$key')), findsNothing);
    }
    for (final label in ['All', 'Telegram', 'WhatsApp']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.showCheckmark == false),
      isTrue,
    );
    expect(find.text('AI inbox'), findsNothing);
    expect(find.text('0'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('tab badges and singular banner match two Telegram chats', (
    tester,
  ) async {
    await fixture.mount(tester, InboxScreen(service: CountService(twoChats())));
    for (final key in ['', 'tg']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('inbox-tab-badge-$key')),
          matching: find.text('3'),
        ),
        findsOneWidget,
      );
    }
    expect(find.byKey(const ValueKey('inbox-tab-badge-wa')), findsNothing);
    expect(find.text('1 chat is waiting for your reply'), findsOneWidget);
    expect(find.textContaining('group-101'), findsOneWidget);
    expect(find.textContaining('group-202'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('banner uses plural when several chats need replies', (
    tester,
  ) async {
    final rows = twoChats();
    rows[1]['needs_reply'] = true;
    rows.add({
      'id': 3,
      'remote_id': 'third',
      'network': 'wa',
      'title': 'Third',
      'unread': 0,
      'muted': true,
      'needs_reply': true,
    });
    await fixture.mount(tester, InboxScreen(service: CountService(rows)));
    expect(find.text('3 chats are waiting for your reply'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'opening an unread chat immediately lowers totals and hides the banner',
    (tester) async {
      final service = CountService(twoChats());
      await fixture.mount(tester, InboxScreen(service: service));
      await tester.tap(find.text('Alpha group'));
      await tester.pump();
      expect(service.state.counts!.all, 0);
      expect(service.state.counts!.needsReply, 0);
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-tab-badge-')), findsNothing);
      expect(find.text('AI inbox'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('new push messages update badges without waiting for the poll', (
    tester,
  ) async {
    final service = CountService(twoChats(unread: 0));
    await fixture.mount(tester, InboxScreen(service: service));
    service.chatRows[0].addAll({
      'unread': 1,
      'needs_reply': true,
      'last_message_id': 'new-push',
    });
    await service.onPush({'chat_id': 1, 'message_id': 'new-push'});
    await tester.pumpAndSettle();
    expect(service.state.counts!.all, 1);
    expect(find.byKey(const ValueKey('inbox-tab-badge-')), findsOneWidget);
    expect(find.text('1 chat is waiting for your reply'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('loading badges use placeholders instead of zero', (
    tester,
  ) async {
    final service = CountService(twoChats())
      ..blocked = Completer<Map<String, dynamic>>();
    await fixture.mount(tester, InboxScreen(service: service));
    expect(find.byKey(const ValueKey('inbox-count-skeleton-')), findsOneWidget);
    expect(find.text('0'), findsNothing);
    service.blocked!.complete(page(twoChats()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inbox-count-skeleton-')), findsNothing);
    expect(service.state.counts!.all, 3);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'refresh failure preserves badges and offers a small retry hint',
    (tester) async {
      final service = CountService(twoChats());
      await fixture.mount(tester, InboxScreen(service: service));
      service.fail = true;
      await tester.tap(find.byTooltip('Refresh'));
      await tester.pumpAndSettle();
      expect(service.state.counts!.all, 3);
      expect(find.byKey(const ValueKey('inbox-tab-badge-')), findsOneWidget);
      expect(
        find.text('Counts could not refresh. Showing last known counts.'),
        findsOneWidget,
      );
      expect(find.text('0'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'mute excludes totals immediately while its chat retains its own badge',
    (tester) async {
      final service = CountService(twoChats());
      await fixture.mount(tester, InboxScreen(service: service));
      await service.mute(1, true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('inbox-tab-badge-')), findsNothing);
      expect(find.text('3'), findsOneWidget);
      await service.mute(1, false);
      await tester.pumpAndSettle();
      expect(service.state.counts!.all, 3);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'bottom navigation caps display at 99 plus using the shared state',
    (tester) async {
      final state = stateWith(twoChats(unread: 130));
      await fixture.mount(
        tester,
        Scaffold(
          bottomNavigationBar: MagicBottomNavigation(
            items: const [
              {'component': 'inbox', 'label': 'Inbox'},
              {'component': 'account', 'label': 'Account'},
            ],
            selectedIndex: 0,
            onSelected: (_) {},
            inboxState: state,
          ),
        ),
      );
      expect(find.text('99+'), findsWidgets);
      expect(find.text('130'), findsNothing);
      state.markRead(1);
      await tester.pumpAndSettle();
      expect(find.text('99+'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'current-data after screenshot and controlled unread acceptance example',
    (tester) async {
      if (!Platform.environment.containsKey('INBOX_PREVIEW_DIR')) return;
      final path = File('/tmp/magicai-inbox-counts-after.json');
      if (!path.existsSync()) return;
      final snapshot = jsonDecode(path.readAsStringSync()) as Map;
      final rows = (snapshot['chats'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      await fixture.mount(tester, InboxScreen(service: CountService(rows)));
      await fixture.screenshot(tester, 'after');
      await tester.pumpWidget(const SizedBox());
      final unread = [
        for (final row in rows)
          {
            ...row,
            'unread': row == rows.first ? 1 : 0,
            'needs_reply': row == rows.first,
          },
      ];
      await fixture.mount(tester, InboxScreen(service: CountService(unread)));
      await fixture.screenshot(tester, 'after-unread-scenario');
      await tester.tap(find.text('${unread.first['title']}'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await fixture.screenshot(tester, 'after-opened');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
