import 'dart:math' as math;

import '../utils/text_normalization.dart';

/// Lightweight token-set similarity (approx. RapidFuzz token_set_ratio).
class FuzzyMatch {
  FuzzyMatch._();

  static Set<String> _tokens(String text) {
    return text
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9áéíóúüñ]+', caseSensitive: false))
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  static String _sortedJoin(Iterable<String> tokens) {
    final list = tokens.toList()..sort();
    return list.join(' ');
  }

  static double tokenSetRatio(String a, String b) {
    final ta = _tokens(a);
    final tb = _tokens(b);
    if (ta.isEmpty && tb.isEmpty) return 1.0;
    if (ta.isEmpty || tb.isEmpty) return 0.0;

    final intersection = ta.intersection(tb);
    final diffA = ta.difference(tb);
    final diffB = tb.difference(ta);

    final sortedInter = _sortedJoin(intersection);
    final sortedA = _sortedJoin([...intersection, ...diffA]);
    final sortedB = _sortedJoin([...intersection, ...diffB]);

    if (sortedInter.isEmpty) {
      return TextNormalization.similarityRatio(sortedA, sortedB);
    }

    return math.max(
      TextNormalization.similarityRatio(sortedInter, sortedA),
      math.max(
        TextNormalization.similarityRatio(sortedInter, sortedB),
        TextNormalization.similarityRatio(sortedA, sortedB),
      ),
    );
  }
}
