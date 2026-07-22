import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class GoodreadsMeta {
  const GoodreadsMeta({
    required this.averageRating,
    this.ratingsCount,
    this.bookUrl,
    this.author,
  });

  final double averageRating;
  final int? ratingsCount;
  final String? bookUrl;
  final String? author;
}

/// Lightweight fetch of Goodreads book page by ISBN (personal use).
/// Fragile: HTML/JSON shape can change; prefer structured fields when present.
class GoodreadsScraper {
  GoodreadsScraper({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 15),
                followRedirects: true,
                maxRedirects: 5,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                  'Accept-Language': 'en-US,en;q=0.9,es;q=0.8',
                },
                responseType: ResponseType.plain,
                validateStatus: (code) => code != null && code >= 200 && code < 400,
              ),
            );

  final Dio _dio;

  static final _avgRe = RegExp(r'"averageRating"\s*:\s*([0-9]+(?:\.[0-9]+)?)');
  static final _ratingValueRe =
      RegExp(r'"ratingValue"\s*:\s*"?([0-9]+(?:\.[0-9]+)?)"?');
  static final _countRe = RegExp(r'"ratingsCount"\s*:\s*"?([0-9]+)"?');
  static final _showUrlRe =
      RegExp(r'https://www\.goodreads\.com/book/show/[0-9]+[^"\s<]*');

  Future<GoodreadsMeta?> fetchByIsbn(String isbn) async {
    final digits = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (digits.length < 10) return null;

    try {
      final resp = await _dio.get<String>(
        'https://www.goodreads.com/book/isbn/$digits',
      );
      final html = resp.data;
      if (html == null || html.isEmpty) return null;
      if (html.contains('Just a moment') ||
          html.toLowerCase().contains('captcha')) {
        debugPrint('GoodreadsScraper: blocked/captcha');
        return null;
      }

      final avgMatch = _avgRe.firstMatch(html) ?? _ratingValueRe.firstMatch(html);
      if (avgMatch == null) return null;
      final average = double.tryParse(avgMatch.group(1)!);
      if (average == null || average <= 0 || average > 5) return null;

      final countMatch = _countRe.firstMatch(html);
      final count = countMatch != null ? int.tryParse(countMatch.group(1)!) : null;

      String? bookUrl = resp.realUri.toString();
      if (!bookUrl.contains('/book/show/')) {
        bookUrl = _showUrlRe.firstMatch(html)?.group(0) ??
            'https://www.goodreads.com/book/isbn/$digits';
      } else {
        // Strip query noise.
        bookUrl = bookUrl.split('?').first;
      }

      return GoodreadsMeta(
        averageRating: average,
        ratingsCount: count,
        bookUrl: bookUrl,
        author: _guessAuthor(html),
      );
    } catch (e) {
      debugPrint('GoodreadsScraper: $e');
      return null;
    }
  }

  String? _guessAuthor(String html) {
    // Best-effort; may be absent depending on page variant.
    final patterns = [
      RegExp(r'"__typename"\s*:\s*"Contributor"\s*,\s*"name"\s*:\s*"([^"]+)"'),
      RegExp(r'property="books:author"\s+content="([^"]+)"'),
      RegExp(r'"author"\s*:\s*\{\s*"id"\s*:\s*"[^"]+"\s*,\s*"name"\s*:\s*"([^"]+)"'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      final name = m?.group(1)?.trim();
      if (name != null && name.length >= 2 && name.length < 80) return name;
    }
    return null;
  }
}
