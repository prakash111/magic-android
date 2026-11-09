import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/inbox/inbox_screen.dart';
import 'package:magicai_mobile/services/inbox_service.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'extension_workflow_test.dart' show workflowApi;

final sampleTestChats = <Map<String, dynamic>>[
  {
    'id': 101,
    'network': 'tg',
    'remote_id': 'contact-101',
    'title': 'Alice Walker',
    'is_group': false,
    'pinned': false,
    'muted': false,
    'unread': 2,
    'needs_reply': true,
    'connection_status': 'connected',
    'last_at': '2026-11-09T10:00:00Z',
    'last_message': {'body': 'Hey, are you free today?', 'direction': 'in'},
  },
  {
    'id': 102,
    'network': 'wa',
    'remote_id': 'contact-102',
    'title': 'Bob Martin',
    'is_group': false,
    'pinned': false,
    'muted': false,
    'unread': 0,
    'needs_reply': false,
    'connection_status': 'connected',
    'last_at': '2026-11-09T09:00:00Z',
    'last_message': {'body': 'Thanks for the update!', 'direction': 'out'},
  },
];

class TestInboxService extends InboxService {
  TestInboxService() : super(workflowApi((_) async => {'data': []}));

  final List<Map<String, dynamic>> chatRows = [
    for (final c in sampleTestChats) Map<String, dynamic>.from(c),
  ];
  final List<int> deletedChats = [];

  @override
  Future<Map<String, dynamic>> chats({
    String network = '',
    String query = '',
    String? cursor,
    bool needsReply = false,
  }) async => {
    'data': chatRows
        .where(
          (c) =>
              (network.isEmpty || c['network'] == network) &&
              (query.isEmpty ||
                  '${c['title']}'.toLowerCase().contains(
                    query.toLowerCase(),
                  )),
        )
        .toList(),
    'meta': InboxCounts.fromChats(chatRows).toJson(),
    'networks': [
      {'network': 'tg', 'status': 'connected'},
      {'network': 'wa', 'status': 'connected'},
    ],
  };

  @override
  Future<void> flush() async {}

  @override
  Future<Map<String, dynamic>> counts() async =>
      InboxCounts.fromChats(chatRows).toJson();

  @override
  Future<void> deleteChat(int chat) async {
    deletedChats.add(chat);
    chatRows.removeWhere((c) => c['id'] == chat);
    state.removeChat(chat);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
    theme: AppTheme.darkTheme,
    home: child,
  );

  group('InboxState removeChat unit tests', () {
    test('removes chat from state and updates counts immediately', () {
      final state = InboxState();
      final fetch = state.beginFetch();
      state.applyPage({
        'data': [
          for (final c in sampleTestChats) Map<String, dynamic>.from(c),
        ],
        'meta': InboxCounts.fromChats(sampleTestChats).toJson(),
      }, fetch);

      expect(state.chats.length, 2);
      expect(state.counts?.all, 2);
      expect(state.counts?.chatsTotal, 2);

      final removed = state.removeChat(101);
      expect(removed, isTrue);
      expect(state.chats.length, 1);
      expect(state.chats.first['id'], 102);
      expect(state.counts?.all, 0); // Alice had 2 unread, Bob had 0
      expect(state.counts?.chatsTotal, 1);

      // Unknown chat ID returns false
      expect(state.removeChat(999), isFalse);
    });
  });

  group('InboxScreen delete interaction tests', () {
    testWidgets('shows dismissible swipe-to-delete with confirmation dialog', (
      tester,
    ) async {
      final service = TestInboxService();
      await tester.pumpWidget(wrap(InboxScreen(service: service)));
      await tester.pumpAndSettle();

      expect(find.text('Alice Walker'), findsOneWidget);
      expect(find.text('Bob Martin'), findsOneWidget);

      // Verify Dismissible exists
      expect(find.byKey(const ValueKey('inbox-chat-101')), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-chat-102')), findsOneWidget);

      // Swipe to delete Alice Walker
      await tester.drag(
        find.byKey(const ValueKey('inbox-chat-101')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      // Dialog should be visible
      expect(find.text('Delete conversation?'), findsOneWidget);
      expect(find.text('"Alice Walker" and all its messages will be deleted.'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Tap Cancel -> chat should remain
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Alice Walker'), findsOneWidget);
      expect(service.deletedChats, isEmpty);

      // Swipe again and confirm
      await tester.drag(
        find.byKey(const ValueKey('inbox-chat-101')),
        const Offset(-500, 0),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Alice Walker should be removed from the list immediately
      expect(find.text('Alice Walker'), findsNothing);
      expect(find.text('Bob Martin'), findsOneWidget);
      expect(service.deletedChats, contains(101));
    });

    testWidgets('long press displays delete action and deletes on confirmation', (
      tester,
    ) async {
      final service = TestInboxService();
      await tester.pumpWidget(wrap(InboxScreen(service: service)));
      await tester.pumpAndSettle();

      expect(find.text('Bob Martin'), findsOneWidget);

      // Long press on Bob Martin
      await tester.longPress(find.text('Bob Martin'));
      await tester.pumpAndSettle();

      // Bottom sheet options
      expect(find.text('Pin chat'), findsOneWidget);
      expect(find.text('Delete conversation'), findsOneWidget);

      // Tap Delete conversation
      await tester.tap(find.text('Delete conversation'));
      await tester.pumpAndSettle();

      // Confirmation dialog
      expect(find.text('Delete conversation?'), findsOneWidget);
      expect(find.text('"Bob Martin" and all its messages will be deleted.'), findsOneWidget);

      // Confirm delete
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Bob Martin should be gone immediately
      expect(find.text('Bob Martin'), findsNothing);
      expect(service.deletedChats, contains(102));
    });
  });
}
