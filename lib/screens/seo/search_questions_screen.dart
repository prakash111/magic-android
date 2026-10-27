import '../../services/app_localizations.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/keyword_data.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';

class SearchQuestionsScreen extends StatefulWidget {
  const SearchQuestionsScreen({super.key});

  @override
  State<SearchQuestionsScreen> createState() => _SearchQuestionsScreenState();
}

class _SearchQuestionsScreenState extends State<SearchQuestionsScreen> {
  final _searchController = TextEditingController(text: 'flutter development');
  bool _isLoading = false;
  List<SearchQuestionItem> _questions = [];
  String _selectedFilter = 'All';

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchQuestions() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() => _isLoading = true);
    final results = await ApiService.getSearchQuestions(query);
    if (mounted) {
      setState(() {
        _questions = results;
        _isLoading = false;
      });
    }
  }

  List<SearchQuestionItem> get _filteredQuestions {
    if (_selectedFilter == 'All') return _questions;
    return _questions
        .where((q) => q.category.toLowerCase() == _selectedFilter.toLowerCase())
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    AppLocalizations.watch(context);

    const categories = ['All', 'What', 'How', 'Why', 'Can/Is'];

    return Scaffold(
      appBar: AppBar(title: Text(appTr('People Also Ask (PAA)'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: appTr('Enter topic for search questions...'),
                      prefixIcon: Icon(
                        Icons.help_outline,
                        color: AppTheme.primary,
                      ),
                    ),
                    onSubmitted: (_) => _fetchQuestions(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isLoading ? null : _fetchQuestions,
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
                      : Text(appTr('Search')),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Category filter chips
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (context, index) {
                  AppLocalizations.watch(context);
                  return const SizedBox(width: 8);
                },
                itemBuilder: (context, index) {
                  AppLocalizations.watch(context);
                  final cat = categories[index];
                  final isSelected = _selectedFilter == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (val) {
                      if (val) setState(() => _selectedFilter = cat);
                    },
                    selectedColor: AppTheme.primary,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : AppTheme.textMuted,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            // Questions List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredQuestions.isEmpty
                  ? Center(
                      child: Text(
                        appTr('No search questions found.'),
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _filteredQuestions.length,
                      separatorBuilder: (context, index) {
                        AppLocalizations.watch(context);
                        return const SizedBox(height: 10);
                      },
                      itemBuilder: (context, index) {
                        AppLocalizations.watch(context);
                        final item = _filteredQuestions[index];
                        return Card(
                          child: ExpansionTile(
                            leading: CircleAvatar(
                              backgroundColor: AppTheme.primary.withOpacity(
                                0.15,
                              ),
                              foregroundColor: AppTheme.primary,
                              radius: 16,
                              child: Text(
                                item.category.substring(0, 1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              item.question,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              appTr("Category: :value", {
                                "value": item.category,
                              }),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.snippet,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        height: 1.5,
                                        color: AppTheme.textLight,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton.icon(
                                          onPressed: () {
                                            Clipboard.setData(
                                              ClipboardData(
                                                text:
                                                    '${item.question}\n\n${item.snippet}',
                                              ),
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  appTr(
                                                    'Copied question & answer!',
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.copy,
                                            size: 16,
                                          ),
                                          label: Text(appTr('Copy QA')),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
}
