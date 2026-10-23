class KeywordItem {
  final String keyword;
  final int volume;
  final double cpc;
  final int difficulty;
  final String intent;

  KeywordItem({
    required this.keyword,
    this.volume = 0,
    this.cpc = 0,
    this.difficulty = 0,
    this.intent = 'Unavailable',
  });

  Map<String, dynamic> toJson() => {
    'keyword': keyword,
    'volume': volume,
    'cpc': cpc,
    'difficulty': difficulty,
    'intent': intent,
  };

  factory KeywordItem.fromJson(Map<String, dynamic> json) => KeywordItem(
    keyword: json['keyword'] ?? '',
    volume: json['volume'] ?? 0,
    cpc: (json['cpc'] is num) ? (json['cpc'] as num).toDouble() : 0,
    difficulty: json['difficulty'] ?? 0,
    intent: json['intent'] ?? 'Unavailable',
  );
}

class SearchQuestionItem {
  final String question;
  final String category;
  final String snippet;

  SearchQuestionItem({
    required this.question,
    required this.category,
    this.snippet = '',
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'category': category,
    'snippet': snippet,
  };

  factory SearchQuestionItem.fromJson(Map<String, dynamic> json) =>
      SearchQuestionItem(
        question: json['question'] ?? '',
        category: json['category'] ?? 'General',
        snippet: json['snippet'] ?? '',
      );
}

class SEOMetaResult {
  final String title;
  final String description;
  final String keywords;
  final String ogTitle;
  final String ogDescription;
  final String canonicalUrl;
  final String schemaJson;

  SEOMetaResult({
    required this.title,
    required this.description,
    required this.keywords,
    required this.ogTitle,
    required this.ogDescription,
    required this.canonicalUrl,
    required this.schemaJson,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'keywords': keywords,
    'ogTitle': ogTitle,
    'ogDescription': ogDescription,
    'canonicalUrl': canonicalUrl,
    'schemaJson': schemaJson,
  };

  factory SEOMetaResult.fromJson(Map<String, dynamic> json) => SEOMetaResult(
    title: json['title'] ?? '',
    description: json['description'] ?? '',
    keywords: json['keywords'] ?? '',
    ogTitle: json['ogTitle'] ?? json['title'] ?? '',
    ogDescription: json['ogDescription'] ?? json['description'] ?? '',
    canonicalUrl: json['canonicalUrl'] ?? '',
    schemaJson: json['schemaJson'] ?? '',
  );
}
