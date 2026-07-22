class TextNormalization {
  static final _pricePattern = RegExp(
    r'(€|\$|£|\d+[.,]\d{2}\s*(€|eur|usd)?)',
    caseSensitive: false,
  );
  static final _editionPattern = RegExp(
    r'\b(\d+\s*(ª|a|th|st|nd|rd)?\s*)?(edici[oó]n|edition|ed\.?)\b',
    caseSensitive: false,
  );
  static final _isbnPattern = RegExp(r'\b97[89][\d\- ]{10,}\b');
  static final _publisherNoise = RegExp(
    r'\b(penguin|planeta|anagrama|debolsillo|nova|plaza|random|house|harper|collins|tor|orbis)\b',
    caseSensitive: false,
  );

  /// Normalizes text by trimming and collapsing multiple spaces
  static String normalize(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Extracts 1–2 title-like lines from raw OCR (drops edition, price, ISBN noise).
  static String extractTitleQuery(String rawOcr, {int minLength = 10}) {
    final lines = rawOcr
        .split(RegExp(r'[\r\n]+'))
        .map(normalize)
        .where((line) => line.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      final flat = normalize(rawOcr);
      return flat.length >= minLength ? flat : '';
    }

    final scored = <({String line, double score})>[];
    for (final line in lines) {
      if (_shouldDiscardLine(line)) continue;
      scored.add((line: line, score: _lineScore(line)));
    }

    if (scored.isEmpty) {
      final flat = normalize(rawOcr);
      return flat.length >= minLength ? flat : '';
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final top = scored.take(2).map((e) => e.line).toList();
    final query = normalize(top.join(' '));
    return query.length >= minLength ? query : (top.first.length >= 8 ? top.first : '');
  }

  static bool _shouldDiscardLine(String line) {
    if (line.length < 3) return true;
    if (_pricePattern.hasMatch(line)) return true;
    if (_editionPattern.hasMatch(line) && line.length < 24) return true;
    if (_isbnPattern.hasMatch(line) && line.length < 20) return true;
    final letters = line.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), '');
    if (letters.isEmpty) return true;
    final letterRatio = letters.length / line.length;
    if (letterRatio < 0.45) return true;
    // Short ALL-CAPS publisher stamps when longer title lines exist elsewhere.
    if (line.length <= 12 &&
        line == line.toUpperCase() &&
        _publisherNoise.hasMatch(line)) {
      return true;
    }
    return false;
  }

  static double _lineScore(String line) {
    final len = line.length.clamp(1, 80);
    final letters = line.replaceAll(RegExp(r'[^A-Za-zÁÉÍÓÚÜÑáéíóúüñ]'), '');
    final letterRatio = letters.length / line.length;
    var score = len * 1.0 + letterRatio * 40;
    if (len >= 8 && len <= 60) score += 25;
    if (len > 70) score -= 20;
    if (_editionPattern.hasMatch(line)) score -= 15;
    if (_publisherNoise.hasMatch(line) && line.length < 20) score -= 10;
    return score;
  }

  static int levenshteinDistance(String a, String b) {
    final lenA = a.length;
    final lenB = b.length;

    if (lenA == 0) return lenB;
    if (lenB == 0) return lenA;

    final matrix = List.generate(lenA + 1, (i) => List.filled(lenB + 1, 0));

    for (int i = 0; i <= lenA; i++) {
      matrix[i][0] = i;
    }
    for (int j = 0; j <= lenB; j++) {
      matrix[0][j] = j;
    }

    for (int i = 1; i <= lenA; i++) {
      for (int j = 1; j <= lenB; j++) {
        final cost = (a[i - 1] == b[j - 1]) ? 0 : 1;
        matrix[i][j] = [
          matrix[i - 1][j] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j - 1] + cost,
        ].reduce((a, b) => a < b ? a : b);
      }
    }

    return matrix[lenA][lenB];
  }

  static double similarityRatio(String a, String b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;

    final distance = levenshteinDistance(a.toLowerCase(), b.toLowerCase());
    return 1.0 - (distance / maxLen);
  }

  /// Variable threshold: more permissive for short strings (README §8).
  static double similarityThresholdFor(String a, String b) {
    final len = a.length < b.length ? a.length : b.length;
    if (len < 20) return 0.75;
    return 0.85;
  }

  static bool isSimilar(String a, String b, {double? threshold}) {
    final t = threshold ?? similarityThresholdFor(a, b);
    return similarityRatio(a, b) >= t;
  }
}
