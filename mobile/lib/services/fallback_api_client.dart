import '../models/book.dart';
import 'book_api.dart';

/// Tries [primary] first; on any failure falls back to [fallback] (usually mock).
class FallbackBookApi implements BookApi {
  FallbackBookApi({
    required this.primary,
    required this.fallback,
  });

  final BookApi primary;
  final BookApi fallback;

  @override
  Future<IdentifyBookResponse> identifyBook({
    String? isbn,
    String? ocrText,
    required String locale,
    required String device,
  }) async {
    try {
      return await primary.identifyBook(
        isbn: isbn,
        ocrText: ocrText,
        locale: locale,
        device: device,
      );
    } catch (_) {
      return fallback.identifyBook(
        isbn: isbn,
        ocrText: ocrText,
        locale: locale,
        device: device,
      );
    }
  }

  @override
  Future<ResolveGoodreadsResponse> resolveGoodreads({
    required String title,
    required String author,
    String? isbn13,
  }) async {
    try {
      return await primary.resolveGoodreads(
        title: title,
        author: author,
        isbn13: isbn13,
      );
    } catch (_) {
      return fallback.resolveGoodreads(
        title: title,
        author: author,
        isbn13: isbn13,
      );
    }
  }
}
