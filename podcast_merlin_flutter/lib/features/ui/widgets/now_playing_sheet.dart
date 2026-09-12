import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';
import 'cached_image.dart';
import 'playback_speed_sheet.dart';
import 'queue_bottom_sheet.dart';
import 'sleep_timer_bottom_sheet.dart';

class NowPlayingSheet extends ConsumerWidget {
  const NowPlayingSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const NowPlayingSheet(),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  Widget _buildRewindIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.replay_5, size: 28);
    if (seconds == 10) return const Icon(Icons.replay_10, size: 28);
    if (seconds == 30) return const Icon(Icons.replay_30, size: 28);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.replay, size: 28),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildForwardIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.forward_5, size: 28);
    if (seconds == 10) return const Icon(Icons.forward_10, size: 28);
    if (seconds == 30) return const Icon(Icons.forward_30, size: 28);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.forward, size: 28),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final audioHandler = ref.watch(audioHandlerProvider);

    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final item = mediaSnapshot.data;
        final episode = audioHandler.currentEpisode;

        if (item == null && episode == null) {
          return const SizedBox.shrink();
        }

        final title = item?.title ?? episode?.title ?? 'Playing Podcast';
        final podcastTitle = item?.album ?? episode?.podcastRss ?? '';
        final imageUrl = (episode?.imageUrl.isNotEmpty == true)
            ? episode!.imageUrl
            : (item?.artUri?.toString() ?? '');
        final totalDuration = item?.duration ?? Duration(seconds: episode?.duration ?? 0);

        return StreamBuilder<PlaybackState>(
          stream: audioHandler.playbackState,
          builder: (context, playbackSnapshot) {
            final state = playbackSnapshot.data;
            final isPlaying = state?.playing ?? false;
            final position = state?.position ?? Duration.zero;

            final maxSeconds = totalDuration.inSeconds > 0 ? totalDuration.inSeconds : 1;
            final clampedSec = position.inSeconds.clamp(0, maxSeconds).toDouble();

            return LayoutBuilder(
              builder: (context, constraints) {
                final maxSheetHeight = constraints.maxHeight;
                final artSize = (maxSheetHeight * 0.35).clamp(160.0, 300.0);

                return SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Drag Handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(top: 4, bottom: 8),
                              decoration: BoxDecoration(
                                color: theme.dividerColor.withValues(alpha: 0.4),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          // Top bar with close button & title
                          Row(
                            children: [
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                icon: const Icon(Icons.keyboard_arrow_down, size: 28),
                                tooltip: 'Close Player',
                                onPressed: () => Navigator.pop(context),
                              ),
                              Expanded(
                                child: Text(
                                  podcastTitle.isNotEmpty ? podcastTitle : 'Now Playing',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48), // Balancing width of close button
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Big Cover Artwork
                          Center(
                            child: Container(
                              width: artSize,
                              height: artSize,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.brightness == Brightness.dark
                                        ? Colors.black54
                                        : Colors.black26,
                                    blurRadius: 16,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: AppCachedImage(
                                  imageUrl: imageUrl,
                                  width: artSize,
                                  height: artSize,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          // Title & Show metadata
                          Text(
                            title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          if (episode?.publishedAt != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              DateFormat.yMMMMd().format(episode!.publishedAt!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Scrubber Slider
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                            ),
                            child: Slider(
                              min: 0.0,
                              max: maxSeconds.toDouble(),
                              value: clampedSec,
                              onChanged: (val) {
                                audioHandler.seek(Duration(seconds: val.toInt()));
                              },
                            ),
                          ),
                          // Timestamps Row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _formatDuration(position),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                Text(
                                  _formatDuration(totalDuration),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Primary Playback Controls
                          StreamBuilder<({int rewind, int fastForward})>(
                            stream: audioHandler.seekDurationsStream,
                            initialData: (
                              rewind: audioHandler.rewindDuration,
                              fastForward: audioHandler.fastForwardDuration,
                            ),
                            builder: (context, seekSnapshot) {
                              final rewindSec = seekSnapshot.data?.rewind ?? audioHandler.rewindDuration;
                              final forwardSec = seekSnapshot.data?.fastForward ?? audioHandler.fastForwardDuration;

                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    iconSize: 36,
                                    icon: _buildRewindIcon(rewindSec),
                                    tooltip: 'Rewind ${rewindSec}s',
                                    onPressed: () => audioHandler.rewind(),
                                  ),
                                  const SizedBox(width: 24),
                                  IconButton(
                                    constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
                                    iconSize: 64,
                                    icon: Icon(
                                      isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                                      color: theme.colorScheme.primary,
                                    ),
                                    onPressed: () {
                                      if (isPlaying) {
                                        audioHandler.pause();
                                      } else {
                                        audioHandler.play();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 24),
                                  IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    iconSize: 36,
                                    icon: _buildForwardIcon(forwardSec),
                                    tooltip: 'Fast forward ${forwardSec}s',
                                    onPressed: () => audioHandler.fastForward(),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),
                          // Secondary Utility Row: Speed, Sleep Timer, Queue, Download
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // Speed button
                              IconButton(
                                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                icon: const Icon(Icons.speed),
                                tooltip: 'Playback Speed',
                                onPressed: () => PlaybackSpeedSheet.show(context),
                              ),
                              // Sleep Timer button
                              StreamBuilder<Duration?>(
                                stream: audioHandler.sleepTimerStream,
                                initialData: audioHandler.sleepTimerRemaining,
                                builder: (context, sleepSnapshot) {
                                  final isActive = audioHandler.isSleepTimerActive;
                                  final isEnd = audioHandler.isSleepTimerEndOfEpisode;
                                  final remaining = sleepSnapshot.data ?? audioHandler.sleepTimerRemaining;

                                  Widget iconWidget = const Icon(Icons.bedtime_outlined);
                                  if (isActive) {
                                    final label = isEnd
                                        ? 'End'
                                        : (remaining != null ? '${remaining.inMinutes}m' : 'On');
                                    iconWidget = Badge(
                                      label: Text(label, style: const TextStyle(fontSize: 9)),
                                      backgroundColor: theme.colorScheme.primary,
                                      child: Icon(Icons.bedtime, color: theme.colorScheme.primary),
                                    );
                                  }

                                  return IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    icon: iconWidget,
                                    tooltip: 'Sleep Timer',
                                    onPressed: () => SleepTimerBottomSheet.show(context),
                                  );
                                },
                              ),
                              // Queue button
                              StreamBuilder<List<Episode>>(
                                stream: audioHandler.queueStream,
                                initialData: audioHandler.currentQueue,
                                builder: (context, queueSnapshot) {
                                  final queue = queueSnapshot.data ?? audioHandler.currentQueue;
                                  Widget iconWidget = const Icon(Icons.queue_music);
                                  if (queue.isNotEmpty) {
                                    iconWidget = Badge(
                                      label: Text('${queue.length}', style: const TextStyle(fontSize: 9)),
                                      backgroundColor: theme.colorScheme.primary,
                                      child: Icon(Icons.queue_music, color: theme.colorScheme.primary),
                                    );
                                  }

                                  return IconButton(
                                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                    icon: iconWidget,
                                    tooltip: 'Up Next Queue',
                                    onPressed: () => QueueBottomSheet.show(context),
                                  );
                                },
                              ),
                              // Download Action button
                              if (episode != null)
                                Consumer(
                                  builder: (context, ref, _) {
                                    final downloadService = ref.watch(episodeDownloadServiceProvider);
                                    if (episode.isDownloaded) {
                                      return IconButton(
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        icon: Icon(
                                          Icons.download_done_rounded,
                                          color: theme.colorScheme.primary,
                                        ),
                                        tooltip: 'Downloaded',
                                        onPressed: () {},
                                      );
                                    } else if (episode.isDownloading) {
                                      return const IconButton(
                                        constraints: BoxConstraints(minWidth: 48, minHeight: 48),
                                        icon: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                        tooltip: 'Downloading...',
                                        onPressed: null,
                                      );
                                    } else {
                                      return IconButton(
                                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                        icon: const Icon(Icons.download_outlined),
                                        tooltip: 'Download Episode',
                                        onPressed: () {
                                          downloadService.startDownload(episode);
                                        },
                                      );
                                    }
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
