import 'dart:math' as math;

import 'package:flutter/services.dart';

import 'ai_model_selection.dart';
import 'mobile_api.dart';
import 'social_post_service.dart';

class DocumentAiSelection {
  final String original;
  final int start, end;
  DocumentAiSelection(this.original, TextSelection? selection)
    : start =
          selection != null &&
              selection.isValid &&
              !selection.isCollapsed &&
              selection.end <= original.length
          ? selection.start
          : 0,
      end =
          selection != null &&
              selection.isValid &&
              !selection.isCollapsed &&
              selection.end <= original.length
          ? selection.end
          : original.length;
  bool get selected => start != 0 || end != original.length;
  String get text => original.substring(start, end);
  String get context {
    if (!selected) return '';
    final from = math.max(0, start - 6000);
    final to = math.min(original.length, end + 6000);
    return original.substring(from, math.min(to, from + 60000));
  }

  String apply(String replacement, String action) {
    if (action != 'extend') {
      return original.replaceRange(start, end, replacement);
    }
    String separator(String value) => value.endsWith('\n\n')
        ? ''
        : value.endsWith('\n')
        ? '\n'
        : '\n\n';
    final before = original.substring(0, end), after = original.substring(end);
    return '$before${separator(before)}${replacement.trim()}${after.isEmpty ? '' : '\n\n$after'}';
  }
}

class DocumentAiProposal {
  final String original, suggested, action, model;
  final bool selectionOnly;
  const DocumentAiProposal({
    required this.original,
    required this.suggested,
    required this.action,
    required this.model,
    required this.selectionOnly,
  });
}

class DocumentAssistant {
  final MobileApi api;
  const DocumentAssistant(this.api);
  Future<DocumentAiProposal> propose({
    required int documentId,
    required DocumentAiSelection selection,
    required String action,
    String instruction = '',
    String? requestId,
  }) async {
    if (selection.text.trim().isEmpty) {
      throw const ApiFailure('Enter or select some document text first.');
    }
    if (selection.text.length > 60000) {
      throw const ApiFailure(
        'Select a section of fewer than 60,000 characters.',
      );
    }
    if (action == 'refine' && instruction.trim().isEmpty) {
      throw const ApiFailure('Describe the changes you would like.');
    }
    final choices = AiModelSelection(api);
    final models = await choices.models();
    final model = await choices.resolve(models);
    if (model == null) {
      throw const ApiFailure(
        'No text model is enabled for your plan. Contact your administrator.',
      );
    }
    final result = await api.request(
      '/documents/$documentId/assist',
      method: 'POST',
      body: {
        'action': action,
        'content': selection.text,
        if (selection.context.isNotEmpty) 'context': selection.context,
        'instruction': instruction.trim(),
        'model': model,
        'request_id': requestId ?? SocialPostService.requestId(),
      },
    );
    if (result is! Map ||
        result['replacement'] is! String ||
        (result['replacement'] as String).trim().isEmpty) {
      throw const ApiFailure(
        'The AI returned no text. Your document is unchanged. Please retry.',
      );
    }
    return DocumentAiProposal(
      original: selection.original,
      suggested: selection.apply(result['replacement'] as String, action),
      action: action,
      model: model,
      selectionOnly: selection.selected,
    );
  }
}
