class TextNormalization {
  /// Normalizes text by trimming and collapsing multiple spaces
  static String normalize(String text) {
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
  
  /// Calculates Levenshtein distance between two strings
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
          matrix[i - 1][j] + 1,      // deletion
          matrix[i][j - 1] + 1,      // insertion
          matrix[i - 1][j - 1] + cost // substitution
        ].reduce((a, b) => a < b ? a : b);
      }
    }
    
    return matrix[lenA][lenB];
  }
  
  /// Calculates similarity ratio (0.0 to 1.0) using Levenshtein distance
  static double similarityRatio(String a, String b) {
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    
    final distance = levenshteinDistance(a.toLowerCase(), b.toLowerCase());
    return 1.0 - (distance / maxLen);
  }
  
  /// Checks if two texts are similar enough (threshold 0.85 by default)
  static bool isSimilar(String a, String b, {double threshold = 0.85}) {
    return similarityRatio(a, b) >= threshold;
  }
}
