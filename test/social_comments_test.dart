import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magicai_mobile/screens/social/social_post_comments_screen.dart';
import 'package:magicai_mobile/screens/social/social_post_report_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/social_notification_navigation.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

Map<String, dynamic> response({bool replied = false}) => {
  'supported': true,
  'can_reply': true,
  'current_page': 1,
  'last_page': 1,
  'data': [
    {
      'id': '11',
      'author': 'Visitor',
      'text': 'How can I book?',
      'can_reply': true,
      'status': 'received',
      'replies': replied
          ? [
              {'id': '12', 'status': 'sent', 'text': 'Use our booking page.'},
            ]
          : [],
    },
  ],
};
Widget host(Widget child) =>
    MaterialApp(theme: AppTheme.darkTheme, home: child);

void main() {
  incomingSocialCommentTests();
  socialCommentPaginationTests();
  tearDown(() {
    SocialNotificationNavigation.pending.value = null;
    SocialNotificationNavigation.ready = false;
  });

  test('push targets use local post and comment ids and accept existing link payloads', () {
    final target = SocialNotificationNavigation.parse({
      'type': 'social_comment',
      'social_post_id': '7',
      'social_comment_id': '11',
    });
    expect(target!.postId, '7');
    expect(target.commentId, '11');
    expect(
      SocialNotificationNavigation.parse({
        'link': 'https://magicai.example.test/dashboard/user/social-media/post/7?comment_id=11',
      })!.commentId,
      '11',
    );
    expect(
      SocialNotificationNavigation.parse({'link': 'javascript:alert(1)'}),
      isNull,
    );
    expect(
      SocialNotificationNavigation.parse({
        'type': 'social_comment',
        'social_post_id': '../private',
      }),
      isNull,
    );
  });

  testWidgets('loads comments and replies to the exact selected comment', (
    tester,
  ) async {
    var replied = false;
    Map? sent;
    final api = nativeApi((path, body) async {
      if (path.endsWith('/comments/11/reply')) {
        sent = body;
        replied = true;
        return {
          'data': {'id': '12', 'status': 'sent'},
        };
      }
      return response(replied: replied);
    });
    await tester.pumpWidget(
      host(SocialPostCommentsScreen(api: api, postId: '7', commentId: '11')),
    );
    await tester.pumpAndSettle();
    expect(find.text('How can I book?'), findsOneWidget);
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Use our booking page.');
    await tester.tap(find.text('Send reply'));
    await tester.pumpAndSettle();
    expect(sent!['text'], 'Use our booking page.');
    expect(sent!['request_id'], isNotEmpty);
    expect(find.text('Your reply'), findsOneWidget);
    expect(find.text('Use our booking page.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'permission failures keep comments visible and leave the reply editable',
    (tester) async {
      final api = nativeApi((path, body) async {
        if (path.endsWith('/reply')) {
          throw const ApiFailure(
            'Reconnect and grant comment permissions.',
            status: 422,
          );
        }
        return response();
      });
      await tester.pumpWidget(
        host(SocialPostCommentsScreen(api: api, postId: '7')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'My reply');
      await tester.tap(find.text('Send reply'));
      await tester.pumpAndSettle();
      expect(
        find.text('Reconnect and grant comment permissions.'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'My reply',
      );
    },
  );

  testWidgets(
    'unsupported networks show the server explanation without a reply control',
    (tester) async {
      final api = nativeApi(
        (path, body) async => {
          'supported': false,
          'can_reply': false,
          'reason': 'Comments are unavailable for this connection.',
          'data': [],
          'current_page': 1,
          'last_page': 1,
        },
      );
      await tester.pumpWidget(
        host(SocialPostCommentsScreen(api: api, postId: '7')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Comments are unavailable for this connection.'),
        findsOneWidget,
      );
      expect(find.text('Reply'), findsNothing);
    },
  );

  testWidgets('comment layout fits a small screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(1.6),
          ),
          child: SocialPostCommentsScreen(
            api: nativeApi((_, body) async => response()),
            postId: '7',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a comment notification opens its thread after the report loads',
    (tester) async {
      final api = nativeApi(
        (path, body) async => path.contains('/comments')
            ? response()
            : {
                'id': '7',
                'status': 'published',
                'caption': 'Post',
                'platforms': ['facebook'],
                'analytics': {'metrics': []},
              },
      );
      await tester.pumpWidget(
        host(
          SocialPostReportScreen(
            api: api,
            initialPost: const {'id': '7'},
            initialCommentId: '11',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Comments and replies'), findsOneWidget);
      expect(find.text('How can I book?'), findsOneWidget);
    },
  );
}

void incomingSocialCommentTests() {
  testWidgets('an incoming comment push refreshes the currently open thread', (
    tester,
  ) async {
    var count = 0;
    final api = nativeApi((path, body) async {
      count++;
      return response();
    });
    await tester.pumpWidget(
      host(SocialPostCommentsScreen(api: api, postId: '7')),
    );
    await tester.pumpAndSettle();
    final before = count;
    SocialNotificationNavigation.update({
      'type': 'social_comment',
      'social_post_id': '7',
      'social_comment_id': '11',
    });
    await tester.pumpAndSettle();
    expect(count, greaterThan(before));
  });
}

void socialCommentPaginationTests() {
  testWidgets(
    'remote comment pagination fills the current partial page without skipping comments',
    (tester) async {
      final paths = <String>[];
      final api = nativeApi((path, body) async {
        paths.add(path);
        final next = Uri.parse(path).queryParameters['cursor'];
        final data = response();
        data['next_cursor'] = next == null ? 'older-comments' : null;
        if (next != null) {
          (data['data'] as List).add({
            'id': '22',
            'author': 'Second visitor',
            'text': 'Older comment',
            'can_reply': true,
            'replies': [],
          });
        }
        return data;
      });
      await tester.pumpWidget(
        host(SocialPostCommentsScreen(api: api, postId: '7')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Load more comments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Load more comments'));
      await tester.pumpAndSettle();
      expect(Uri.parse(paths.last).queryParameters['page'], '1');
      expect(Uri.parse(paths.last).queryParameters['cursor'], 'older-comments');
      expect(find.text('Older comment'), findsOneWidget);
    },
  );
}
