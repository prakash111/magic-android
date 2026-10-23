class SocialPost {
  final String id;
  final String caption;
  final List<String> platforms;
  final String? mediaUrl;
  final String? mediaType; // 'image', 'video'
  final DateTime scheduledAt;
  final String status; // 'scheduled', 'published', 'draft'
  final DateTime createdAt;

  SocialPost({
    required this.id,
    required this.caption,
    required this.platforms,
    this.mediaUrl,
    this.mediaType,
    required this.scheduledAt,
    this.status = 'scheduled',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'caption': caption,
    'platforms': platforms,
    'mediaUrl': mediaUrl,
    'mediaType': mediaType,
    'scheduledAt': scheduledAt.toIso8601String(),
    'status': status,
    'createdAt': createdAt.toIso8601String(),
  };

  factory SocialPost.fromJson(Map<String, dynamic> json) => SocialPost(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    caption: json['caption'] ?? '',
    platforms: (json['platforms'] as List? ?? ['x'])
        .map((e) => e.toString())
        .toList(),
    mediaUrl: json['mediaUrl'],
    mediaType: json['mediaType'],
    scheduledAt: json['scheduledAt'] != null
        ? DateTime.tryParse(json['scheduledAt']) ??
              DateTime.now().add(const Duration(hours: 2))
        : DateTime.now().add(const Duration(hours: 2)),
    status: json['status'] ?? 'scheduled',
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
        : DateTime.now(),
  );

  SocialPost copyWith({
    String? id,
    String? caption,
    List<String>? platforms,
    String? mediaUrl,
    String? mediaType,
    DateTime? scheduledAt,
    String? status,
    DateTime? createdAt,
  }) {
    return SocialPost(
      id: id ?? this.id,
      caption: caption ?? this.caption,
      platforms: platforms ?? this.platforms,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      mediaType: mediaType ?? this.mediaType,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
