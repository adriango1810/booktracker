import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/preferences_service.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<ScanHistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await PreferencesService.create();
    setState(() {
      _entries = prefs.getHistory();
      _loading = false;
    });
  }

  Future<void> _clear() async {
    final prefs = await PreferencesService.create();
    await prefs.clearHistory();
    await _load();
  }

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial'),
        actions: [
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clear,
              tooltip: 'Vaciar historial',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('Aún no hay libros escaneados'))
              : ListView.separated(
                  itemCount: _entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    final when = DateTime.fromMillisecondsSinceEpoch(e.timestampMs);
                    return ListTile(
                      title: Text(e.title),
                      subtitle: Text(
                        [
                          e.author,
                          if (e.isbn13 != null) e.isbn13!,
                          when.toLocal().toString().split('.').first,
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () => _open(e.goodreadsUrl),
                    );
                  },
                ),
    );
  }
}
