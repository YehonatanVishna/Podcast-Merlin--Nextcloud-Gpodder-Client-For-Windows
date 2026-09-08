import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';

class PlaybackSpeedSheet extends ConsumerWidget {
  const PlaybackSpeedSheet({super.key});

  static const List<double> presets = [0.8, 1.0, 1.2, 1.5, 2.0, 2.5];

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PlaybackSpeedSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioHandler = ref.watch(audioHandlerProvider);

    return StreamBuilder<PlaybackState>(
      stream: audioHandler.playbackState,
      builder: (context, snapshot) {
        final currentSpeed = snapshot.data?.speed ?? audioHandler.speed;
        final clampedSpeed = currentSpeed.clamp(0.5, 3.0);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header with Speed badge
              Row(
                children: [
                  Icon(
                    Icons.speed,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Playback Speed',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${clampedSpeed.toStringAsFixed(1)}x',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Fine-grained Slider (0.5x to 3.0x with 0.1x steps)
              Row(
                children: [
                  const Text('0.5x', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                      ),
                      child: Slider(
                        value: clampedSpeed,
                        min: 0.5,
                        max: 3.0,
                        divisions: 25,
                        label: '${clampedSpeed.toStringAsFixed(1)}x',
                        onChanged: (val) {
                          final rounded = (val * 10).roundToDouble() / 10;
                          audioHandler.setSpeed(rounded);
                        },
                      ),
                    ),
                  ),
                  const Text('3.0x', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 16),
              // Quick Presets
              Text(
                'QUICK PRESETS',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: presets.map((preset) {
                  final isSelected = (clampedSpeed - preset).abs() < 0.05;
                  return ChoiceChip(
                    label: Text('${preset.toStringAsFixed(1)}x'),
                    selected: isSelected,
                    onSelected: (_) {
                      audioHandler.setSpeed(preset);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }
}
