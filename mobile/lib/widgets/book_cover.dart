import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/biblioteka_theme.dart';

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
    // No `default=false`: a missing cover returns OL's tiny placeholder
    // immediately instead of a slow 404.
    return 'https://covers.openlibrary.org/b/isbn/$digits-$suffix.jpg';
  }

  /// Warm the disk cache so home/history don't wait on Open Library.
  static void prefetch(String? isbn) {
    for (final size in const [CoverSize.medium, CoverSize.large]) {
      final url = forIsbn(isbn, size: size);
      if (url == null) continue;
      CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
    }
  }
}

class BookCover extends StatelessWidget {
  const BookCover({
    super.key,
    this.isbn13,
    this.width = 56,
    this.height = 84,
    this.borderRadius = 8,
    this.size = CoverSize.large,
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

    final dpr = MediaQuery.devicePixelRatioOf(context);
    // Decode at device pixels; width-only so aspect isn't squashed.
    final memW = (width * dpr).round();

    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: memW,
        maxWidthDiskCache: 900,
        fadeInDuration: const Duration(milliseconds: 180),
        fadeOutDuration: const Duration(milliseconds: 80),
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
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
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [BkColors.leaf, BkColors.clay],
        ),
        borderRadius: borderRadius,
      ),
      child: Icon(
        Icons.menu_book_rounded,
        color: BkColors.cream.withValues(alpha: 0.75),
        size: width * 0.42,
      ),
    );
  }
}
