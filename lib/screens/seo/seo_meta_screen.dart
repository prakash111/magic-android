import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/keyword_data.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class SEOMetaScreen extends StatefulWidget {
  const SEOMetaScreen({super.key});

  @override
  State<SEOMetaScreen> createState() => _SEOMetaScreenState();
}

class _SEOMetaScreenState extends State<SEOMetaScreen> {
  final _topicController = TextEditingController(text: 'AI SEO Automation');
  final _brandController = TextEditingController(text: 'MagicAI');
  bool _isLoading = false;
  SEOMetaResult? _metaResult;

  @override
  void initState() {
    super.initState();
    _generateMeta();
  }

  @override
  void dispose() {
    _topicController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  Future<void> _generateMeta() async {
    setState(() => _isLoading = true);
    final result = await ApiService.generateSEOMeta(
      keyword: _topicController.text,
      appName: _brandController.text,
    );
    if (mounted) {
      setState(() {
        _metaResult = result;
        _isLoading = false;
      });
    }
  }

  void _copyCompleteHtml() {
    if (_metaResult == null) return;
    final html =
        '''
<title>${_metaResult!.title}</title>
<meta name="description" content="${_metaResult!.description}">
<meta name="keywords" content="${_metaResult!.keywords}">
<link rel="canonical" href="${_metaResult!.canonicalUrl}">
<meta property="og:title" content="${_metaResult!.ogTitle}">
<meta property="og:description" content="${_metaResult!.ogDescription}">
<meta property="og:url" content="${_metaResult!.canonicalUrl}">
<script type="application/ld+json">
${_metaResult!.schemaJson}
</script>''';

    Clipboard.setData(ClipboardData(text: html));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(appTr('Full HTML Meta & Schema copied to clipboard!')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(appTr('SEO Meta & Schema Generator')),
        actions: [
          IconButton(
            tooltip: appTr('Copy HTML Header'),
            icon: const Icon(Icons.code),
            onPressed: _copyCompleteHtml,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Input Fields Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _topicController,
                      decoration: InputDecoration(
                        labelText: appTr('Focus Topic / Page Subject'),
                        hintText: appTr('e.g. AI SEO Automation'),
                        prefixIcon: Icon(Icons.topic, color: AppTheme.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _brandController,
                      decoration: InputDecoration(
                        labelText: appTr('Brand / Website Name'),
                        hintText: appTr('e.g. MagicAI'),
                        prefixIcon: Icon(
                          Icons.business,
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _generateMeta,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.auto_fix_high),
                        label: Text(appTr('Generate Meta & Schema')),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (_metaResult != null) ...[
              // Google SERP Live Preview Card
              Text(
                appTr('Google Search Live Preview'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                color: const Color(0xFF1E293B),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 12,
                            backgroundColor: Color(0xFF334155),
                            child: Icon(
                              Icons.public,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _metaResult!.canonicalUrl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _metaResult!.title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF818CF8),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        appTr(_metaResult!.description),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Title Detail Card
              _buildFieldCard(
                title: appTr('Meta Title'),
                content: _metaResult!.title,
                countText: '${_metaResult!.title.length} / 60 chars',
                isOptimal:
                    _metaResult!.title.length >= 45 &&
                    _metaResult!.title.length <= 60,
              ),

              const SizedBox(height: 12),

              // Description Detail Card
              _buildFieldCard(
                title: appTr('Meta Description'),
                content: _metaResult!.description,
                countText: '${_metaResult!.description.length} / 160 chars',
                isOptimal:
                    _metaResult!.description.length >= 120 &&
                    _metaResult!.description.length <= 160,
              ),

              const SizedBox(height: 12),

              // Keywords Card
              _buildFieldCard(
                title: appTr('Focus Keywords'),
                content: _metaResult!.keywords,
                countText: 'Comma-separated',
                isOptimal: true,
              ),

              const SizedBox(height: 12),

              // Schema JSON-LD Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            appTr('JSON-LD Structured Data'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: _metaResult!.schemaJson),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(appTr('Schema JSON copied!')),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _metaResult!.schemaJson,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard({
    required String title,
    required String content,
    required String countText,
    required bool isOptimal,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  appTr(title),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (isOptimal ? AppTheme.success : AppTheme.warning)
                            .withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        appTr(countText),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isOptimal
                              ? AppTheme.success
                              : AppTheme.warning,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              appTr("Copied :title!", {"title": title}),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(
              content,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
