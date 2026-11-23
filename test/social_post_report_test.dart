import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:magicai_mobile/screens/native_social_screen.dart';
import 'package:magicai_mobile/screens/social/social_post_report_screen.dart';
import 'package:magicai_mobile/services/mobile_api.dart';
import 'package:magicai_mobile/services/social_post_service.dart';
import 'package:magicai_mobile/theme/app_colors.dart';
import 'package:magicai_mobile/theme/app_theme.dart';

import 'native_screen_test.dart' show nativeApi;

Map<String, dynamic> report({String status = 'published'}) => {
  'id': '42',
  'caption': 'Product launch update with a detailed caption for our audience.',
  'platforms': ['x'],
  'accountName': '@magicai',
  'status': status,
  'postType': 'post',
  'tone': 'Engaging',
  'createdAt': '2026-11-20T10:00:00Z',
  'publishedAt': status == 'published' ? '2026-11-21T12:00:00Z' : null,
  'link': status == 'published' ? 'https://x.com/i/web/status/123' : null,
  'analytics': {
    'metrics': [
      {
        'key': 'like_count',
        'label': 'Likes',
        'value': status == 'published' ? 0 : null,
      },
      {
        'key': 'impression_count',
        'label': 'Impressions',
        'value': status == 'published' ? 1234 : null,
      },
      {'key': 'reply_count', 'label': 'Replies', 'value': null},
    ],
    'engagementCount': status == 'published' ? 12 : null,
    'engagementRate': status == 'published' ? 0.97 : null,
    'updatedAt': status == 'published' ? '2026-11-23T12:00:00Z' : null,
  },
};

Widget shell(Widget child, Brightness brightness, {double scale = 1}) =>
    MaterialApp(
      theme: brightness == Brightness.dark
          ? AppTheme.darkTheme
          : AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: child),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    for (final width in [320.0, 390.0, 768.0]) {
      testWidgets(
        'post list and report fit $width in $brightness with enlarged text',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final requests = <String>[];
          final api = nativeApi((path, _) async {
            requests.add(path);
            if (path == '/social-media/platforms') return [];
            if (path == '/social-media/posts/42') return report();
            return {
              'data': [
                report(),
                {
                  ...report(),
                  'id': '43',
                  'mediaType': 'video',
                  'mediaUrl': 'https://media.example.test/clip.mp4',
                },
              ],
              'current_page': 1,
              'last_page': 1,
            };
          });
          await tester.pumpWidget(
            shell(ServerSocialScreen(api: api), brightness, scale: 1.4),
          );
          await tester.pumpAndSettle();
          final card = find.byType(SocialPostCard);
          expect(card, findsAtLeastNWidgets(1));
          expect(
            tester
                .widget<Card>(
                  find.descendant(of: card, matching: find.byType(Card)).first,
                )
                .color,
            brightness == Brightness.dark
                ? AppColors.dark.surface
                : AppColors.light.surface,
          );
          await tester.ensureVisible(find.byTooltip('Grid view'));
          await tester.tap(find.byTooltip('Grid view'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          final first = tester.getTopLeft(
            find.byKey(const ValueKey('social-post-42')),
          );
          final second = tester.getTopLeft(
            find.byKey(const ValueKey('social-post-43')),
          );
          if (width >= 700) {
            expect(first.dy, second.dy);
            expect(second.dx, greaterThan(first.dx));
          } else {
            expect(second.dy, greaterThan(first.dy));
          }
          await tester.ensureVisible(find.text('View report').first);
          await tester.tap(find.text('View report').first);
          await tester.pumpAndSettle();
          expect(requests, contains('/social-media/posts/42'));
          expect(find.text('Post report'), findsOneWidget);
          await tester.scrollUntilVisible(
            find.text('Post analytics'),
            300,
            scrollable: find
                .descendant(
                  of: find.byType(SocialPostReportScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tester.scrollUntilVisible(
            find.text('0.97%'),
            200,
            scrollable: find
                .descendant(
                  of: find.byType(SocialPostReportScreen),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          expect(find.text('1,234'), findsOneWidget);
          expect(find.text('0'), findsOneWidget);
          expect(find.text('Replies'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'report retains unavailable metrics and provides retry after a failed refresh',
    (tester) async {
      var fail = true;
      final api = nativeApi((_, _) async {
        if (fail) throw const ApiFailure('Connection unavailable');
        return report(status: 'draft');
      });
      await tester.pumpWidget(
        shell(
          SocialPostReportScreen(
            api: api,
            initialPost: report(status: 'draft'),
          ),
          Brightness.dark,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Post analytics'),
        250,
        scrollable: find
            .descendant(
              of: find.byType(SocialPostReportScreen),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text(
          'Analytics are available after this post is published and the platform syncs.',
        ),
        findsOneWidget,
      );
      expect(find.text('0'), findsNothing);
      expect(find.text('Open published post'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  test('detail service rejects invalid IDs and mismatched responses', () async {
    final api = nativeApi((_, _) async => {'id': '99'});
    final service = SocialPostService(api);
    await expectLater(service.post('../42'), throwsA(isA<ApiFailure>()));
    await expectLater(service.post('42'), throwsA(isA<ApiFailure>()));
  });
  for (final width in [320.0, 390.0]) {
    testWidgets(
      'large metrics stay inside a $width dp report with 1.6 text scaling and RTL',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final data = report();
        (data['analytics'] as Map)['metrics'] = [
          {'key': 'view_count', 'label': 'Views', 'value': 9007199254740991},
        ];
        (data['analytics'] as Map)['nextRefreshAt'] = '2026-11-23T12:15:00Z';
        final api = nativeApi((_, _) async => data);
        await tester.pumpWidget(
          shell(
            Directionality(
              textDirection: TextDirection.rtl,
              child: SocialPostReportScreen(api: api, initialPost: data),
            ),
            Brightness.dark,
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        final value = find.text('9,007,199,254,740,991');
        await tester.scrollUntilVisible(
          value,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(value, findsOneWidget);
        expect(tester.getRect(value).left, greaterThanOrEqualTo(0));
        expect(tester.getRect(value).right, lessThanOrEqualTo(width));
        expect(find.textContaining('Next analytics refresh'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'the media carousel resets its displayed page after a report refresh changes images',
    (tester) async {
      final first = {
        ...report(),
        'mediaType': 'image',
        'mediaUrl': 'https://magicai.example.test/one.png',
        'images': [
          'https://magicai.example.test/one.png',
          'https://magicai.example.test/two.png',
        ],
      };
      final second = {
        ...first,
        'images': [
          'https://magicai.example.test/three.png',
          'https://magicai.example.test/four.png',
        ],
      };
      Widget media(Map<String, dynamic> post) => shell(
        Center(
          child: SizedBox(
            width: 320,
            height: 240,
            child: SocialPostMedia(post: post),
          ),
        ),
        Brightness.dark,
      );
      await tester.pumpWidget(media(first));
      await tester.pumpAndSettle();
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        expect(image.fit, BoxFit.contain);
        expect(image.image, isA<ResizeImage>());
        expect((image.image as ResizeImage).width, lessThanOrEqualTo(1920));
      }
      await tester.drag(find.byType(PageView), const Offset(-350, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.pumpWidget(media(second));
      await tester.pumpAndSettle();
      expect(find.text('1 / 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'unsupported and credential-bearing media URLs never open a native preview',
    (tester) async {
      for (final url in [
        'javascript:alert(1)',
        'http://magicai.example.test/clip.mp4',
        'https://private@example.test/clip.mp4',
      ]) {
        await tester.pumpWidget(
          shell(
            SocialPostMedia(
              post: {...report(), 'mediaType': 'video', 'mediaUrl': url},
            ),
            Brightness.dark,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Play video'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    },
  );
}
