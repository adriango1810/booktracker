import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/history_rating_enricher.dart';
import '../services/preferences_service.dart';
import '../theme/biblioteka_theme.dart';
import '../utils/biblioteka_link.dart';
import '../widgets/book_cover.dart';
import '../widgets/paper_scaffold.dart';
import '../widgets/rating_stars.dart';
import 'history_screen.dart';
import 'scan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ScanHistoryEntry? _last;
  bool _loading = true;
  bool _ratingLoading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final prefs = await PreferencesService.create();
    if (!mounted) return;
    setState(() {
      _last = prefs.lastEntry;
      _loading = false;
    });
    BookCoverUrls.prefetch(_last?.isbn13);
    _enrichRatings();
  }

  Future<void> _enrichRatings() async {
    final last = _last;
    if (last == null) return;
    if (last.ratingSource == 'goodreads' && last.ratingAverage != null) return;

    setState(() => _ratingLoading = true);
    await HistoryRatingEnricher().enrichStored(
      limit: 1,
      onProgress: (list) {
        if (!mounted) return;
        setState(() => _last = list.isNotEmpty ? list.first : _last);
      },
    );
    if (!mounted) return;
    final prefs = await PreferencesService.create();
    setState(() {
      _last = prefs.lastEntry;
      _ratingLoading = false;
    });
  }

  Future<void> _openScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanScreen()),
    );
    _refresh();
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
    _refresh();
  }

  Future<void> _openLast() async {
    final url = _last?.goodreadsUrl;
    if (url == null || url.isEmpty) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return PaperScaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Book Scanner',
                            style: text.headlineSmall,
                          ),
                        ),
                        Material(
                          color: BkColors.leafTint,
                          shape: const CircleBorder(),
                          child: IconButton(
                            onPressed: _openHistory,
                            icon: const Icon(Icons.history),
                            color: BkColors.leaf,
                            tooltip: 'Historial',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'ESCANEA · GUARDA · COMPARTE',
                      style: text.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Apunta al ISBN o al título y ábrelo en Goodreads o Biblioteka.',
                      style: text.bodyMedium?.copyWith(color: BkColors.inkSoft),
                    ),
                    const Spacer(flex: 2),
                    FilledButton(
                      onPressed: _openScan,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(64),
                        textStyle: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.qr_code_scanner, size: 28),
                          SizedBox(width: 12),
                          Text('Escanear'),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (_last != null) ...[
                      Text('ÚLTIMO ESCANEADO', style: text.titleSmall),
                      const SizedBox(height: 10),
                      SoftCard(
                        onTap: _openLast,
                        child: Row(
                          children: [
                            BookCover(
                              isbn13: _last!.isbn13,
                              width: 64,
                              height: 96,
                              size: CoverSize.large,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _last!.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleMedium?.copyWith(
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _last!.author,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: BkColors.inkSoft),
                                  ),
                                  const SizedBox(height: 6),
                                  if (_ratingLoading &&
                                      _last!.ratingAverage == null)
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    RatingStars(
                                      average: _last!.ratingAverage,
                                      count: _last!.ratingsCount,
                                      source: _last!.ratingSource,
                                      compact: true,
                                    ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Abrir en Goodreads',
                                    style: TextStyle(
                                      color: BkColors.leaf,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (bibliotekaConfigured) ...[
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () => openInBiblioteka(
                                        title: _last!.title,
                                        author: _last!.author,
                                        isbn13: _last!.isbn13,
                                      ),
                                      child: const Text(
                                        'Añadir a Biblioteka',
                                        style: TextStyle(
                                          color: BkColors.leaf,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    GestureDetector(
                                      onTap: () => openRecommendInBiblioteka(
                                        title: _last!.title,
                                        author: _last!.author,
                                        isbn13: _last!.isbn13,
                                      ),
                                      child: const Text(
                                        'Recomendar a',
                                        style: TextStyle(
                                          color: BkColors.leaf,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.open_in_new,
                              color: BkColors.inkSoft,
                            ),
                          ],
                        ),
                      ),
                    ] else
                      const Text(
                        'Aún no has escaneado ningún libro.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: BkColors.inkSoft),
                      ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _openHistory,
                      child: const Text('Ver historial'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
