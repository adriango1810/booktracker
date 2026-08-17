import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';

String? bibliotekaBaseUrl() {
  if (!dotenv.isInitialized) return null;
  final base = dotenv.env['BIBLIOTEKA_BASE_URL']?.trim() ?? '';
  return base.isEmpty ? null : base;
}

bool get bibliotekaConfigured => bibliotekaBaseUrl() != null;

Uri? _bibliotekaUri({
  required String path,
  required String title,
  String? author,
  String? isbn13,
}) {
  final base = bibliotekaBaseUrl();
  final trimmedTitle = title.trim();
  if (base == null || trimmedTitle.isEmpty) return null;

  final parsed = Uri.tryParse(base);
  if (parsed == null || !parsed.hasScheme) return null;

  final params = <String, String>{
    'title': trimmedTitle,
    'source': 'scanner',
  };
  final trimmedAuthor = author?.trim();
  if (trimmedAuthor != null && trimmedAuthor.isNotEmpty) {
    params['author'] = trimmedAuthor;
  }
  final isbn = isbn13?.replaceAll(RegExp(r'[^0-9Xx]'), '');
  if (isbn != null && isbn.isNotEmpty) {
    params['isbn'] = isbn;
  }

  return parsed.replace(path: path, queryParameters: params);
}

/// Deep link to Biblioteka's new-book form (active profile).
Uri? bibliotekaNewBookUri({
  required String title,
  String? author,
  String? isbn13,
}) =>
    _bibliotekaUri(
      path: '/biblioteca/nuevo',
      title: title,
      author: author,
      isbn13: isbn13,
    );

/// Deep link to pick another profile and save the book there.
Uri? bibliotekaRecommendUri({
  required String title,
  String? author,
  String? isbn13,
}) =>
    _bibliotekaUri(
      path: '/recomendar',
      title: title,
      author: author,
      isbn13: isbn13,
    );

Future<bool> _launch(Uri? uri) async {
  if (uri == null) return false;
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<bool> openInBiblioteka({
  required String title,
  String? author,
  String? isbn13,
}) =>
    _launch(
      bibliotekaNewBookUri(title: title, author: author, isbn13: isbn13),
    );

Future<bool> openRecommendInBiblioteka({
  required String title,
  String? author,
  String? isbn13,
}) =>
    _launch(
      bibliotekaRecommendUri(title: title, author: author, isbn13: isbn13),
    );
