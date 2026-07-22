import 'package:flutter/material.dart';

class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    this.average,
    this.count,
    this.compact = false,
    this.onDark = false,
    this.source,
  });

  final double? average;
  final int? count;
  final bool compact;
  final bool onDark;
  final String? source;

  String get _sourceLabel {
    switch (source) {
      case 'goodreads':
        return 'Goodreads';
      case 'openlibrary':
        return 'Open Library';
      case 'google':
        return 'Google Books';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final avg = average;
    final muted = onDark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;
    final strong = onDark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;

    if (avg == null || avg <= 0) {
      return Text(
        compact ? 'Sin nota' : 'Sin valoración',
        style: TextStyle(color: muted, fontSize: compact ? 12 : 13),
      );
    }

    final color = onDark ? Colors.amberAccent : Colors.amber.shade700;
    final label = avg.toStringAsFixed(2);
    final countLabel =
        count != null && count! > 0 ? ' (${_formatCount(count!)})' : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: compact ? 16 : 18, color: color),
        const SizedBox(width: 4),
        Text(
          '$label$countLabel',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: compact ? 12 : 14,
            color: strong,
          ),
        ),
        if (_sourceLabel.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            _sourceLabel,
            style: TextStyle(fontSize: 11, color: muted),
          ),
        ],
      ],
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}
