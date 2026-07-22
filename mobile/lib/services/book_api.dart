import '../models/book.dart';

abstract class BookApi {
  Future<IdentifyBookResponse> identifyBook({
    String? isbn,
    String? ocrText,
    required String locale,
    required String device,
  });

  Future<ResolveGoodreadsResponse> resolveGoodreads({
    required String title,
    required String author,
    String? isbn13,
  });
}
