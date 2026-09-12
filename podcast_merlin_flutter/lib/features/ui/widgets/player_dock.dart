import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/episode.dart';
import '../../../core/providers/app_providers.dart';
import 'cached_image.dart';
import 'now_playing_sheet.dart';
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
            final progressVal = (clampedSec / maxSeconds).clamp(0.0, 1.0);

            return LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 600;

                if (isCompact) {
                  return _buildCompactMiniPlayer(
                    context,
                    audioHandler: audioHandler,
                    title: title,
                    imageUrl: imageUrl,
                    position: position,
                    totalDuration: totalDuration,
                    progress: progressVal,
                    isPlaying: isPlaying,
                  );
                }

                return _buildDesktopPlayerDock(
                  context,
                  audioHandler: audioHandler,
                  title: title,
                  imageUrl: imageUrl,
                  position: position,
                  totalDuration: totalDuration,
                  maxSeconds: maxSeconds,
                  clampedSec: clampedSec,
                  isPlaying: isPlaying,
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCompactMiniPlayer(
    BuildContext context, {
    required dynamic audioHandler,
    required String title,
    required String imageUrl,
    required Duration position,
    required Duration totalDuration,
    required double progress,
    required bool isPlaying,
  }) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      child: InkWell(
        onTap: () => NowPlayingSheet.show(context),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Slim progress bar at the very top of mini player
              LinearProgressIndicator(
                value: progress,
                minHeight: 2.5,
                backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    // Thumbnail Artwork
                    AppCachedImage(
                      imageUrl: imageUrl,
                      width: 44,
                      height: 44,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    const SizedBox(width: 10),
                    // Title & Time info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_formatDuration(position)} / ${_formatDuration(totalDuration)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Play / Pause Button
                    IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: Icon(
                        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        size: 36,
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
                    // Fast Forward Button
                    StreamBuilder<({int rewind, int fastForward})>(
                      stream: audioHandler.seekDurationsStream,
                      initialData: (
                        rewind: audioHandler.rewindDuration,
                        fastForward: audioHandler.fastForwardDuration,
                      ),
                      builder: (context, seekSnapshot) {
                        final forwardSec =
                            seekSnapshot.data?.fastForward ?? audioHandler.fastForwardDuration;
                        return IconButton(
                          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                          icon: _buildForwardIcon(forwardSec),
                          tooltip: 'Forward ${forwardSec}s',
                          onPressed: () => audioHandler.fastForward(),
                        );
                      },
                    ),
                    // Expand Icon Button
                    IconButton(
                      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      icon: const Icon(Icons.keyboard_arrow_up, size: 24),
                      tooltip: 'Open Player',
                      onPressed: () => NowPlayingSheet.show(context),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopPlayerDock(
    BuildContext context, {
    required dynamic audioHandler,
    required String title,
    required String imageUrl,
    required Duration position,
    required Duration totalDuration,
    required int maxSeconds,
    required double clampedSec,
    required bool isPlaying,
  }) {
    final theme = Theme.of(context);

    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.2),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.brightness == Brightness.dark ? Colors.black54 : Colors.black12,
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
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDuration(position)} / ${_formatDuration(totalDuration)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
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
              // Fast Forward with configured duration
              StreamBuilder<({int rewind, int fastForward})>(
                stream: audioHandler.seekDurationsStream,
                initialData: (
                  rewind: audioHandler.rewindDuration,
                  fastForward: audioHandler.fastForwardDuration,
                ),
                builder: (context, seekSnapshot) {
                  final forwardSec =
                      seekSnapshot.data?.fastForward ?? audioHandler.fastForwardDuration;
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
                      backgroundColor: theme.colorScheme.primary,
                      child: Icon(Icons.bedtime, color: theme.colorScheme.primary),
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
                      backgroundColor: theme.colorScheme.primary,
                      child: Icon(Icons.queue_music, color: theme.colorScheme.primary),
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
