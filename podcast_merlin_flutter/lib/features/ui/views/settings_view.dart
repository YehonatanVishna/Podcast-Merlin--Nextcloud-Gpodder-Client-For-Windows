import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../sync/opml_service.dart';
import '../../sync/secure_storage_service.dart';
import '../widgets/sync_error_banner.dart';

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
    final db = ref.read(databaseProvider);
    final podcasts = await db.getAllPodcasts();
    final xmlContent = OpmlService.generateOpml(podcasts: podcasts);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export Subscriptions (${podcasts.length} feeds)'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('OPML 2.0 XML:'),
              const SizedBox(height: 8),
              TextField(
                controller: TextEditingController(text: xmlContent),
                maxLines: 10,
                readOnly: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy to Clipboard'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: xmlContent));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Exported ${podcasts.length} subscriptions to OPML (copied to clipboard)')),
              );
            },
          ),
        ],
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Exported ${podcasts.length} subscriptions to OPML')),
    );
  }

  void _showImportOpmlDialog() {
    final textController = TextEditingController();
    bool syncWithServer = true;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final outlines = OpmlService.parseOpml(textController.text);

          return AlertDialog(
            title: const Text('Import Subscriptions from OPML'),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Paste OPML 2.0 XML or file content below:'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: textController,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      hintText: '<opml version="2.0">...',
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: outlines.isNotEmpty
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.grey.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      outlines.isNotEmpty
                          ? 'Detected ${outlines.length} podcast(s):\n${outlines.take(4).map((o) => '• ${o.title.isNotEmpty ? o.title : o.xmlUrl}').join('\n')}${outlines.length > 4 ? '\n• ...and ${outlines.length - 4} more' : ''}'
                          : 'Paste valid OPML XML above to preview feeds',
                      style: TextStyle(
                        fontSize: 12,
                        color: outlines.isNotEmpty ? Colors.green[900] : Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: const Text('Sync new feeds with gPodder', style: TextStyle(fontSize: 13)),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: syncWithServer,
                    onChanged: (val) => setDialogState(() => syncWithServer = val),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: outlines.isEmpty
                    ? null
                    : () async {
                        final db = ref.read(databaseProvider);
                        final imported = await OpmlService.importOpml(
                          textController.text,
                          db,
                          syncWithServer: syncWithServer,
                        );
                        await ref.read(podcastsNotifierProvider.notifier).loadPodcasts();
                        if (syncWithServer) {
                          ref.read(syncStatusNotifierProvider.notifier).pushBacklog().catchError((_) => false);
                        }
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Successfully imported ${imported.length} new podcast(s)')),
                          );
                        }
                      },
                child: Text('Import (${outlines.length})'),
              ),
            ],
          );
        },
      ),
    );
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
