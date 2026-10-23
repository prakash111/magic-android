import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/keyword_data.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class KeywordResearchScreen extends StatefulWidget {
  const KeywordResearchScreen({super.key});

  @override
  State<KeywordResearchScreen> createState() => _KeywordResearchScreenState();
}

class _KeywordResearchScreenState extends State<KeywordResearchScreen> {
  final _searchController = TextEditingController(text: 'ai productivity');
  bool _isLoading = false;
  List<KeywordItem> _keywords = [];

  @override
  void initState() {
    super.initState();
    _fetchKeywords();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchKeywords() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isLoading = true);
    final results = await ApiService.suggestKeywords(query);
    if (mounted) {
      setState(() {
        _keywords = results;
        _isLoading = false;
      });
    }
  }

  void _copyAll() {
    if (_keywords.isEmpty) return;
    final buffer = StringBuffer();
    buffer.writeln('Keyword,Volume,CPC,Difficulty,Intent');
    for (final kw in _keywords) {
      buffer.writeln(
        '${kw.keyword},${kw.volume},\$${kw.cpc.toStringAsFixed(2)},${kw.difficulty}%,${kw.intent}',
      );
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All keywords copied as CSV!')),
    );
  }

  Color _getDifficultyColor(int diff) {
    if (diff < 35) return AppTheme.success;
    if (diff < 65) return AppTheme.warning;
    return AppTheme.error;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyword Research & Wizard'),
        actions: [
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.download_outlined),
            onPressed: _copyAll,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search Input Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Enter seed topic or keyword...',
                      prefixIcon: Icon(Icons.search, color: AppTheme.primary),
                    ),
                    onSubmitted: (_) => _fetchKeywords(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _fetchKeywords,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 15,
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Discover'),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Header summary
            if (_keywords.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_keywords.length} Keyword Opportunities Found',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _copyAll,
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy All'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            // Results List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _keywords.isEmpty
                  ? const Center(
                      child: Text(
                        'No keywords found. Try another query.',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _keywords.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final kw = _keywords[index];
                        final diffColor = _getDifficultyColor(kw.difficulty);

                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        kw.keyword,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 18),
                                      tooltip: 'Copy Keyword',
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(text: kw.keyword),
                                        );
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Copied "${kw.keyword}"',
                                                ),
                                              ),
                                            );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    _buildPill(
                                      icon: Icons.bar_chart,
                                      label: '${kw.volume}/mo',
                                      color: AppTheme.primary,
                                    ),
                                    _buildPill(
                                      icon: Icons.attach_money,
                                      label:
                                          '\$${kw.cpc.toStringAsFixed(2)} CPC',
                                      color: AppTheme.accent,
                                    ),
                                    _buildPill(
                                      icon: Icons.speed,
                                      label: '${kw.difficulty}% Diff',
                                      color: diffColor,
                                    ),
                                    _buildPill(
                                      icon: Icons.flag_outlined,
                                      label: kw.intent,
                                      color: AppTheme.textMuted,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
