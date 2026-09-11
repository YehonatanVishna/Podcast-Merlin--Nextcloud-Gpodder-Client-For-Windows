import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';
import 'cached_image.dart';
import 'playback_speed_sheet.dart';
import 'queue_bottom_sheet.dart';
import 'sleep_timer_bottom_sheet.dart';

class PlayerDock extends ConsumerWidget {
  const PlayerDock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

            return Container(
              height: 90,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black54
                        : Colors.black12,
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Slider Bar
                  SizedBox(
                    height: 18,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        trackHeight: 3,
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
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
                  ),
                  Row(
                    children: [
                      // Thumbnail Artwork
                      AppCachedImage(
                        imageUrl: imageUrl,
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(width: 12),
                      // Title & Podcast Name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_formatDuration(position)} / ${_formatDuration(totalDuration)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.color
                                        ?.withValues(alpha: 0.7),
                                  ),
                            ),
                          ],
                        ),
                      ),
                      // Controls
                      // Rewind with configured duration
                      StreamBuilder<({int rewind, int fastForward})>(
                        stream: audioHandler.seekDurationsStream,
                        initialData: (
                          rewind: audioHandler.rewindDuration,
                          fastForward: audioHandler.fastForwardDuration,
                        ),
                        builder: (context, seekSnapshot) {
                          final rewindSec = seekSnapshot.data?.rewind ?? audioHandler.rewindDuration;
                          return IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: _buildRewindIcon(rewindSec),
                            tooltip: 'Rewind ${rewindSec}s',
                            onPressed: () => audioHandler.rewind(),
                          );
                        },
                      ),
                      // Play / Pause
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                          size: 38,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () {
                          if (isPlaying) {
                            audioHandler.pause();
                          } else {
                            audioHandler.play();
                          }
                        },
                      ),
                      // Fast Forward with configured duration
                      StreamBuilder<({int rewind, int fastForward})>(
                        stream: audioHandler.seekDurationsStream,
                        initialData: (
                          rewind: audioHandler.rewindDuration,
                          fastForward: audioHandler.fastForwardDuration,
                        ),
                        builder: (context, seekSnapshot) {
                          final forwardSec = seekSnapshot.data?.fastForward ?? audioHandler.fastForwardDuration;
                          return IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: _buildForwardIcon(forwardSec),
                            tooltip: 'Fast forward ${forwardSec}s',
                            onPressed: () => audioHandler.fastForward(),
                          );
                        },
                      ),
                      // Speed selector
                      IconButton(
                        visualDensity: VisualDensity.compact,
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
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Icon(Icons.bedtime, color: Theme.of(context).colorScheme.primary),
                            );
                          }

                          return IconButton(
                            visualDensity: VisualDensity.compact,
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
                              backgroundColor: Theme.of(context).colorScheme.primary,
                              child: Icon(Icons.queue_music, color: Theme.of(context).colorScheme.primary),
                            );
                          }

                          return IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: iconWidget,
                            tooltip: 'Up Next Queue',
                            onPressed: () => QueueBottomSheet.show(context),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRewindIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.replay_5);
    if (seconds == 10) return const Icon(Icons.replay_10);
    if (seconds == 30) return const Icon(Icons.replay_30);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.replay),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildForwardIcon(int seconds) {
    if (seconds == 5) return const Icon(Icons.forward_5);
    if (seconds == 10) return const Icon(Icons.forward_10);
    if (seconds == 30) return const Icon(Icons.forward_30);
    return Stack(
      alignment: Alignment.center,
      children: [
        const Icon(Icons.forward),
        Positioned(
          bottom: 2,
          child: Text(
            '$seconds',
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold),
          ),
        ),
      ],
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
}
