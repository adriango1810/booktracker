import '../models/book.dart';
import '../utils/isbn_validation.dart';
import 'book_api.dart';

/// Local mock per README section 7 (Pasos 4–5 without backend).
///
/// Real ISBNs open a Goodreads **search** for that ISBN (not a fake book id),
/// so the browser lands on the correct edition when possible.
class MockApiClient implements BookApi {
  static const mockIsbn = '9780000000000';

  @override
  Future<IdentifyBookResponse> identifyBook({
    String? isbn,
    String? ocrText,
    required String locale,
    required String device,
  }) async {
    await Future.delayed(const Duration(milliseconds: 300));

    if (isbn != null && isbn.isNotEmpty) {
      final normalized = ISBNValidator.normalizeISBN(isbn);
      if (normalized == mockIsbn) {
        return IdentifyBookResponse(
          status: 'ok',
          confidence: 0.95,
          book: const Book(
            title: 'Libro de prueba (mock)',
            author: 'Autor de prueba',
            isbn13: mockIsbn,
          ),
          reason: 'isbn_exact_match',
        );
      }
      if (ISBNValidator.isValidISBN13(normalized)) {
        return IdentifyBookResponse(
          status: 'ok',
          confidence: 0.92,
          book: Book(
            title: 'ISBN $normalized',
            author: 'Buscar en Goodreads',
            isbn13: normalized,
          ),
          reason: 'isbn_exact_match',
        );
      }
    }

    if (ocrText != null &&
        ocrText.toLowerCase().contains('nombre del viento')) {
      return IdentifyBookResponse(
        status: 'ok',
        confidence: 0.75,
        candidates: [
          BookCandidate(
            title: 'El nombre del viento',
            author: 'Patrick Rothfuss',
            isbn13: '9788401020236',
          ),
          BookCandidate(
            title: 'El temor de un hombre sabio',
            author: 'Patrick Rothfuss',
            isbn13: '9788401337433',
          ),
        ],
        reason: 'ocr_fuzzy_match',
      );
    }

    if (ocrText != null && ocrText.length >= 8) {
      return IdentifyBookResponse(
        status: 'ok',
        confidence: 0.70,
        book: Book(
          title: ocrText,
          author: 'Autor desconocido',
        ),
        reason: 'ocr_weak_match',
      );
    }

    return IdentifyBookResponse(
      status: 'error',
      confidence: 0.0,
      reason: 'no_match',
    );
  }

  @override
  Future<ResolveGoodreadsResponse> resolveGoodreads({
    required String title,
    required String author,
    String? isbn13,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));

    if (title.toLowerCase().contains('nombre del viento') ||
        isbn13 == '9788401020236') {
      return ResolveGoodreadsResponse(
        status: 'ok',
        confidence: 0.9,
        goodreadsUrl: 'https://www.goodreads.com/book/show/186074',
      );
    }

    if (isbn13 == mockIsbn) {
      return ResolveGoodreadsResponse(
        status: 'ok',
        confidence: 0.9,
        goodreadsUrl: 'https://www.goodreads.com/search?q=$mockIsbn',
      );
    }

    // Prefer ISBN search — finds the right edition for real barcodes.
    if (isbn13 != null && isbn13.isNotEmpty) {
      return ResolveGoodreadsResponse(
        status: 'ok',
        confidence: 0.9,
        goodreadsUrl:
            'https://www.goodreads.com/search?q=${Uri.encodeComponent(isbn13)}',
      );
    }

    final query = Uri.encodeComponent('$title $author'.trim());
    return ResolveGoodreadsResponse(
      status: 'ok',
      confidence: 0.85,
      goodreadsUrl: 'https://www.goodreads.com/search?q=$query',
    );
  }
}
