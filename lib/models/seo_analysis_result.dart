class SEOChecklistItem {
  final String title;
  final bool passed;
  final String detail;
  final String category;

  SEOChecklistItem({
    required this.title,
    required this.passed,
    required this.detail,
    required this.category,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'passed': passed,
    'detail': detail,
    'category': category,
  };

  factory SEOChecklistItem.fromJson(Map<String, dynamic> json) =>
      SEOChecklistItem(
        title: json['title'] ?? '',
        passed: json['passed'] ?? false,
        detail: json['detail'] ?? '',
        category: json['category'] ?? 'general',
      );
}

class SEOAnalysisResult {
  final double percentage;
  final int wordCount;
  final int characterCount;
  final int headingCount;
  final int linkCount;
  final int imageCount;
  final double keywordDensity;
  final int keywordOccurrences;
  final double readabilityScore;
  final String readabilityGrade;
  final List<String> competitorList;
  final List<String> longTailList;
  final List<SEOChecklistItem> checklist;
  final String? improvedContent;

  SEOAnalysisResult({
    required this.percentage,
    required this.wordCount,
    required this.characterCount,
    required this.headingCount,
    required this.linkCount,
    required this.imageCount,
    required this.keywordDensity,
    required this.keywordOccurrences,
    required this.readabilityScore,
    required this.readabilityGrade,
    required this.competitorList,
    required this.longTailList,
    required this.checklist,
    this.improvedContent,
  });

  Map<String, dynamic> toJson() => {
    'percentage': percentage,
    'wordCount': wordCount,
    'characterCount': characterCount,
    'headingCount': headingCount,
    'linkCount': linkCount,
    'imageCount': imageCount,
    'keywordDensity': keywordDensity,
    'keywordOccurrences': keywordOccurrences,
    'readabilityScore': readabilityScore,
    'readabilityGrade': readabilityGrade,
    'competitorList': competitorList,
    'longTailList': longTailList,
    'checklist': checklist.map((e) => e.toJson()).toList(),
    'improvedContent': improvedContent,
  };

  factory SEOAnalysisResult.fromJson(Map<String, dynamic> json) {
    var rawChecklist = json['checklist'] as List? ?? [];
    return SEOAnalysisResult(
      percentage: (json['percentage'] is num)
          ? (json['percentage'] as num).toDouble()
          : double.tryParse('${json['percentage']}') ?? 0.0,
      wordCount: json['wordCount'] ?? 0,
      characterCount: json['characterCount'] ?? 0,
      headingCount: json['headersCount'] ?? json['headingCount'] ?? 0,
      linkCount: json['linksCount'] ?? json['linkCount'] ?? 0,
      imageCount: json['imagesCount'] ?? json['imageCount'] ?? 0,
      keywordDensity: (json['keywordDensity'] is num)
          ? (json['keywordDensity'] as num).toDouble()
          : 0.0,
      keywordOccurrences: json['keywordOccurrences'] ?? 0,
      readabilityScore: (json['readabilityScore'] is num)
          ? (json['readabilityScore'] as num).toDouble()
          : 70.0,
      readabilityGrade: json['readabilityGrade'] ?? 'Good',
      competitorList: (json['competitorList'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      longTailList: (json['longTailList'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      checklist: rawChecklist
          .map((e) => SEOChecklistItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      improvedContent: json['improvedContent'],
    );
  }
}
