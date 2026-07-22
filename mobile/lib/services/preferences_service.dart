import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ScanHistoryEntry {
  final String title;
  final String author;
  final String? isbn13;
  final String goodreadsUrl;
  final int timestampMs;
  final double? ratingAverage;
  final int? ratingsCount;
  final String? ratingSource;

  const ScanHistoryEntry({
    required this.title,
    required this.author,
    this.isbn13,
    required this.goodreadsUrl,
    required this.timestampMs,
    this.ratingAverage,
    this.ratingsCount,
    this.ratingSource,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'author': author,
        'isbn13': isbn13,
        'goodreadsUrl': goodreadsUrl,
        'timestampMs': timestampMs,
        'ratingAverage': ratingAverage,
        'ratingsCount': ratingsCount,
        'ratingSource': ratingSource,
      };

  factory ScanHistoryEntry.fromJson(Map<String, dynamic> json) {
    return ScanHistoryEntry(
      title: json['title'] as String? ?? '',
      author: json['author'] as String? ?? '',
      isbn13: json['isbn13'] as String?,
      goodreadsUrl: json['goodreadsUrl'] as String? ?? '',
      timestampMs: json['timestampMs'] as int? ?? 0,
      ratingAverage: (json['ratingAverage'] as num?)?.toDouble(),
      ratingsCount: json['ratingsCount'] as int?,
      ratingSource: json['ratingSource'] as String?,
    );
  }

  ScanHistoryEntry copyWith({
    String? title,
    String? author,
    String? isbn13,
    String? goodreadsUrl,
    int? timestampMs,
    double? ratingAverage,
    int? ratingsCount,
    String? ratingSource,
  }) {
    return ScanHistoryEntry(
      title: title ?? this.title,
      author: author ?? this.author,
      isbn13: isbn13 ?? this.isbn13,
      goodreadsUrl: goodreadsUrl ?? this.goodreadsUrl,
      timestampMs: timestampMs ?? this.timestampMs,
      ratingAverage: ratingAverage ?? this.ratingAverage,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      ratingSource: ratingSource ?? this.ratingSource,
    );
  }
}

class PreferencesService {
  static const _autoOpenKey = 'auto_open_goodreads';
  static const _autoOpenPromptedKey = 'auto_open_prompted';
  static const _historyKey = 'scan_history_v1';
  static const _maxHistory = 10;

  final SharedPreferences _prefs;

  PreferencesService(this._prefs);

  static Future<PreferencesService> create() async {
    return PreferencesService(await SharedPreferences.getInstance());
  }

  bool getAutoOpenGoodreads({required bool defaultValue}) {
    return _prefs.getBool(_autoOpenKey) ?? defaultValue;
  }

  Future<void> setAutoOpenGoodreads(bool value) async {
    await _prefs.setBool(_autoOpenKey, value);
  }

  bool get hasPromptedAutoOpen => _prefs.getBool(_autoOpenPromptedKey) ?? false;

  Future<void> setAutoOpenPrompted() async {
    await _prefs.setBool(_autoOpenPromptedKey, true);
  }

  List<ScanHistoryEntry> getHistory() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ScanHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  ScanHistoryEntry? get lastEntry {
    final history = getHistory();
    return history.isEmpty ? null : history.first;
  }

  Future<void> addHistoryEntry(ScanHistoryEntry entry) async {
    final history = getHistory();
    history.insert(0, entry);
    final trimmed = history.take(_maxHistory).toList();
    await _prefs.setString(
      _historyKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> removeHistoryEntryAt(int index) async {
    final history = getHistory();
    if (index < 0 || index >= history.length) return;
    history.removeAt(index);
    if (history.isEmpty) {
      await _prefs.remove(_historyKey);
      return;
    }
    await _prefs.setString(
      _historyKey,
      jsonEncode(history.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> replaceHistory(List<ScanHistoryEntry> entries) async {
    final trimmed = entries.take(_maxHistory).toList();
    if (trimmed.isEmpty) {
      await _prefs.remove(_historyKey);
      return;
    }
    await _prefs.setString(
      _historyKey,
      jsonEncode(trimmed.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> clearHistory() async {
    await _prefs.remove(_historyKey);
  }
}
