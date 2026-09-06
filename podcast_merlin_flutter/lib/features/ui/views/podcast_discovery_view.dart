import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/models/search_result_podcast.dart';
import '../../../core/providers/app_providers.dart';
import '../../discovery/discovery_notifier.dart';

class PodcastDiscoveryView extends ConsumerStatefulWidget {
  const PodcastDiscoveryView({super.key});

  @override
  ConsumerState<PodcastDiscoveryView> createState() => _PodcastDiscoveryViewState();
}

class _PodcastDiscoveryViewState extends ConsumerState<PodcastDiscoveryView> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounceTimer;
  final Set<String> _subscribingUrls = {};

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 400), () {
      ref.read(discoveryNotifierProvider.notifier).search(query);
    });
  }

  Future<void> _subscribePodcast(SearchResultPodcast item) async {
    if (_subscribingUrls.contains(item.rssUrl)) return;
    setState(() {
      _subscribingUrls.add(item.rssUrl);
    });

    try {
      final success = await ref.read(podcastsNotifierProvider.notifier).addPodcastFeed(item.rssUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? 'Subscribed to "${item.title}"'
                  : 'Failed to subscribe to "${item.title}"',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() {
          _subscribingUrls.remove(item.rssUrl);
        });
      }
    }
  }

  void _showPodcastDetails(SearchResultPodcast item, bool isSubscribed) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(item.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.imageUrl.isNotEmpty)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        width: 140,
                        height: 140,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const Icon(Icons.podcasts, size: 80),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (item.author.isNotEmpty) ...[
                  Text(
                    'Author: ${item.author}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                ],
                if (item.categories.isNotEmpty) ...[
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: item.categories.map((c) {
                      return Chip(
                        label: Text(c, style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  item.description.isNotEmpty ? item.description : 'No description available.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (item.websiteUrl.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () async {
                      final uri = Uri.tryParse(item.websiteUrl);
                      if (uri != null && await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      }
                    },
                    child: Text(
                      'Visit Website',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton.icon(
              icon: isSubscribed
                  ? const Icon(Icons.check)
                  : (_subscribingUrls.contains(item.rssUrl)
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add)),
              label: Text(isSubscribed ? 'Subscribed' : 'Subscribe'),
              onPressed: isSubscribed || _subscribingUrls.contains(item.rssUrl)
                  ? null
                  : () {
                      Navigator.pop(context);
                      _subscribePodcast(item);
                    },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final discoveryState = ref.watch(discoveryNotifierProvider);
    final searchService = ref.watch(multisourceSearchServiceProvider);
    final podcastsAsync = ref.watch(podcastsNotifierProvider);

    final subscribedUrls = podcastsAsync.when(
      data: (list) => list.map((p) => p.rssUrl).toSet(),
      loading: () => <String>{},
      error: (_, _) => <String>{},
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover Podcasts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              if (discoveryState.currentQuery.isNotEmpty) {
                ref.read(discoveryNotifierProvider.notifier).search(discoveryState.currentQuery);
              } else {
                ref.read(discoveryNotifierProvider.notifier).loadTrending();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search podcasts (e.g. Technology, News, Science)...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                ref.read(discoveryNotifierProvider.notifier).loadTrending();
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                if (searchService.availableProviders.length > 1) ...[
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: discoveryState.activeProviderId,
                    onChanged: (newId) {
                      if (newId != null) {
                        ref.read(discoveryNotifierProvider.notifier).setActiveProvider(newId);
                      }
                    },
                    items: searchService.availableProviders.map((p) {
                      return DropdownMenuItem<String>(
                        value: p.id,
                        child: Text(p.displayName),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Text(
                  discoveryState.isTrending
                      ? '🔥 Trending Podcasts'
                      : 'Search Results (${discoveryState.results.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _buildBody(discoveryState, subscribedUrls),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DiscoveryState discoveryState, Set<String> subscribedUrls) {
    if (discoveryState.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Searching podcast directories...'),
          ],
        ),
      );
    }

    if (discoveryState.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.info_outline, size: 56, color: Colors.amber),
              const SizedBox(height: 16),
              Text(
                discoveryState.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                onPressed: () {
                  if (discoveryState.currentQuery.isNotEmpty) {
                    ref.read(discoveryNotifierProvider.notifier).search(discoveryState.currentQuery);
                  } else {
                    ref.read(discoveryNotifierProvider.notifier).loadTrending();
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    if (discoveryState.results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              discoveryState.isTrending
                  ? 'No trending podcasts found.'
                  : 'No podcasts matched "${discoveryState.currentQuery}".',
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 900
            ? 3
            : (constraints.maxWidth > 600 ? 2 : 1);

        if (crossAxisCount == 1) {
          return ListView.builder(
            itemCount: discoveryState.results.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemBuilder: (context, index) {
              final item = discoveryState.results[index];
              final isSubscribed = subscribedUrls.contains(item.rssUrl);
              final isSubscribing = _subscribingUrls.contains(item.rssUrl);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: item.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: item.imageUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Icon(Icons.podcasts, size: 40),
                          )
                        : const Icon(Icons.podcasts, size: 40),
                  ),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    item.author.isNotEmpty ? item.author : item.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: isSubscribed
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : (isSubscribing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add_circle_outline)),
                    onPressed: isSubscribed || isSubscribing
                        ? null
                        : () => _subscribePodcast(item),
                  ),
                  onTap: () => _showPodcastDetails(item, isSubscribed),
                ),
              );
            },
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: discoveryState.results.length,
          itemBuilder: (context, index) {
            final item = discoveryState.results[index];
            final isSubscribed = subscribedUrls.contains(item.rssUrl);
            final isSubscribing = _subscribingUrls.contains(item.rssUrl);

            return Card(
              child: InkWell(
                onTap: () => _showPodcastDetails(item, isSubscribed),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: item.imageUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: item.imageUrl,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorWidget: (_, _, _) => const Icon(Icons.podcasts, size: 40),
                              )
                            : const Icon(Icons.podcasts, size: 40),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item.author.isNotEmpty ? item.author : item.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        onPressed: isSubscribed || isSubscribing
                            ? null
                            : () => _subscribePodcast(item),
                        child: isSubscribed
                            ? const Icon(Icons.check, size: 18)
                            : (isSubscribing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Text('Subscribe')),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
