class SavedDocument {
  final String id;
  final String title;
  final String content;
  final String type; // 'seo', 'blog', 'chat', 'template', 'image'
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  SavedDocument({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    required this.createdAt,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'type': type,
    'createdAt': createdAt.toIso8601String(),
    'metadata': metadata,
  };

  factory SavedDocument.fromJson(Map<String, dynamic> json) => SavedDocument(
    id: json['id'] ?? '',
    title: json['title'] ?? 'Untitled Document',
    content: json['content'] ?? '',
    type: json['type'] ?? 'general',
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
        : DateTime.now(),
    metadata: Map<String, dynamic>.from(json['metadata'] ?? {}),
  );
}
