import 'dart:math';

import '../models/seo_analysis_result.dart';

class SEOEngine {
  /// Analyzes article or product description text against target keyword
  static SEOAnalysisResult analyze({
    required String content,
    required String keyword,
    String contentType = 'article',
  }) {
    final cleanContent = content.trim();
    if (cleanContent.isEmpty) {
      return SEOAnalysisResult(
        percentage: 0,
        wordCount: 0,
        characterCount: 0,
        headingCount: 0,
        linkCount: 0,
        imageCount: 0,
        keywordDensity: 0,
        keywordOccurrences: 0,
        readabilityScore: 0,
        readabilityGrade: 'No Content',
        competitorList: [],
        longTailList: [],
        checklist: [
          SEOChecklistItem(
            title: 'Add Content to Analyze',
            passed: false,
            detail: 'Start writing or paste your draft into the editor.',
            category: 'content',
          ),
        ],
      );
    }

    final words = cleanContent
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();

    final wordCount = words.length;
    final characterCount = cleanContent.length;

    // Headings count (Markdown `# Heading` or HTML `<h1>..</h6>`)
    final markdownHeadings = RegExp(
      r'(^|\n)#{1,6}\s+.+',
      caseSensitive: false,
    ).allMatches(cleanContent).length;
    final htmlHeadings = RegExp(
      r'<h[1-6][^>]*>.*?</h[1-6]>',
      caseSensitive: false,
    ).allMatches(cleanContent).length;
    final headingCount = markdownHeadings + htmlHeadings;

    // Links count (Markdown `[text](url)` excluding images `![alt](url)` or HTML `<a href=...>`)
    final markdownLinks = RegExp(r'(?<!!)\[([^\]]+)\]\(([^)]+)\)')
        .allMatches(cleanContent)
        .length;
    final htmlLinks = RegExp(
      r'<a\s+[^>]*href=[^>]*>',
      caseSensitive: false,
    ).allMatches(cleanContent).length;
    final linkCount = markdownLinks + htmlLinks;

    // Images count (Markdown `![alt](url)` or HTML `<img ...>`)
    final markdownImages = RegExp(r'!\[([^\]]*)\]\(([^)]+)\)')
        .allMatches(cleanContent)
        .length;
    final htmlImages = RegExp(
      r'<img\s+[^>]*>',
      caseSensitive: false,
    ).allMatches(cleanContent).length;
    final imageCount = markdownImages + htmlImages;

    // Keyword metrics
    final cleanKeyword = keyword.trim().toLowerCase();
    int keywordOccurrences = 0;
    double keywordDensity = 0.0;

    if (cleanKeyword.isNotEmpty && wordCount > 0) {
      final keywordWords = cleanKeyword.split(RegExp(r'\s+'));
      if (keywordWords.length == 1) {
        keywordOccurrences = words.where((w) => w == cleanKeyword).length;
      } else {
        // Multi-word phrase count
        final lowerContent = cleanContent.toLowerCase();
        keywordOccurrences = RegExp(RegExp.escape(cleanKeyword))
            .allMatches(lowerContent)
            .length;
      }
      keywordDensity = (keywordOccurrences / wordCount) * 100;
    }

    // Sentence count & Readability calculation (Flesch Reading Ease)
    final sentences = cleanContent
        .split(RegExp(r'[.!?]+(?:\s+|$)'))
        .where((s) => s.trim().isNotEmpty)
        .length;
    final safeSentences = max(1, sentences);

    int totalSyllables = 0;
    for (final word in words) {
      totalSyllables += _countSyllables(word);
    }
    final safeSyllables = max(1, totalSyllables);

    // Flesch Reading Ease formula
    double fleschScore =
        206.835 -
        (1.015 * (wordCount / safeSentences)) -
        (84.6 * (safeSyllables / max(1, wordCount)));
    fleschScore = fleschScore.clamp(0.0, 100.0);

    String readabilityGrade;
    if (fleschScore >= 80) {
      readabilityGrade = 'Very Easy';
    } else if (fleschScore >= 60) {
      readabilityGrade = 'Good / Standard';
    } else if (fleschScore >= 40) {
      readabilityGrade = 'Fairly Difficult';
    } else {
      readabilityGrade = 'Very Complex';
    }

    // Build Checklist
    final checklist = <SEOChecklistItem>[];

    // 1. Keyword Presence
    final hasKeyword = cleanKeyword.isNotEmpty;
    checklist.add(
      SEOChecklistItem(
        title: 'Target Keyword Specified',
        passed: hasKeyword,
        detail: hasKeyword
            ? 'Focus keyword is "$cleanKeyword"'
            : 'Define a target keyword for focused optimization.',
        category: 'keyword',
      ),
    );

    // 2. Keyword in First 100 Words
    final first100Words = words.take(100).join(' ');
    final keywordInFirst100 =
        hasKeyword && first100Words.contains(cleanKeyword);
    checklist.add(
      SEOChecklistItem(
        title: 'Keyword in First 100 Words',
        passed: keywordInFirst100,
        detail: keywordInFirst100 ? 'Appears early in your introduction.' : 'Include the focus keyword within your opening hook or first 100 words.',
        category: 'keyword',
      ),
    );

    // 3. Keyword Density (Ideal: 0.8% - 2.5%)
    final densityOk = keywordDensity >= 0.8 && keywordDensity <= 2.5;
    checklist.add(
      SEOChecklistItem(
        title: 'Keyword Density',
        passed: densityOk,
        detail:
            'Current density: ${keywordDensity.toStringAsFixed(1)}% ($keywordOccurrences occurrences). Ideal range: 1.0% - 2.5%.',
        category: 'keyword',
      ),
    );

    // 4. Content Length
    final minWords = contentType == 'product' ? 150 : 600;
    final lengthOk = wordCount >= minWords;
    checklist.add(
      SEOChecklistItem(
        title: 'Content Length ($minWords+ words)',
        passed: lengthOk,
        detail:
            '$wordCount words written. ${lengthOk ? 'Great depth!' : 'Add more detail to outrank competitors.'}',
        category: 'content',
      ),
    );

    // 5. Headings / Subheadings
    final minHeadings = contentType == 'product' ? 1 : 3;
    final headingsOk = headingCount >= minHeadings;
    checklist.add(
      SEOChecklistItem(
        title: 'Subheadings Hierarchy (H2 / H3)',
        passed: headingsOk,
        detail:
            '$headingCount subheadings found. Subheadings break text and keep readers engaged.',
        category: 'structure',
      ),
    );

    // 6. Links
    final linksOk = linkCount >= 1;
    checklist.add(
      SEOChecklistItem(
        title: 'Internal / External Links',
        passed: linksOk,
        detail:
            '$linkCount links present. Include citations or links to relevant internal articles.',
        category: 'structure',
      ),
    );

    // 7. Visual Media
    final imagesOk = imageCount >= 1;
    checklist.add(
      SEOChecklistItem(
        title: 'Media & Visual Elements',
        passed: imagesOk,
        detail:
            '$imageCount media items detected. Adding images improves dwell time.',
        category: 'media',
      ),
    );

    // 8. Readability
    final readabilityOk = fleschScore >= 55;
    checklist.add(
      SEOChecklistItem(
        title: 'Readability Score ($readabilityGrade)',
        passed: readabilityOk,
        detail:
            'Score: ${fleschScore.toStringAsFixed(0)}/100. ${readabilityOk ? 'Easy for audience to digest.' : 'Try shorter sentences and simpler words.'}',
        category: 'content',
      ),
    );

    // Calculate overall percentage
    double totalWeight = 0;
    double earnedWeight = 0;

    final weights = {
      'Target Keyword Specified': 15.0,
      'Keyword in First 100 Words': 15.0,
      'Keyword Density': 20.0,
      'Content Length ($minWords+ words)': 20.0,
      'Subheadings Hierarchy (H2 / H3)': 10.0,
      'Internal / External Links': 7.0,
      'Media & Visual Elements': 5.0,
      'Readability Score ($readabilityGrade)': 8.0,
    };

    for (final item in checklist) {
      final w = weights[item.title] ?? 10.0;
      totalWeight += w;
      if (item.passed) {
        earnedWeight += w;
      } else if (item.title.startsWith('Keyword Density') &&
          keywordOccurrences > 0) {
        earnedWeight += w * 0.4;
      } else if (item.title.startsWith('Content Length')) {
        earnedWeight += w * (wordCount / minWords).clamp(0.0, 0.9);
      }
    }

    final percentage = ((earnedWeight / max(1.0, totalWeight)) * 100).clamp(
      0.0,
      100.0,
    );

    // Generate Long-Tail and Competitor Lists
    final longTailKeywords = <String>[];
    final competitors = <String>[];

    return SEOAnalysisResult(
      percentage: percentage,
      wordCount: wordCount,
      characterCount: characterCount,
      headingCount: headingCount,
      linkCount: linkCount,
      imageCount: imageCount,
      keywordDensity: keywordDensity,
      keywordOccurrences: keywordOccurrences,
      readabilityScore: fleschScore,
      readabilityGrade: readabilityGrade,
      competitorList: competitors,
      longTailList: longTailKeywords,
      checklist: checklist,
    );
  }

  static int _countSyllables(String word) {
    var clean = word.toLowerCase().trim();
    if (clean.length <= 3) return 1;
    clean = clean.replaceAll(RegExp(r'(?:[^laeiouy]|ed|es|e)$'), '');
    clean = clean.replaceAll(RegExp(r'^y'), '');
    final matches = RegExp(r'[aeiouy]{1,2}').allMatches(clean);
    return max(1, matches.length);
  }
}
