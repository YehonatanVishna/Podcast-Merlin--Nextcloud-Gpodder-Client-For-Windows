import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';

final RegExp timestampRegex = RegExp(r'(?:(\d{1,2}):)?([0-5]?\d):([0-5]\d)');

/// Converts a timestamp string (e.g. "05:30", "1:15:30", "02:00:00") into a [Duration].
Duration parseTimestampToDuration(String timestamp) {
  final clean = timestamp.trim();
  final match = timestampRegex.firstMatch(clean);
  if (match != null) {
    final hours = match.group(1) != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
    final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
    return Duration(hours: hours, minutes: minutes, seconds: seconds);
  }

  final parts = clean.split(':').map((p) => int.tryParse(p) ?? 0).toList();
  if (parts.length == 2) {
    return Duration(minutes: parts[0], seconds: parts[1]);
  } else if (parts.length == 3) {
    return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
  }
  return Duration.zero;
}

/// Extracts all timestamp strings found in the given text.
List<String> extractTimestamps(String text) {
  return timestampRegex.allMatches(text).map((m) => m.group(0)!).toList();
}

/// Strips basic HTML tags from descriptions for plain text rendering.
String stripHtmlTags(String htmlText) {
  return htmlText
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}

class TimestampedDescription extends ConsumerWidget {
  final String text;
  final Episode? episode;
  final TextStyle? textStyle;
  final ValueChanged<Duration>? onSeek;

  const TimestampedDescription({
    super.key,
    required this.text,
    this.episode,
    this.textStyle,
    this.onSeek,
  });

  Future<void> _handleTimestampTap(
    BuildContext context,
    WidgetRef ref,
    String timestamp,
  ) async {
    final duration = parseTimestampToDuration(timestamp);
    if (onSeek != null) {
      onSeek!(duration);
    } else {
      final audioHandler = ref.read(audioHandlerProvider);
      if (episode != null && audioHandler.currentEpisode?.mediaUrl != episode!.mediaUrl) {
        await audioHandler.playEpisode(episode!);
      }
      await audioHandler.seek(duration);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Seeking to $timestamp'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cleanText = stripHtmlTags(text);
    final matches = timestampRegex.allMatches(cleanText).toList();

    if (matches.isEmpty) {
      return SelectableText(
        cleanText,
        style: textStyle ?? Theme.of(context).textTheme.bodyMedium,
      );
    }

    // Extract unique timestamps for top quick chips
    final uniqueTimestamps = <String>[];
    for (final m in matches) {
      final t = m.group(0)!;
      if (!uniqueTimestamps.contains(t)) {
        uniqueTimestamps.add(t);
      }
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;
    final primaryColor = Theme.of(context).colorScheme.primary;

    for (final match in matches) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: cleanText.substring(lastEnd, match.start),
          style: textStyle ?? Theme.of(context).textTheme.bodyMedium,
        ));
      }

      final timestampStr = match.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.0),
          child: InkWell(
            onTap: () => _handleTimestampTap(context, ref, timestampStr),
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: primaryColor.withValues(alpha: 0.4), width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline, size: 13, color: primaryColor),
                  const SizedBox(width: 3),
                  Text(
                    timestampStr,
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ));

      lastEnd = match.end;
    }

    if (lastEnd < cleanText.length) {
      spans.add(TextSpan(
        text: cleanText.substring(lastEnd),
        style: textStyle ?? Theme.of(context).textTheme.bodyMedium,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (uniqueTimestamps.isNotEmpty) ...[
          const Text(
            'Timestamps',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: uniqueTimestamps.map((ts) {
                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.play_arrow, size: 14),
                    label: Text(ts, style: const TextStyle(fontSize: 12)),
                    onPressed: () => _handleTimestampTap(context, ref, ts),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text.rich(
          TextSpan(children: spans),
        ),
      ],
    );
  }
}
