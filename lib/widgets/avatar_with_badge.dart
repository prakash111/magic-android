import 'package:flutter/material.dart';

import '../theme/design.dart';

class AvatarWithBadge extends StatelessWidget {
  final String name, network;
  final String? url;
  final double radius;
  const AvatarWithBadge({
    super.key,
    required this.name,
    required this.network,
    this.url,
    this.radius = 24,
  });
  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s.characters.first)
        .join()
        .toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: accentFor(name),
      foregroundColor: Colors.white,
      child: Text(initials.isEmpty ? '?' : initials),
    );
    return SizedBox(
      width: radius * 2 + 4,
      height: radius * 2 + 4,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipOval(
              child: url == null || url!.isEmpty
                  ? fallback
                  : Image(
                      image: NetworkImage(url!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => fallback,
                      loadingBuilder: (_, child, progress) =>
                          progress == null ? child : fallback,
                    ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: CircleAvatar(
              radius: 9,
              backgroundColor: network == 'wa'
                  ? const Color(0xff10b981)
                  : const Color(0xff24a9e5),
              child: Icon(
                switch (network) {
                  'wa' => Icons.chat,
                  'ms' => Icons.message,
                  'ig' => Icons.camera_alt,
                  'wb' => Icons.language,
                  _ => Icons.send,
                },
                size: 11,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
