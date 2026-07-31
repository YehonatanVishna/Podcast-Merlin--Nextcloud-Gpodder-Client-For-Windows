import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
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
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveCredentials() async {
    final storage = ref.read(secureStorageProvider);
    await storage.write(SecureStorageService.keyServerUrl, _serverController.text.trim());
    await storage.write(SecureStorageService.keyUsername, _userController.text.trim());
    await storage.write(SecureStorageService.keyPassword, _passwordController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Credentials saved successfully')),
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final syncStatus = ref.watch(syncStatusNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nextcloud gPodder Settings'),
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text('Save Credentials'),
                        onPressed: _saveCredentials,
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
