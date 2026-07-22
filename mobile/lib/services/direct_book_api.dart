import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/book.dart';
import '../utils/fuzzy_match.dart';
import '../utils/isbn_validation.dart';
import '../utils/text_normalization.dart';
import 'book_api.dart';

/// Identifies books by calling Open Library directly from the device.
/// No home-PC backend required — works on Wi‑Fi or mobile data.
class DirectBookApi implements BookApi {
  DirectBookApi({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 12),
                headers: {'User-Agent': 'BookScannerPersonal/1.0'},
              ),
            );

  final Dio _dio;

  static const _isbnUrl = 'https://openlibrary.org/isbn';
  static const _searchUrl = 'https://openlibrary.org/search.json';
  static const _goodreadsSearch = 'https://www.goodreads.com/search?q=';

  static const _knownGoodreads = <String, String>{
    'el nombre del viento':
        'https://www.goodreads.com/book/show/186074',
    '9788401020236': 'https://www.goodreads.com/book/show/186074',
  };

  @override
  Future<IdentifyBookResponse> identifyBook({
    String? isbn,
    String? ocrText,
    required String locale,
    required String device,
  }) async {
    if (isbn != null && isbn.isNotEmpty) {
      return _identifyByIsbn(isbn);
    }
    if (ocrText != null && ocrText.isNotEmpty) {
      return _identifyByOcr(ocrText);
    }
    throw ArgumentError('Either isbn or ocr_text must be provided');
  }

  @override
  Future<ResolveGoodreadsResponse> resolveGoodreads({
    required String title,
    required String author,
    String? isbn13,
  }) async {
    final titleKey = title.toLowerCase().trim();
    if (_knownGoodreads.containsKey(titleKey)) {
      return ResolveGoodreadsResponse(
        status: 'ok',
        confidence: 0.9,
        goodreadsUrl: _knownGoodreads[titleKey],
      );
    }
    if (isbn13 != null && _knownGoodreads.containsKey(isbn13)) {
      return ResolveGoodreadsResponse(
        status: 'ok',
        confidence: 0.9,
        goodreadsUrl: _knownGoodreads[isbn13],
      );
    }

    if (isbn13 != null && isbn13.length >= 10) {
      return ResolveGoodreadsResponse(
        status: 'ok',
        confidence: 0.9,
        goodreadsUrl: '$_goodreadsSearch${Uri.encodeComponent(isbn13)}',
      );
    }

    var confidence = 0.78;
    var searchUrl =
        '$_goodreadsSearch${Uri.encodeComponent('$title $author'.trim())}';

    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        _searchUrl,
        queryParameters: {
          'q': '$title $author'.trim(),
          'limit': 1,
        },
      );
      final docs = (resp.data?['docs'] as List<dynamic>?) ?? [];
      if (docs.isNotEmpty) {
        final doc = docs.first as Map<String, dynamic>;
        final olTitle = (doc['title'] as String?) ?? title;
        final authors = doc['author_name'] as List<dynamic>?;
        final olAuthor =
            (authors != null && authors.isNotEmpty)
                ? authors.first.toString()
                : author;
        final ratio = FuzzyMatch.tokenSetRatio(
          '$title $author',
          '$olTitle $olAuthor',
        );
        confidence = math.max(confidence, math.min(0.92, ratio));
        if (ratio >= 0.85) {
          searchUrl =
              '$_goodreadsSearch${Uri.encodeComponent('$olTitle $olAuthor')}';
          return ResolveGoodreadsResponse(
            status: 'ok',
            confidence: confidence,
            goodreadsUrl: searchUrl,
          );
        }
      }
    } catch (e) {
      debugPrint('DirectBookApi resolve refine: $e');
    }

    if (confidence >= 0.85) {
      return ResolveGoodreadsResponse(
        status: 'ok',
        confidence: confidence,
        goodreadsUrl: searchUrl,
      );
    }

    return ResolveGoodreadsResponse(
      status: 'ok',
      confidence: confidence,
      candidates: [
        BookCandidate(
          title: title,
          author: author,
          isbn13: isbn13,
          goodreadsUrl: searchUrl,
          confidence: confidence,
        ),
      ],
    );
  }

  Future<IdentifyBookResponse> _identifyByIsbn(String rawIsbn) async {
    final isbn = ISBNValidator.normalizeISBN(rawIsbn);
    try {
      final resp = await _dio.get<Map<String, dynamic>>('$_isbnUrl/$isbn.json');
      if (resp.statusCode == 200 && resp.data != null) {
        final data = resp.data!;
        final title = (data['title'] as String?) ?? 'Libro desconocido';
        final author = await _resolveAuthor(data['authors']);
        return IdentifyBookResponse(
          status: 'ok',
          confidence: 0.95,
          book: Book(title: title, author: author, isbn13: isbn),
          reason: 'isbn_exact_match',
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode != 404) {
        debugPrint('DirectBookApi isbn.json: $e');
      }
    }

    try {
      final search = await _dio.get<Map<String, dynamic>>(
        _searchUrl,
        queryParameters: {'isbn': isbn, 'limit': 1},
      );
      final docs = (search.data?['docs'] as List<dynamic>?) ?? [];
      if (docs.isNotEmpty) {
        final doc = docs.first as Map<String, dynamic>;
        return IdentifyBookResponse(
          status: 'ok',
          confidence: 0.92,
          book: Book(
            title: (doc['title'] as String?) ?? 'Libro desconocido',
            author: _authorFromDoc(doc),
            isbn13: isbn,
          ),
          reason: 'isbn_search_match',
        );
      }
    } catch (e) {
      debugPrint('DirectBookApi isbn search: $e');
    }

    return IdentifyBookResponse(
      status: 'error',
      confidence: 0.0,
      reason: 'isbn_not_found',
    );
  }

  Future<IdentifyBookResponse> _identifyByOcr(String ocrText) async {
    var query = TextNormalization.extractTitleQuery(ocrText);
    if (query.isEmpty) {
      query = TextNormalization.normalize(ocrText);
    }
    if (query.length > 80) {
      final cut = query.substring(0, 80);
      final space = cut.lastIndexOf(' ');
      query = space > 20 ? cut.substring(0, space) : cut;
    }
    if (query.length < 5) {
      return IdentifyBookResponse(
        status: 'error',
        confidence: 0.0,
        reason: 'query_too_short',
      );
    }

    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        _searchUrl,
        queryParameters: {'q': query, 'limit': 8},
      );
      final docs = (resp.data?['docs'] as List<dynamic>?) ?? [];
      if (docs.isEmpty) {
        return IdentifyBookResponse(
          status: 'error',
          confidence: 0.0,
          reason: 'no_match',
        );
      }

      final scored = <({double score, BookCandidate book})>[];
      for (final raw in docs) {
        final doc = raw as Map<String, dynamic>;
        final title = ((doc['title'] as String?) ?? '').trim();
        if (title.isEmpty) continue;
        final author = _authorFromDoc(doc);
        final titleScore = FuzzyMatch.tokenSetRatio(query, title);
        final combined =
            FuzzyMatch.tokenSetRatio(query, '$title $author') * 0.95;
        var score = titleScore > combined ? titleScore : combined;
        if (title.length >= 8 && title.length <= 60) {
          score = math.min(1.0, score + 0.03);
        }

        scored.add((
          score: score,
          book: BookCandidate(
            title: title,
            author: author,
            isbn13: _isbnFromDoc(doc),
            confidence: score,
          ),
        ));
      }

      if (scored.isEmpty) {
        return IdentifyBookResponse(
          status: 'error',
          confidence: 0.0,
          reason: 'no_match',
        );
      }

      scored.sort((a, b) => b.score.compareTo(a.score));
      final best = scored.first;
      final pool = scored
          .where((e) => e.score >= 0.55)
          .take(3)
          .map((e) => e.book)
          .toList();

      if (best.score >= 0.85) {
        return IdentifyBookResponse(
          status: 'ok',
          confidence: best.score,
          book: Book(
            title: best.book.title,
            author: best.book.author,
            isbn13: best.book.isbn13,
          ),
          reason: 'ocr_strong_match',
        );
      }

      if (best.score >= 0.60) {
        return IdentifyBookResponse(
          status: 'ok',
          confidence: best.score,
          candidates: pool,
          reason: 'ocr_ambiguous',
        );
      }

      return IdentifyBookResponse(
        status: 'error',
        confidence: best.score,
        reason: 'ocr_weak_match',
      );
    } catch (e) {
      debugPrint('DirectBookApi ocr: $e');
      return IdentifyBookResponse(
        status: 'error',
        confidence: 0.0,
        reason: 'search_failed',
      );
    }
  }

  Future<String> _resolveAuthor(dynamic authorsField) async {
    if (authorsField is! List || authorsField.isEmpty) {
      return 'Autor desconocido';
    }
    final first = authorsField.first;
    if (first is! Map) return 'Autor desconocido';
    final key = first['key'] as String?;
    if (key == null || key.isEmpty) return 'Autor desconocido';
    try {
      final resp =
          await _dio.get<Map<String, dynamic>>('https://openlibrary.org$key.json');
      return (resp.data?['name'] as String?) ?? 'Autor desconocido';
    } catch (_) {
      return key.split('/').last;
    }
  }

  String _authorFromDoc(Map<String, dynamic> doc) {
    final authors = doc['author_name'] as List<dynamic>?;
    if (authors == null || authors.isEmpty) return 'Autor desconocido';
    return authors.first.toString();
  }

  String? _isbnFromDoc(Map<String, dynamic> doc) {
    final list = doc['isbn'] as List<dynamic>?;
    if (list == null || list.isEmpty) return null;
    for (final item in list) {
      final s = item.toString();
      if (s.length == 13) return s;
    }
    return list.first.toString();
  }
}
