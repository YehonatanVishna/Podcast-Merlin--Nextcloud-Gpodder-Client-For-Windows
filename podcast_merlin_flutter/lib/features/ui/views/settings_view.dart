import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../sync/opml_ui_helper.dart';
import '../../sync/secure_storage_service.dart';
import '../widgets/sync_error_banner.dart';
import '../../../main.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _serverController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = true;
  bool _isTesting = false;
  String? _statusMessage;
  bool _isSuccessStatus = false;
  int _rewindSeconds = 10;
  int _fastForwardSeconds = 30;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final storage = ref.read(secureStorageProvider);
    _serverController.text = await storage.read(SecureStorageService.keyServerUrl) ?? '';
    _userController.text = await storage.read(SecureStorageService.keyUsername) ?? '';
    _passwordController.text = await storage.read(SecureStorageService.keyPassword) ?? '';

    final rew = await storage.read(SecureStorageService.keyRewindDuration);
    final ff = await storage.read(SecureStorageService.keyFastForwardDuration);
    if (rew != null && int.tryParse(rew) != null) {
      _rewindSeconds = int.parse(rew);
    }
    if (ff != null && int.tryParse(ff) != null) {
      _fastForwardSeconds = int.parse(ff);
    }

    ref.invalidate(downloadStorageUsageBytesProvider);
    ref.invalidate(downloadedEpisodesCountProvider);

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final oldServer = await storage.read(SecureStorageService.keyServerUrl) ?? '';
    final oldUser = await storage.read(SecureStorageService.keyUsername) ?? '';
    final newServer = _serverController.text.trim();
    final newUser = _userController.text.trim();

    if (oldServer != newServer || oldUser != newUser) {
      // Credentials or server changed, reset sync timestamps so next sync does a clean full fetch
      await storage.delete(SecureStorageService.keyLastSubscriptionTimestamp);
      await storage.delete(SecureStorageService.keyLastActionTimestamp);
    }

    await storage.write(SecureStorageService.keyServerUrl, newServer);
    await storage.write(SecureStorageService.keyUsername, newUser);
    await storage.write(SecureStorageService.keyPassword, _passwordController.text.trim());

    await storage.write(SecureStorageService.keyRewindDuration, _rewindSeconds.toString());
    await storage.write(SecureStorageService.keyFastForwardDuration, _fastForwardSeconds.toString());
    ref.read(audioHandlerProvider).setSeekDurations(rewind: _rewindSeconds, fastForward: _fastForwardSeconds);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _statusMessage = null;
      _isSuccessStatus = false;
    });

    final apiClient = ref.read(apiClientProvider);
    final errorDetail = await apiClient.testConnectionDetailed(
      serverUrl: _serverController.text.trim(),
      username: _userController.text.trim(),
      password: _passwordController.text.trim(),
    );

    setState(() {
      _isTesting = false;
      _isSuccessStatus = errorDetail == null;
      _statusMessage = errorDetail == null
          ? 'Connected successfully to Nextcloud gPodder!'
          : 'Connection failed: $errorDetail';
    });
  }

  Future<void> _exportOpml() async {
    await OpmlUiHelper.exportOpml(context, ref);
  }

  void _showImportOpmlDialog() {
    OpmlUiHelper.importOpml(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final syncStatus = ref.watch(syncStatusNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SvgPicture.asset(
                          'assets/images/logo.svg',
                          width: 80,
                          height: 80,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Podcast Merlin',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Nextcloud gPodder Client • v2.0.0',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (syncStatus.error != null && !syncStatus.isSyncing) ...[
                  SyncErrorBanner(
                    errorMessage: syncStatus.error!,
                    onDismiss: () => ref.read(syncStatusNotifierProvider.notifier).clearError(),
                    onRetry: () => ref.read(podcastsNotifierProvider.notifier).refreshAll(),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text(
                  'Nextcloud gPodder Server Integration',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Synchronize your podcast subscriptions and playback positions across Windows, Android, macOS, and Linux.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _serverController,
                  decoration: const InputDecoration(
                    labelText: 'Nextcloud Server URL',
                    hintText: 'https://nextcloud.example.com',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.cloud),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _userController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'App Password or Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                ),
                const SizedBox(height: 24),
                if (_statusMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isSuccessStatus
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _isSuccessStatus ? Colors.green : Colors.red,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _isSuccessStatus ? Icons.check_circle_outline : Icons.error_outline,
                          color: _isSuccessStatus ? Colors.green[800] : Colors.red[800],
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _statusMessage!,
                            style: TextStyle(
                              color: _isSuccessStatus ? Colors.green[900] : Colors.red[900],
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Consumer(
                  builder: (context, ref, child) {
                    final syncState = ref.watch(syncStatusNotifierProvider);
                    final isSyncing = syncState.isSyncing;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (isSyncing) ...[
                          Row(
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  syncState.currentTask ?? 'Syncing with gPodder...',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        OutlinedButton.icon(
                          icon: isSyncing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.sync),
                          label: Text(isSyncing ? 'Syncing...' : 'Sync Now with gPodder'),
                          onPressed: isSyncing
                              ? null
                              : () async {
                                  await _saveCredentials();
                                  ref.read(podcastsNotifierProvider.notifier).refreshAll();
                                },
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Force Full Re-sync (Retrieve all played positions)'),
                          onPressed: isSyncing
                              ? null
                              : () async {
                                  await _saveCredentials();
                                  ref.read(podcastsNotifierProvider.notifier).refreshAll(forceFullResync: true);
                                },
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: _isTesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_done),
                        label: const Text('Test Connection'),
                        onPressed: _isTesting ? null : _testConnection,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Playback & Seek Controls',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Customize the rewind and fast-forward skip intervals used in the player dock.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _rewindSeconds,
                        decoration: const InputDecoration(
                          labelText: 'Rewind Interval',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.replay),
                        ),
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5 seconds')),
                          DropdownMenuItem(value: 10, child: Text('10 seconds')),
                          DropdownMenuItem(value: 15, child: Text('15 seconds')),
                          DropdownMenuItem(value: 30, child: Text('30 seconds')),
                          DropdownMenuItem(value: 45, child: Text('45 seconds')),
                          DropdownMenuItem(value: 60, child: Text('60 seconds')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _rewindSeconds = val);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _fastForwardSeconds,
                        decoration: const InputDecoration(
                          labelText: 'Fast Forward Interval',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.forward),
                        ),
                        items: const [
                          DropdownMenuItem(value: 5, child: Text('5 seconds')),
                          DropdownMenuItem(value: 10, child: Text('10 seconds')),
                          DropdownMenuItem(value: 15, child: Text('15 seconds')),
                          DropdownMenuItem(value: 30, child: Text('30 seconds')),
                          DropdownMenuItem(value: 45, child: Text('45 seconds')),
                          DropdownMenuItem(value: 60, child: Text('60 seconds')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _fastForwardSeconds = val);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save Settings'),
                  onPressed: _saveCredentials,
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'OPML Management',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Import subscriptions from or export them to an OPML 2.0 file, compatible with antennaPod, Pocket Casts, and Apple Podcasts.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.file_upload_outlined),
                        label: const Text('Export OPML'),
                        onPressed: _exportOpml,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.file_download_outlined),
                        label: const Text('Import OPML'),
                        onPressed: _showImportOpmlDialog,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                const Text(
                  'Downloads & Storage',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Manage offline podcast episodes downloaded to your device.',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                _buildDownloadsStorageCard(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadsStorageCard(BuildContext context) {
    final storageAsync = ref.watch(downloadStorageUsageBytesProvider);
    final countAsync = ref.watch(downloadedEpisodesCountProvider);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline Storage Used',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      storageAsync.when(
                        data: (bytes) {
                          final count = countAsync.valueOrNull ?? 0;
                          return Text(
                            '${_formatBytes(bytes)} across $count downloaded ${count == 1 ? 'episode' : 'episodes'}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          );
                        },
                        loading: () => const Text('Calculating...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        error: (err, st) => const Text('Storage calculation error', style: TextStyle(fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh storage info',
                  onPressed: () {
                    ref.invalidate(downloadStorageUsageBytesProvider);
                    ref.invalidate(downloadedEpisodesCountProvider);
                  },
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 18),
                  label: const Text('Clear All'),
                  onPressed: () => _showClearAllDownloadsDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Open Download Center'),
                onPressed: () {
                  PodcastMerlinApp.mainShellKey.currentState?.navigateTo(2);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _showClearAllDownloadsDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Downloads?'),
        content: const Text(
          'This will delete all downloaded audio files from your device. Your playback history and subscriptions will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await ref.read(episodeDownloadServiceProvider).clearAllDownloads();
      ref.invalidate(downloadStorageUsageBytesProvider);
      ref.invalidate(downloadedEpisodesCountProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared $deleted downloaded audio ${deleted == 1 ? 'file' : 'files'}')),
        );
      }
    }
  }
}
