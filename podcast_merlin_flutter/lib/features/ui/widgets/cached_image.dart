import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Reusable cached network image widget with local disk & memory caching.
class AppCachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;
  final BorderRadius? borderRadius;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final cleanUrl = imageUrl.trim();

    final fallback = errorWidget ??
        Container(
          width: width,
          height: height,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.podcasts,
            size: (width != null && width! < 60) ? 24 : 40,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        );

    if (cleanUrl.isEmpty || (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: fallback);
      }
      return fallback;
    }

    final loadingWidget = placeholder ??
        Container(
          width: width,
          height: height,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.0),
            ),
          ),
        );

    Widget imageWidget = CachedNetworkImage(
      imageUrl: cleanUrl,
      width: width,
      height: height,
      fit: fit,
      placeholder: (context, url) => loadingWidget,
      errorWidget: (context, url, error) => fallback,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: const Duration(milliseconds: 200),
    );

    if (borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }
}
