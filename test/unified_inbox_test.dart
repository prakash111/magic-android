import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/inbox/inbox_screen.dart';
import 'package:magicai_mobile/screens/inbox/thread_screen.dart';
import 'package:magicai_mobile/screens/workspace_screen.dart';
import 'package:magicai_mobile/services/inbox_service.dart';
import 'package:magicai_mobile/services/extension_workflow_service.dart';
import 'package:magicai_mobile/widgets/ai_review_card.dart';
import 'package:magicai_mobile/widgets/attachment_tray.dart';
import 'package:magicai_mobile/widgets/send_to_network_sheet.dart';
import 'package:magicai_mobile/widgets/message_bubble.dart';
import 'package:magicai_mobile/widgets/magic_bottom_navigation.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'extension_workflow_test.dart' show workflowApi;

const previewKey = ValueKey('inbox-preview');
final sampleChats = <Map<String, dynamic>>[
  {
    'id': 1,
    'network': 'tg',
    'remote_id': 'group-1',
    'title': 'Telegram Group',
    'is_group': true,
    'members': 128,
    'pinned': true,
    'muted': false,
    'unread': 3,
    'needs_reply': true,
    'connection_status': 'connected',
    'last_at': '2026-11-02T11:27:00Z',
    'typing_name': 'Meera',
    'last_message': {
      'body': 'Can someone share the pricing sheet?',
      'sender_name': 'Meera Kapoor',
      'direction': 'in',
    },
  },
  {
    'id': 2,
    'network': 'wa',
    'remote_id': 'contact-1',
    'title': 'Riya Sharma',
    'is_group': false,
    'pinned': false,
    'muted': false,
    'unread': 1,
    'needs_reply': true,
    'connection_status': 'connected',
    'last_at': '2026-11-02T11:52:00Z',
    'last_message': {'body': 'Can you send the proposal?', 'direction': 'in'},
  },
  {
    'id': 3,
    'network': 'tg',
    'remote_id': 'contact-2',
    'title': 'Vikram Singh',
    'is_group': false,
    'pinned': false,
    'muted': false,
    'unread': 0,
    'needs_reply': false,
    'connection_status': 'connected',
    'last_at': '2026-11-01T11:52:00Z',
    'last_message': {'body': 'Received, thanks!', 'direction': 'in'},
  },
  {
    'id': 4,
    'network': 'wa',
    'remote_id': 'contact-3',
    'title': 'Zoomnearby Support',
    'is_group': false,
    'pinned': false,
    'muted': true,
    'unread': 2,
    'needs_reply': false,
    'connection_status': 'expired',
    'last_at': '2026-11-01T12:52:00Z',
    'last_message': {'body': 'Your invoice is attached', 'direction': 'out'},
  },
];
final sampleMessages = <Map<String, dynamic>>[
  {
    'id': 1,
    'direction': 'in',
    'sender_remote_id': 'aarav',
    'sender_name': 'Aarav Mehta',
    'body': 'Hi team, quick question for the agency.',
    'status': 'received',
    'created_at': '2026-11-01T11:41:00Z',
    'attachments': [],
  },
  {
    'id': 2,
    'direction': 'out',
    'body': 'Hi! How can we help?',
    'status': 'read',
    'created_at': '2026-11-01T11:42:00Z',
    'attachments': [],
  },
  {
    'id': 3,
    'direction': 'in',
    'sender_remote_id': 'aarav',
    'sender_name': 'Aarav Mehta',
    'body': 'Are you providing web services?',
    'status': 'received',
    'created_at': '2026-11-02T11:43:00Z',
    'attachments': [],
  },
  {
    'id': 4,
    'direction': 'out',
    'body': 'Yes, we build websites, apps and SEO.',
    'status': 'delivered',
    'created_at': '2026-11-02T11:44:00Z',
    'attachments': [],
  },
  {
    'id': 5,
    'direction': 'in',
    'sender_remote_id': 'meera',
    'sender_name': 'Meera Kapoor',
    'body': 'Can someone share the pricing sheet?',
    'status': 'received',
    'created_at': '2026-11-02T12:03:00Z',
    'attachments': [],
  },
  {
    'id': 6,
    'direction': 'in',
    'sender_remote_id': 'karan',
    'sender_name': 'Karan Joshi',
    'body': 'Here is the latest brochure',
    'status': 'received',
    'created_at': '2026-11-02T12:05:00Z',
    'attachments': [
      {
        'id': 4,
        'kind': 'document',
        'name': 'Agency-Brochure.pdf',
        'size': 2516582,
        'mime': 'application/pdf',
      },
    ],
  },
];

class FakeInboxService extends InboxService {
  FakeInboxService() : super(workflowApi((_) async => {'data': []}));
  Map<String, dynamic> preferences = {
    'ai_fix_mode': 'off',
    'smart_replies': true,
  };
  List<Map<String, dynamic>> sent = [], pending = [];
  int reads = 0;
  final chatRows = [
    for (final chat in sampleChats) Map<String, dynamic>.from(chat),
  ];
  Map<String, dynamic> cacheData = {};
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
                  )) &&
              (!needsReply || c['needs_reply'] == true),
        )
        .toList(),
    'meta': InboxCounts.fromChats(chatRows).toJson(),
    'networks': [
      {'network': 'tg', 'status': 'connected'},
      {'network': 'wa', 'status': 'connected'},
    ],
  };
  @override
  Future<Map<String, dynamic>> messages(int chat, {String? cursor}) async => {
    'data': [...sampleMessages, ...sent],
    'chat': chatRows.firstWhere((row) => row['id'] == chat),
  };
  @override
  Future<void> read(int chat) async {
    reads++;
    final row = chatRows.firstWhere((row) => row['id'] == chat);
    row['unread'] = 0;
    row['needs_reply'] = false;
  }

  @override
  Future<Map<String, dynamic>> counts() async =>
      InboxCounts.fromChats(chatRows).toJson();

  @override
  Future<void> pin(int chat, {bool? pinned, bool? muted}) async {
    final row = chatRows.firstWhere((row) => row['id'] == chat);
    if (pinned != null) row['pinned'] = pinned;
    if (muted != null) row['muted'] = muted;
  }

  @override
  Future<void> flush() async {}
  @override
  Future<List<Map<String, dynamic>>> outbox(int chat) async => pending;
  @override
  Future<void> cache(String name, Object value) async {
    cacheData[name] = value;
  }

  @override
  Future<dynamic> cached(String name) async => cacheData[name];
  @override
  Future<Map<String, dynamic>> prefs({Map<String, dynamic>? values}) async {
    preferences.addAll(values ?? {});
    return preferences;
  }

  @override
  Future<List<String>> replies(int chat, {String? model}) async => [
    'Yes, we build websites and mobile apps',
    'Sure, happy to help.',
    'You are welcome!',
  ];
  @override
  Future<Map<String, dynamic>> fix(
    String text, {
    String lang = 'en',
    String? model,
  }) async => {
    'text': 'Yes, we provide these services.',
    'changes': [
      {'from': text, 'to': 'Yes, we provide these services.'},
    ],
  };
  @override
  Future<Map<String, dynamic>> send(
    int chat,
    String text, {
    List<int> attachments = const [],
    int? replyTo,
    String? clientId,
    String mode = 'off',
    String? model,
    String lang = 'en',
  }) async {
    final row = {
      'id': 100 + sent.length,
      'body': mode == 'auto' ? 'Yes, we provide these services.' : text,
      'direction': 'out',
      'status': 'sent',
      'created_at': '2026-11-02T12:48:00Z',
      'attachments': [],
      if (mode == 'auto')
        'ai_fixed_json': {
          'original': text,
          'changes': [
            {'from': text, 'to': 'Yes, we provide these services.'},
          ],
        },
    };
    sent.add(row);
    return {'data': row};
  }

  @override
  Future<List<Map<String, dynamic>>> forward(
    String text,
    List<int> chats, {
    bool fix = false,
    String? model,
  }) async => chats
      .map((id) => {'chat_id': id, 'status': 'queued', 'message_id': 100 + id})
      .toList();
  @override
  Future<List<Map<String, dynamic>>> sendStatus(List<int> ids) async =>
      ids.map((id) => {'id': id, 'status': 'sent'}).toList();
}

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  Size size = const Size(400, 860),
  bool rtl = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    RepaintBoundary(
      key: previewKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme.copyWith(
          appBarTheme: AppTheme.darkTheme.appBarTheme.copyWith(
            titleTextStyle: AppTheme.darkTheme.textTheme.titleLarge?.copyWith(
              fontFamily: Platform.environment.containsKey('INBOX_FONT_DIR')
                  ? 'Roboto'
                  : null,
            ),
          ),
          textTheme: AppTheme.darkTheme.textTheme.apply(
            fontFamily: Platform.environment.containsKey('INBOX_FONT_DIR')
                ? 'Roboto'
                : null,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
            child: child!,
          ),
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> screenshot(WidgetTester tester, String name) async {
  final directory = Platform.environment['INBOX_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(previewKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File('$directory/$name.png').writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    final fonts = Platform.environment['INBOX_FONT_DIR'];
    if (fonts != null) {
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('$fonts/Roboto-Regular.ttf').readAsBytes(),
            ),
          ),
        )
        ..addFont(
          Future.value(
            ByteData.sublistView(
              await File('$fonts/Roboto-Bold.ttf').readAsBytes(),
            ),
          ),
        );
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
    }
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'inbox filters networks, counts unread and waiting chats without duplicate rows',
    (tester) async {
      final service = FakeInboxService();
      await mount(tester, InboxScreen(service: service));
      expect(find.text('Telegram Group'), findsOneWidget);
      expect(find.text('Meera is typing…'), findsOneWidget);
      await screenshot(tester, 'inbox');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Telegram'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('Riya Sharma'), findsNothing);
      expect(find.text('Vikram Singh'), findsOneWidget);
      await tester.tap(find.text('AI inbox'));
      await tester.pumpAndSettle();
      expect(find.text('Vikram Singh'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'thread shows group sender names attachments date separators and read receipts',
    (tester) async {
      final service = FakeInboxService();
      await mount(
        tester,
        ThreadScreen(service: service, chat: sampleChats.first),
      );
      expect(find.text('Karan Joshi'), findsOneWidget);
      expect(find.text('Agency-Brochure.pdf'), findsOneWidget);
      expect(service.reads, greaterThan(0));
      expect(find.byType(MessageBubble), findsWidgets);
      await screenshot(tester, 'thread');
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final mode in ['off', 'ask', 'auto']) {
    testWidgets(
      'composer handles AI fix mode $mode without sending before review',
      (tester) async {
        final service = FakeInboxService()..preferences['ai_fix_mode'] = mode;
        await mount(
          tester,
          ThreadScreen(service: service, chat: sampleChats.first),
        );
        await tester.enterText(
          find.byType(TextField).last,
          'yes we do teh servises',
        );
        await tester.tap(find.byTooltip('Send'));
        await tester.pumpAndSettle();
        if (mode == 'ask') {
          expect(service.sent, isEmpty);
          expect(find.byType(AiReviewCard), findsOneWidget);
          await screenshot(tester, 'ai-review');
          await tester.ensureVisible(find.text('Send corrected'));
          await tester.tap(find.text('Send corrected'));
          await tester.pumpAndSettle();
          expect(
            service.sent.single['body'],
            'Yes, we provide these services.',
          );
        } else {
          expect(service.sent, hasLength(1));
          expect(service.sent.single['ai_fixed_json'] != null, mode == 'auto');
        }
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'send sheet selects multiple networks and shows real recipient outcomes',
    (tester) async {
      final service = FakeInboxService();
      await mount(
        tester,
        Scaffold(
          body: SendToNetworkSheet(
            service: service,
            text: 'Here is a 7-day content plan.',
          ),
        ),
      );
      await tester.tap(find.text('Telegram Group'));
      await tester.tap(find.text('Riya Sharma'));
      await tester.pumpAndSettle();
      expect(find.text('Send to 2 chats'), findsOneWidget);
      await screenshot(tester, 'send-to-network');
      await tester.tap(find.text('Send to 2 chats'));
      await tester.pumpAndSettle();
      expect(find.text('Open in Inbox'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await screenshot(tester, 'sent-to-network');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('attachment tray shows selected files and removes them', (
    tester,
  ) async {
    var removed = -1;
    await mount(
      tester,
      Scaffold(
        body: AttachmentTray(
          files: [
            const WorkflowFile('Proposal.pdf', [
              1,
              2,
              3,
            ], mimeType: 'application/pdf'),
          ],
          onRemove: (index) => removed = index,
        ),
      ),
    );
    expect(find.text('Proposal.pdf'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove attachment'));
    expect(removed, 0);
  });
  testWidgets('favorites pin instantly and remember the selected section', (
    tester,
  ) async {
    final modules = <Map<String, dynamic>>[
      {
        'id': 'inbox',
        'title': 'Inbox',
        'route': 'dashboard.user.marketing-bot.inbox.index',
        'category': 'Campaigns & messaging',
        'available': true,
      },
      {
        'id': 'creative',
        'title': 'Creative Suite',
        'category': 'Creative studio',
        'available': true,
      },
      {
        'id': 'crm',
        'title': 'CRM Contacts',
        'category': 'CRM',
        'available': true,
      },
    ];
    await mount(
      tester,
      Scaffold(
        body: WorkspaceScreen(
          modules: modules,
          user: const {'id': 1},
          refresh: () async {},
        ),
      ),
    );
    expect(find.byTooltip('Show favorites'), findsOneWidget);
    await tester.tap(find.byTooltip('Show favorites'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to favorites').first);
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsNWidgets(2));
    await screenshot(tester, 'explore');
    await tester.scrollUntilVisible(
      find.widgetWithText(ChoiceChip, 'CRM'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(SliverPersistentHeader),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'CRM'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('explore-tool-crm')), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-tool-creative')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      Scaffold(
        body: WorkspaceScreen(
          modules: modules,
          user: const {'id': 1},
          refresh: () async {},
        ),
      ),
    );
    expect(find.byKey(const ValueKey('explore-tool-crm')), findsOneWidget);
    expect(find.byKey(const ValueKey('explore-tool-creative')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'thread and composer fit a small RTL screen at 160 percent text',
    (tester) async {
      await mount(
        tester,
        ThreadScreen(service: FakeInboxService(), chat: sampleChats.first),
        scale: 1.6,
        size: const Size(320, 568),
        rtl: true,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Inbox does not expose connection setup or webhook details', (
    tester,
  ) async {
    await mount(tester, InboxScreen(service: FakeInboxService()));
    expect(find.byTooltip('Connection settings'), findsNothing);
    expect(find.textContaining('webhook'), findsNothing);
    expect(find.byTooltip('Refresh'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'bottom Inbox navigation displays unread count and remains accessible in RTL',
    (tester) async {
      final inbox = InboxState();
      inbox.applyCounts({
        'all': 7,
        'telegram': 7,
        'whatsapp': 0,
        'needs_reply': 0,
        'chats_total': 1,
      }, inbox.beginFetch());
      var selected = -1;
      await mount(
        tester,
        Scaffold(
          bottomNavigationBar: MagicBottomNavigation(
            items: const [
              {'component': 'dashboard', 'label': 'Home'},
              {'component': 'workspace', 'label': 'Explore'},
              {'component': 'chat', 'label': 'Chatbot'},
              {'component': 'inbox', 'label': 'Inbox'},
              {'component': 'account', 'label': 'Account'},
            ],
            inboxState: inbox,
            selectedIndex: 0,
            onSelected: (index) => selected = index,
          ),
        ),
        size: const Size(320, 568),
        scale: 1.6,
        rtl: true,
      );
      expect(find.text('Inbox'), findsOneWidget);
      expect(find.text('7'), findsWidgets);
      await tester.tap(find.text('Inbox'));
      expect(selected, 3);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      inbox.dispose();
    },
  );
}
