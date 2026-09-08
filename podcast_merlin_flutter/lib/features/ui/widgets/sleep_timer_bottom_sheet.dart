import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';

class SleepTimerBottomSheet extends ConsumerWidget {
  const SleepTimerBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const SleepTimerBottomSheet(),
    );
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioHandler = ref.watch(audioHandlerProvider);

    return StreamBuilder<Duration?>(
      stream: audioHandler.sleepTimerStream,
      initialData: audioHandler.sleepTimerRemaining,
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? audioHandler.sleepTimerRemaining;
        final isEndOfEpisode = audioHandler.isSleepTimerEndOfEpisode;
        final isActive = audioHandler.isSleepTimerActive;

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
              // Header
              Row(
                children: [
                  Icon(
                    Icons.bedtime,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Sleep Timer',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isEndOfEpisode
                            ? 'End of Episode'
                            : (remaining != null ? _formatRemaining(remaining) : 'Active'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              // Turn off timer if currently active
              if (isActive) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.timer_off_outlined, color: Colors.red),
                  label: const Text(
                    'Turn Off Timer',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () {
                    audioHandler.cancelSleepTimer();
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Sleep timer cancelled')),
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
              ],
              // Timer presets
              _buildOptionTile(
                context,
                title: '5 minutes',
                icon: Icons.timer_outlined,
                isSelected: !isEndOfEpisode && remaining != null && remaining.inMinutes == 5,
                onTap: () {
                  audioHandler.setSleepTimer(const Duration(minutes: 5));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep timer set for 5 minutes')),
                  );
                },
              ),
              _buildOptionTile(
                context,
                title: '15 minutes',
                icon: Icons.timer_outlined,
                isSelected: !isEndOfEpisode && remaining != null && remaining.inMinutes == 15,
                onTap: () {
                  audioHandler.setSleepTimer(const Duration(minutes: 15));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep timer set for 15 minutes')),
                  );
                },
              ),
              _buildOptionTile(
                context,
                title: '30 minutes',
                icon: Icons.timer_outlined,
                isSelected: !isEndOfEpisode && remaining != null && remaining.inMinutes == 30,
                onTap: () {
                  audioHandler.setSleepTimer(const Duration(minutes: 30));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep timer set for 30 minutes')),
                  );
                },
              ),
              _buildOptionTile(
                context,
                title: '45 minutes',
                icon: Icons.timer_outlined,
                isSelected: !isEndOfEpisode && remaining != null && remaining.inMinutes == 45,
                onTap: () {
                  audioHandler.setSleepTimer(const Duration(minutes: 45));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep timer set for 45 minutes')),
                  );
                },
              ),
              _buildOptionTile(
                context,
                title: '60 minutes',
                icon: Icons.timer_outlined,
                isSelected: !isEndOfEpisode && remaining != null && remaining.inMinutes == 60,
                onTap: () {
                  audioHandler.setSleepTimer(const Duration(minutes: 60));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep timer set for 60 minutes')),
                  );
                },
              ),
              _buildOptionTile(
                context,
                title: 'End of Current Episode',
                icon: Icons.skip_next_outlined,
                isSelected: isEndOfEpisode,
                onTap: () {
                  audioHandler.setSleepTimerEndOfEpisode();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sleep timer set for end of current episode')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOptionTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? theme.colorScheme.primary : null,
        ),
      ),
      trailing: isSelected
          ? Icon(Icons.check, color: theme.colorScheme.primary)
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onTap: onTap,
    );
  }
}
