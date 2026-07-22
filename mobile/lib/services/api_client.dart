import 'package:dio/dio.dart';
import '../models/book.dart';
import 'book_api.dart';

class ApiClient implements BookApi {
  final Dio _dio;
  final String baseUrl;

  ApiClient({required this.baseUrl})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ));

  @override
  Future<IdentifyBookResponse> identifyBook({
    String? isbn,
    String? ocrText,
    required String locale,
    required String device,
  }) async {
    final data = <String, dynamic>{
      'locale': locale,
      'device': device,
    };

    if (isbn != null && isbn.isNotEmpty) {
      data['isbn'] = isbn;
    } else if (ocrText != null && ocrText.isNotEmpty) {
      data['ocr_text'] = ocrText;
    } else {
      throw ArgumentError('Either isbn or ocr_text must be provided');
    }

    try {
      final response = await _dio.post('/identify-book', data: data);
      return IdentifyBookResponse.fromJson(response.data);
    } on DioException {
      rethrow;
    }
  }

  @override
  Future<ResolveGoodreadsResponse> resolveGoodreads({
    required String title,
    required String author,
    String? isbn13,
  }) async {
    final data = <String, dynamic>{
      'title': title,
      'author': author,
      'isbn13': ?isbn13,
    };

    try {
      final response = await _dio.post('/resolve-goodreads', data: data);
      return ResolveGoodreadsResponse.fromJson(response.data);
    } on DioException {
      rethrow;
    }
  }
}
