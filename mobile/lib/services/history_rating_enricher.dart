import 'goodreads_scraper.dart';
import 'preferences_service.dart';

/// Fills Goodreads ratings for saved history in the background (never during scan).
class HistoryRatingEnricher {
  HistoryRatingEnricher({GoodreadsScraper? scraper})
      : _scraper = scraper ?? GoodreadsScraper();

  final GoodreadsScraper _scraper;

  /// Updates SharedPreferences history in place; yields progress as each book fills.
  Future<List<ScanHistoryEntry>> enrichStored({
    void Function(List<ScanHistoryEntry> updated)? onProgress,
    int? limit,
  }) async {
    final prefs = await PreferencesService.create();
    var current = prefs.getHistory();
    if (current.isEmpty) return current;

    var changed = false;
    var fetched = 0;
    final maxFetch = limit;

    for (var i = 0; i < current.length; i++) {
      if (maxFetch != null && fetched >= maxFetch) break;

      final e = current[i];
      if (e.ratingSource == 'goodreads' && e.ratingAverage != null) continue;
      final isbn = e.isbn13;
      if (isbn == null || isbn.length < 10) continue;

      final meta = await _scraper.fetchByIsbn(isbn);
      if (meta == null) continue;

      current[i] = e.copyWith(
        ratingAverage: meta.averageRating,
        ratingsCount: meta.ratingsCount,
        ratingSource: 'goodreads',
        goodreadsUrl: meta.bookUrl ?? e.goodreadsUrl,
        author: (e.author == 'Autor desconocido' && meta.author != null)
            ? meta.author
            : e.author,
      );
      changed = true;
      fetched++;
      onProgress?.call(List.unmodifiable(current));
    }

    if (changed) {
      await prefs.replaceHistory(current);
    }
    return current;
  }
}
