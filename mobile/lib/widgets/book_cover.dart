import 'package:flutter/material.dart';

/// Open Library cover by ISBN (`covers.openlibrary.org`).
enum CoverSize { small, medium, large }

class BookCoverUrls {
  BookCoverUrls._();

  static String? forIsbn(String? isbn, {CoverSize size = CoverSize.medium}) {
    if (isbn == null) return null;
    final digits = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (digits.length < 10) return null;
    final suffix = switch (size) {
      CoverSize.small => 'S',
      CoverSize.medium => 'M',
      CoverSize.large => 'L',
    };
    return 'https://covers.openlibrary.org/b/isbn/$digits-$suffix.jpg?default=false';
  }
}

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    this.isbn13,
    this.width = 56,
    this.height = 84,
    this.borderRadius = 8,
    this.size = CoverSize.medium,
  });

  final String? isbn13;
  final double width;
  final double height;
  final double borderRadius;
  final CoverSize size;

  @override
  Widget build(BuildContext context) {
    final url = BookCoverUrls.forIsbn(isbn13, size: size);
    final radius = BorderRadius.circular(borderRadius);
    final placeholder = _CoverPlaceholder(
      width: width,
      height: height,
      borderRadius: radius,
    );

    if (url == null) return placeholder;

    return ClipRRect(
      borderRadius: radius,
      child: Image.network(
        url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => placeholder,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: width,
            height: height,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({
    required this.width,
    required this.height,
    required this.borderRadius,
  });

  final double width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: borderRadius,
      ),
      child: Icon(
        Icons.menu_book_rounded,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.55),
        size: width * 0.42,
      ),
    );
  }
}
