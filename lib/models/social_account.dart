class SocialAccount {
  final String id;
  final String
  platform; // 'x', 'facebook', 'instagram', 'linkedin', 'tiktok', 'youtube'
  final String displayName;
  final String handle;
  final String? avatarUrl;
  final bool isConnected;
  final int followers;
  final DateTime? lastSyncedAt;

  SocialAccount({
    required this.id,
    required this.platform,
    required this.displayName,
    required this.handle,
    this.avatarUrl,
    required this.isConnected,
    this.followers = 0,
    this.lastSyncedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'platform': platform,
    'displayName': displayName,
    'handle': handle,
    'avatarUrl': avatarUrl,
    'isConnected': isConnected,
    'followers': followers,
    'lastSyncedAt': lastSyncedAt?.toIso8601String(),
  };

  factory SocialAccount.fromJson(Map<String, dynamic> json) => SocialAccount(
    id: json['id'] ?? json['platform'] ?? 'account',
    platform: json['platform'] ?? 'x',
    displayName: json['displayName'] ?? json['platform'] ?? '',
    handle: json['handle'] ?? '',
    avatarUrl: json['avatarUrl'],
    isConnected: json['isConnected'] ?? false,
    followers: json['followers'] ?? 0,
    lastSyncedAt: json['lastSyncedAt'] != null
        ? DateTime.tryParse(json['lastSyncedAt'])
        : null,
  );

  SocialAccount copyWith({
    String? id,
    String? platform,
    String? displayName,
    String? handle,
    String? avatarUrl,
    bool? isConnected,
    int? followers,
    DateTime? lastSyncedAt,
  }) {
    return SocialAccount(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      displayName: displayName ?? this.displayName,
      handle: handle ?? this.handle,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isConnected: isConnected ?? this.isConnected,
      followers: followers ?? this.followers,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}
