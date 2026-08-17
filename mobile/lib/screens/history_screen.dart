import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/history_rating_enricher.dart';
import '../services/preferences_service.dart';
import '../utils/biblioteka_link.dart';
import '../widgets/book_cover.dart';
import '../widgets/rating_stars.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ScanHistoryEntry> _entries = [];
  bool _loading = true;
  bool _enriching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await PreferencesService.create();
    if (!mounted) return;
    setState(() {
      _entries = prefs.getHistory();
      _loading = false;
    });
    _enrichRatings();
  }

  Future<void> _enrichRatings() async {
    final needs = _entries.any(
      (e) =>
          e.isbn13 != null &&
          (e.ratingSource != 'goodreads' || e.ratingAverage == null),
    );
    if (!needs) return;

    setState(() => _enriching = true);
    await HistoryRatingEnricher().enrichStored(
      onProgress: (list) {
        if (!mounted) return;
        setState(() => _entries = list);
      },
    );
    if (!mounted) return;
    setState(() => _enriching = false);
  }

  Future<void> _clearAll() async {
    final prefs = await PreferencesService.create();
    await prefs.clearHistory();
    await _load();
  }

  Future<void> _removeAt(int index) async {
    final prefs = await PreferencesService.create();
    await prefs.removeHistoryEntryAt(index);
    await _load();
  }

  Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String _formatWhen(int timestampMs) {
    final when = DateTime.fromMillisecondsSinceEpoch(timestampMs).toLocal();
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    final hh = when.hour.toString().padLeft(2, '0');
    final mm = when.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          if (_enriching)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearAll,
              tooltip: 'Vaciar historial',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('Aún no hay libros escaneados'))
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    return Dismissible(
                      key: ValueKey(
                        '${e.timestampMs}_${e.isbn13}_${e.goodreadsUrl}_$index',
                      ),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Theme.of(context).colorScheme.error,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _removeAt(index),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: BookCover(
                          isbn13: e.isbn13,
                          width: 48,
                          height: 72,
                          size: CoverSize.medium,
                        ),
                        title: Text(
                          e.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              [
                                e.author,
                                if (e.isbn13 != null) e.isbn13!,
                                _formatWhen(e.timestampMs),
                              ].join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            RatingStars(
                              average: e.ratingAverage,
                              count: e.ratingsCount,
                              source: e.ratingSource,
                              compact: true,
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (bibliotekaConfigured) ...[
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.library_add_outlined),
                                tooltip: 'Añadir a Biblioteka',
                                onPressed: () => openInBiblioteka(
                                  title: e.title,
                                  author: e.author,
                                  isbn13: e.isbn13,
                                ),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.person_add_alt_1_outlined),
                                tooltip: 'Recomendar a',
                                onPressed: () => openRecommendInBiblioteka(
                                  title: e.title,
                                  author: e.author,
                                  isbn13: e.isbn13,
                                ),
                              ),
                            ],
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Eliminar',
                              onPressed: () => _removeAt(index),
                            ),
                          ],
                        ),
                        onTap: () => _open(e.goodreadsUrl),
                      ),
                    );
                  },
                ),
    );
  }
}
