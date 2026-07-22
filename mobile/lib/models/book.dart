class Book {
  final String title;
  final String author;
  final String? isbn13;
  final double? ratingAverage;
  final int? ratingsCount;
  /// `goodreads` | `openlibrary` | `google` | null
  final String? ratingSource;

  const Book({
    required this.title,
    required this.author,
    this.isbn13,
    this.ratingAverage,
    this.ratingsCount,
    this.ratingSource,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      title: json['title'] as String,
      author: json['author'] as String,
      isbn13: json['isbn13'] as String?,
      ratingAverage: (json['rating_average'] as num?)?.toDouble(),
      ratingsCount: json['ratings_count'] as int?,
      ratingSource: json['rating_source'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      if (isbn13 != null) 'isbn13': isbn13,
      if (ratingAverage != null) 'rating_average': ratingAverage,
      if (ratingsCount != null) 'ratings_count': ratingsCount,
      if (ratingSource != null) 'rating_source': ratingSource,
    };
  }

  Book copyWith({
    String? title,
    String? author,
    String? isbn13,
    double? ratingAverage,
    int? ratingsCount,
    String? ratingSource,
  }) {
    return Book(
      title: title ?? this.title,
      author: author ?? this.author,
      isbn13: isbn13 ?? this.isbn13,
      ratingAverage: ratingAverage ?? this.ratingAverage,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      ratingSource: ratingSource ?? this.ratingSource,
    );
  }
}

class BookCandidate {
  final String title;
  final String author;
  final String? isbn13;
  final String? goodreadsUrl;
  final double? confidence;
  final double? ratingAverage;
  final int? ratingsCount;

  BookCandidate({
    required this.title,
    required this.author,
    this.isbn13,
    this.goodreadsUrl,
    this.confidence,
    this.ratingAverage,
    this.ratingsCount,
  });

  factory BookCandidate.fromJson(Map<String, dynamic> json) {
    return BookCandidate(
      title: json['title'] as String,
      author: json['author'] as String,
      isbn13: json['isbn13'] as String?,
      goodreadsUrl: json['goodreads_url'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      ratingAverage: (json['rating_average'] as num?)?.toDouble(),
      ratingsCount: json['ratings_count'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'author': author,
      if (isbn13 != null) 'isbn13': isbn13,
      if (goodreadsUrl != null) 'goodreads_url': goodreadsUrl,
      if (confidence != null) 'confidence': confidence,
      if (ratingAverage != null) 'rating_average': ratingAverage,
      if (ratingsCount != null) 'ratings_count': ratingsCount,
    };
  }

  Book toBook() => Book(
        title: title,
        author: author,
        isbn13: isbn13,
        ratingAverage: ratingAverage,
        ratingsCount: ratingsCount,
        ratingSource: null,
      );
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
            .toList() ??
        [];

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
            .toList() ??
        [];

    return ResolveGoodreadsResponse(
      status: json['status'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      goodreadsUrl: json['goodreads_url'] as String?,
      candidates: candidatesList,
    );
  }
}
