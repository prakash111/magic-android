import 'package:flutter/foundation.dart';

class SocialNotificationTarget {
  final String postId;
  final String? commentId;
  const SocialNotificationTarget(this.postId, this.commentId);
}

class SocialNotificationNavigation {
  static bool ready = false;

  static void markReady() {
    ready = true;
    final target = pending.value;
    if (target != null) {
      pending.value = SocialNotificationTarget(target.postId, target.commentId);
    }
  }

  static final updates = ValueNotifier<SocialNotificationTarget?>(null);

  static void update(Map<String, dynamic> data) {
    final target = parse(data);
    if (target != null) updates.value = target;
  }

  static final pending = ValueNotifier<SocialNotificationTarget?>(null);

  static SocialNotificationTarget? parse(Map<String, dynamic> data) {
    final direct = '${data['social_post_id'] ?? ''}';
    final comment = '${data['social_comment_id'] ?? ''}';
    if (data['type'] == 'social_comment' && RegExp(r'^\d+$').hasMatch(direct)) {
      return SocialNotificationTarget(
        direct,
        RegExp(r'^\d+$').hasMatch(comment) ? comment : null,
      );
    }
    final uri = Uri.tryParse('${data['link'] ?? ''}');
    if (uri == null ||
        (uri.hasScheme && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final match = RegExp(r'^/dashboard/user/social-media/post/(\d+)$')
        .firstMatch(uri.path);
    final id = uri.queryParameters['comment_id'];
    return match == null
        ? null
        : SocialNotificationTarget(
            match.group(1)!,
            id != null && RegExp(r'^\d+$').hasMatch(id) ? id : null,
          );
  }

  static void receive(Map<String, dynamic> data) {
    final target = parse(data);
    if (target != null) pending.value = target;
  }
}
