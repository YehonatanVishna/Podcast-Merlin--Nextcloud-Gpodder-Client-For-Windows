import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/services/image_cache_service.dart';

/// Offline-first persistent cached network image widget.
class AppCachedImage extends StatefulWidget {
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
  State<AppCachedImage> createState() => _AppCachedImageState();
}

class _AppCachedImageState extends State<AppCachedImage> {
  File? _localFile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant AppCachedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final cleanUrl = widget.imageUrl.trim();
    if (cleanUrl.isEmpty || (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      if (mounted) {
        setState(() {
          _localFile = null;
          _isLoading = false;
        });
      }
      return;
    }

    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _localFile = null;
          _isLoading = false;
        });
      }
      return;
    }

    // 1. Check local persistent disk storage FIRST (Instant 0ms lookup)
    final existingFile = await ImageCacheService.getCachedFile(cleanUrl);
    if (existingFile != null && mounted) {
      setState(() {
        _localFile = existingFile;
        _isLoading = false;
      });
      return;
    }

    // 2. If not in disk cache, attempt background download with short 4s timeout
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    final downloadedFile = await ImageCacheService.downloadAndCache(cleanUrl);
    if (mounted) {
      setState(() {
        _localFile = downloadedFile;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = widget.errorWidget ??
        Container(
          width: widget.width,
          height: widget.height,
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Icon(
            Icons.podcasts,
            size: (widget.width != null && widget.width! < 60) ? 24 : 40,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        );

    final cleanUrl = widget.imageUrl.trim();
    if (cleanUrl.isEmpty || (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      return widget.borderRadius != null
          ? ClipRRect(borderRadius: widget.borderRadius!, child: fallback)
          : fallback;
    }

    Widget content;
    if (kIsWeb) {
      content = Image.network(
        cleanUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return widget.placeholder ??
              Container(
                width: widget.width,
                height: widget.height,
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.0),
                  ),
                ),
              );
        },
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else if (_localFile != null) {
      content = Image.file(
        _localFile!,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    } else if (_isLoading) {
      content = widget.placeholder ??
          Container(
            width: widget.width,
            height: widget.height,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.0),
              ),
            ),
          );
    } else {
      content = Image.network(
        cleanUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return content;
  }
}
