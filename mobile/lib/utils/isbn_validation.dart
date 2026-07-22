class ISBNValidator {
  /// Validates if a string is a valid ISBN-13 (978/979 prefix)
  static bool isValidISBN13(String isbn) {
    if (isbn.length != 13) return false;
    
    // Check if starts with 978 or 979
    if (!isbn.startsWith('978') && !isbn.startsWith('979')) return false;
    
    // Check if all characters are digits
    if (!isbn.runes.every((rune) => rune >= 48 && rune <= 57)) return false;
    
    // Validate checksum
    return _validateISBN13Checksum(isbn);
  }
  
  /// Validates ISBN-13 checksum
  static bool _validateISBN13Checksum(String isbn) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      int digit = int.parse(isbn[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    int checksum = (10 - (sum % 10)) % 10;
    return checksum == int.parse(isbn[12]);
  }
  
  /// Normalizes ISBN by removing dashes and spaces
  static String normalizeISBN(String isbn) {
    return isbn.replaceAll(RegExp(r'[\s-]'), '');
  }
  
  /// Converts ISBN-10 to ISBN-13 if possible
  static String? isbn10ToISBN13(String isbn10) {
    isbn10 = normalizeISBN(isbn10);
    if (isbn10.length != 10) return null;
    
    // Validate ISBN-10 checksum
    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(isbn10[i]) * (10 - i);
    }
    String checkChar = isbn10[9];
    int checkValue = (checkChar == 'X' || checkChar == 'x') ? 10 : int.parse(checkChar);
    sum += checkValue;
    
    if (sum % 11 != 0) return null;
    
    // Convert to ISBN-13
    final isbn13 = '978${isbn10.substring(0, 9)}';
    return _calculateISBN13Checksum(isbn13);
  }
  
  /// Calculates ISBN-13 checksum
  static String _calculateISBN13Checksum(String isbn12) {
    int sum = 0;
    for (int i = 0; i < 12; i++) {
      int digit = int.parse(isbn12[i]);
      sum += (i % 2 == 0) ? digit : digit * 3;
    }
    int checksum = (10 - (sum % 10)) % 10;
    return '$isbn12$checksum';
  }
}
