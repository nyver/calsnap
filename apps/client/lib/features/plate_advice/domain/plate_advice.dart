import '../../balanced_plate/domain/plate_group.dart';

/// What a suggestion asks the user to do.
enum PlateAdviceAction {
  add,
  keep,
  optionalReplace;

  String get wireName => switch (this) {
    PlateAdviceAction.add => 'ADD',
    PlateAdviceAction.keep => 'KEEP',
    PlateAdviceAction.optionalReplace => 'OPTIONAL_REPLACE',
  };

  /// Unrecognized or null input is null, so that a suggestion with an
  /// unknown action can be dropped instead of shown incorrectly.
  static PlateAdviceAction? fromWire(String? value) {
    for (final a in PlateAdviceAction.values) {
      if (a.wireName == value) return a;
    }
    return null;
  }
}

/// One piece of advice: an action, an optional plate group it targets, and
/// the text shown to the user.
class PlateAdviceSuggestion {
  const PlateAdviceSuggestion({
    required this.action,
    this.targetGroup,
    required this.title,
    required this.reason,
    this.examples = const [],
  });

  /// Returns null when the suggestion cannot be trusted: an unknown action,
  /// or an empty title or reason. An unknown [targetGroup] becomes null
  /// rather than rejecting the suggestion.
  static PlateAdviceSuggestion? fromJson(Map<String, dynamic> json) {
    final action = PlateAdviceAction.fromWire(json['action'] as String?);
    if (action == null) return null;
    final title = (json['title'] as String?)?.trim() ?? '';
    final reason = (json['reason'] as String?)?.trim() ?? '';
    if (title.isEmpty || reason.isEmpty) return null;
    final targetRaw = json['targetGroup'] as String?;
    final target = targetRaw == null ? null : PlateGroup.fromWire(targetRaw);
    return PlateAdviceSuggestion(
      action: action,
      targetGroup: target == PlateGroup.unknown ? null : target,
      title: title,
      reason: reason,
      examples: [
        for (final e in (json['examples'] as List<dynamic>? ?? const []))
          if (e is String && e.trim().isNotEmpty) e.trim(),
      ],
    );
  }

  final PlateAdviceAction action;
  final PlateGroup? targetGroup;
  final String title;
  final String reason;
  final List<String> examples;
}

/// The backend's plate-balance advice: a short summary plus 1-3 suggestions.
/// See `protocol/api/openapi.yaml` (`PlateAdviceResponse`).
class PlateAdvice {
  const PlateAdvice({required this.summary, required this.suggestions});

  /// Parses defensively: an unacceptable suggestion is dropped rather than
  /// failing the whole response. The caller treats an empty [suggestions]
  /// list like an invalid response.
  factory PlateAdvice.fromJson(Map<String, dynamic> json) {
    final summary = (json['summary'] as String?)?.trim() ?? '';
    final raw = json['suggestions'];
    final suggestions = <PlateAdviceSuggestion>[
      if (raw is List)
        for (final entry in raw)
          if (entry is Map<String, dynamic>)
            ?PlateAdviceSuggestion.fromJson(entry),
    ];
    return PlateAdvice(summary: summary, suggestions: suggestions);
  }

  final String summary;
  final List<PlateAdviceSuggestion> suggestions;
}
