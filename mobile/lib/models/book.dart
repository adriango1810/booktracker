class Book {
  final String title;
  final String author;
  final String? isbn13;
  
  const Book({
    required this.title,
    required this.author,
    this.isbn13,
  });
  
  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      title: json['title'] as String,
      author: json['author'] as String,
      isbn13: json['isbn13'] as String?,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      if (isbn13 != null) 'isbn13': isbn13,
    };
  }
}

class BookCandidate {
  final String title;
  final String author;
  final String? isbn13;
  final String? goodreadsUrl;
  final double? confidence;
  
  BookCandidate({
    required this.title,
    required this.author,
    this.isbn13,
    this.goodreadsUrl,
    this.confidence,
  });
  
  factory BookCandidate.fromJson(Map<String, dynamic> json) {
    return BookCandidate(
      title: json['title'] as String,
      author: json['author'] as String,
      isbn13: json['isbn13'] as String?,
      goodreadsUrl: json['goodreads_url'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      if (isbn13 != null) 'isbn13': isbn13,
      if (goodreadsUrl != null) 'goodreads_url': goodreadsUrl,
      if (confidence != null) 'confidence': confidence,
    };
  }
}

class IdentifyBookResponse {
  final String status;
  final double confidence;
  final Book? book;
  final List<BookCandidate> candidates;
  final String reason;
  
  IdentifyBookResponse({
    required this.status,
    required this.confidence,
    this.book,
    this.candidates = const [],
    required this.reason,
  });
  
  factory IdentifyBookResponse.fromJson(Map<String, dynamic> json) {
    final book = json['book'] != null 
        ? Book.fromJson(json['book'] as Map<String, dynamic>) 
        : null;
    
    final candidatesList = (json['candidates'] as List<dynamic>?)
        ?.map((c) => BookCandidate.fromJson(c as Map<String, dynamic>))
        .toList() ?? [];
    
    return IdentifyBookResponse(
      status: json['status'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      book: book,
      candidates: candidatesList,
      reason: json['reason'] as String? ?? '',
    );
  }
}

class ResolveGoodreadsResponse {
  final String status;
  final double confidence;
  final String? goodreadsUrl;
  final List<BookCandidate> candidates;
  
  ResolveGoodreadsResponse({
    required this.status,
    required this.confidence,
    this.goodreadsUrl,
    this.candidates = const [],
  });
  
  factory ResolveGoodreadsResponse.fromJson(Map<String, dynamic> json) {
    final candidatesList = (json['candidates'] as List<dynamic>?)
        ?.map((c) => BookCandidate.fromJson(c as Map<String, dynamic>))
        .toList() ?? [];
    
    return ResolveGoodreadsResponse(
      status: json['status'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      goodreadsUrl: json['goodreads_url'] as String?,
      candidates: candidatesList,
    );
  }
}
