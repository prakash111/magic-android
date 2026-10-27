import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/seo_analysis_result.dart';
import '../../models/saved_document.dart';
import '../../services/api_service.dart';
import '../../services/storage_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/score_gauge.dart';
import '../../widgets/stat_card.dart';

class SEOAnalyzerScreen extends StatefulWidget {
  const SEOAnalyzerScreen({super.key});

  @override
  State<SEOAnalyzerScreen> createState() => _SEOAnalyzerScreenState();
}

class _SEOAnalyzerScreenState extends State<SEOAnalyzerScreen>
    with SingleTickerProviderStateMixin {
  final _keywordController = TextEditingController(
    text: 'ai content marketing',
  );
  final _contentController = TextEditingController();

  String _contentType = 'article'; // 'article' or 'product'
  bool _isLoading = false;
  bool _isImproving = false;
  SEOAnalysisResult? _result;

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSampleContent();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    _contentController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _loadSampleContent() {
    _contentController.text = '''# The Power of AI Content Marketing in 2026

AI content marketing is revolutionizing how modern brands connect with their target audience. By combining generative AI algorithms with high-intent keyword strategies, marketers can produce high-quality blog posts at scale.

## Why AI Content Marketing Matters

Traditional content creation workflows often take days for research, drafting, and proofreading. Today, AI content marketing tools analyze competitor SERPs, detect long-tail keyword opportunities, and automate draft creation in minutes.

### Key Benefits of AI Optimization
1. **Faster Time to Publish**: Reduce production cycles by up to 70%.
2. **Data-Driven Keyword Density**: Optimize on-page SEO without keyword stuffing.
3. **Enhanced Readability**: Tailor tone of voice and reading levels for your exact demographics.

## Implementing Your AI Strategy

To get started with AI content marketing, audit your existing website content, identify ranking gaps, and incorporate relevant internal links: [Learn more about SEO](https://ai.zoomnearby.com).

![AI Content Dashboard](https://ai.zoomnearby.com/assets/img/dashboard.png)

## Conclusion

Embracing AI content marketing early ensures sustainable organic traffic and protects your site against algorithmic volatility.''';

    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    setState(() => _isLoading = true);
    final res = await ApiService.analyzeArticle(
      content: _contentController.text,
      keyword: _keywordController.text,
      contentType: _contentType,
    );
    if (mounted) {
      setState(() {
        _result = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _improveWithAI() async {
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr('Please enter content to improve.'))),
      );
      return;
    }

    setState(() => _isImproving = true);
    final improved = await ApiService.improveArticle(
      content: _contentController.text,
      keyword: _keywordController.text,
      longTailList: _result?.longTailList ?? [],
      competitorList: _result?.competitorList ?? [],
    );

    if (mounted) {
      setState(() => _isImproving = false);
      _showImprovementModal(improved);
    }
  }

  void _showImprovementModal(String improvedText) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        AppLocalizations.watch(context);
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            AppLocalizations.watch(context);
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Text(
                        appTr('AI Enhanced Content'),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: AppTheme.borderDark),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: SelectableText(
                        improvedText,
                        style: const TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: improvedText),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(appTr('Copied to clipboard!')),
                              ),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 18),
                          label: Text(appTr('Copy')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _contentController.text = improvedText;
                            });
                            Navigator.pop(context);
                            _runAnalysis();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  appTr('Content replaced in editor!'),
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(appTr('Apply to Editor')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveReport() async {
    if (_result == null) return;
    final doc = SavedDocument(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'SEO Audit: ${_keywordController.text}',
      content: _contentController.text,
      type: 'seo',
      createdAt: DateTime.now(),
      metadata: {
        'score': _result!.percentage,
        'keyword': _keywordController.text,
        'wordCount': _result!.wordCount,
      },
    );
    await StorageService.saveDocument(doc);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(appTr('Report saved to Documents!'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appTr('SEO Article Optimizer')),
        actions: [
          IconButton(
            tooltip: appTr('Save Report'),
            icon: const Icon(Icons.bookmark_border),
            onPressed: _saveReport,
          ),
          IconButton(
            tooltip: appTr('Load Sample'),
            icon: const Icon(Icons.refresh),
            onPressed: _loadSampleContent,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Controls Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _keywordController,
                            decoration: InputDecoration(
                              labelText: appTr('Focus Target Keyword'),
                              prefixIcon: Icon(
                                Icons.key,
                                color: AppTheme.primary,
                              ),
                              hintText: appTr('e.g. ai tools'),
                            ),
                            onChanged: (_) => _runAnalysis(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            initialValue: _contentType,
                            decoration: InputDecoration(
                              labelText: appTr('Type'),
                            ),
                            items: [
                              DropdownMenuItem(
                                value: 'article',
                                child: Text(appTr('Blog/Article')),
                              ),
                              DropdownMenuItem(
                                value: 'product',
                                child: Text(appTr('Product Desc')),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setState(() => _contentType = val);
                                _runAnalysis();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _contentController,
                      maxLines: 8,
                      decoration: InputDecoration(
                        labelText: appTr('Article Content / Markdown'),
                        hintText: appTr('Paste or type your draft here...'),
                        alignLabelWithHint: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _contentController.clear();
                            _runAnalysis();
                          },
                        ),
                      ),
                      onChanged: (_) => _runAnalysis(),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _runAnalysis,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.analytics_outlined,
                                    size: 18,
                                  ),
                            label: Text(appTr('Analyze Content')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                            ),
                            onPressed: _isImproving ? null : _improveWithAI,
                            icon: _isImproving
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome, size: 18),
                            label: Text(appTr('AI Improve')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Results Section
            if (_result != null) ...[
              // Score Banner Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
                  child: Row(
                    children: [
                      ScoreGauge(score: _result!.percentage),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              appTr(
                                _result!.percentage >= 75
                                    ? 'Well-Optimized! 🚀'
                                    : _result!.percentage >= 50
                                    ? 'Needs Fine-Tuning ⚠️'
                                    : 'Low SEO Potential ❌',
                              ),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              appTr(
                                "Target Keyword Density: :value% (:keywordOccurrencesx)",
                                {
                                  "value": _result!.keywordDensity
                                      .toStringAsFixed(1),
                                  "keywordOccurrences":
                                      _result!.keywordOccurrences,
                                },
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              appTr(
                                "Readability: :readabilityGrade (:value/100)",
                                {
                                  "readabilityGrade": _result!.readabilityGrade,
                                  "value": _result!.readabilityScore
                                      .toStringAsFixed(0),
                                },
                              ),
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Metrics Row
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      title: appTr('Words'),
                      value: '${_result!.wordCount}',
                      icon: Icons.text_fields,
                      iconColor: AppTheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      title: appTr('Headings'),
                      value: '${_result!.headingCount}',
                      icon: Icons.title,
                      iconColor: AppTheme.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: StatCard(
                      title: appTr('Links'),
                      value: '${_result!.linkCount}',
                      icon: Icons.link,
                      iconColor: AppTheme.success,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: StatCard(
                      title: appTr('Images'),
                      value: '${_result!.imageCount}',
                      icon: Icons.image_outlined,
                      iconColor: AppTheme.warning,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Detailed Tabs
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'SEO Checklist'),
                  Tab(text: 'Keywords'),
                  Tab(text: 'Competitors'),
                ],
              ),
              const SizedBox(height: 12),

              SizedBox(
                height: 380,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Checklist Tab
                    ListView.separated(
                      itemCount: _result!.checklist.length,
                      separatorBuilder: (context, index) {
                        AppLocalizations.watch(context);
                        return const SizedBox(height: 8);
                      },
                      itemBuilder: (context, index) {
                        AppLocalizations.watch(context);
                        final item = _result!.checklist[index];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              item.passed
                                  ? Icons.check_circle
                                  : Icons.cancel_outlined,
                              color: item.passed
                                  ? AppTheme.success
                                  : AppTheme.error,
                            ),
                            title: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              appTr(item.detail),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    // Keywords Tab
                    ListView(
                      children: [
                        Text(
                          appTr('Recommended Long-Tail Keywords'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._result!.longTailList.map(
                          (kw) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.trending_up, size: 20),
                              title: Text(
                                kw,
                                style: const TextStyle(fontSize: 14),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 20,
                                ),
                                tooltip: appTr('Insert into text'),
                                onPressed: () {
                                  setState(() {
                                    _contentController.text += '\n$kw';
                                  });
                                  _runAnalysis();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        appTr("Added \":kw\" to draft", {
                                          "kw": kw,
                                        }),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Competitors Tab
                    ListView(
                      children: [
                        Text(
                          appTr('Top Ranking Competitor Domains'),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warning,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ..._result!.competitorList.map(
                          (comp) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.public, size: 20),
                              title: Text(
                                comp,
                                style: const TextStyle(fontSize: 14),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: comp));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        appTr("Copied \":comp\"", {
                                          "comp": comp,
                                        }),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
