import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'podcast_catalog_view.dart';
import 'episode_list_view.dart';
import 'podcast_discovery_view.dart';
import 'settings_view.dart';
import '../widgets/player_dock.dart';
import '../../../core/models/podcast.dart';
import '../../../core/providers/app_providers.dart';

class ShellNavigationState {
  final int selectedIndex;
  final Podcast? selectedPodcast;

  const ShellNavigationState({
    required this.selectedIndex,
    this.selectedPodcast,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellNavigationState &&
          runtimeType == other.runtimeType &&
          selectedIndex == other.selectedIndex &&
          selectedPodcast?.id == other.selectedPodcast?.id;

  @override
  int get hashCode => selectedIndex.hashCode ^ (selectedPodcast?.id.hashCode ?? 0);
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => MainShellState();
}

class MainShellState extends ConsumerState<MainShell> {
  final List<ShellNavigationState> _history = [
    const ShellNavigationState(selectedIndex: 0, selectedPodcast: null),
  ];
  int _historyIndex = 0;
  StreamSubscription<String>? _playbackErrorSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playbackErrorSub = ref.read(audioHandlerProvider).onPlaybackError.listen((errorMsg) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red[800],
            duration: const Duration(seconds: 8),
            content: Text(
              errorMsg,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            action: SnackBarAction(
              label: 'Dismiss',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _playbackErrorSub?.cancel();
    super.dispose();
  }

  int get selectedIndex => _history[_historyIndex].selectedIndex;
  Podcast? get selectedPodcast => _history[_historyIndex].selectedPodcast;

  void navigateTo(int index, {Podcast? podcast}) {
    final newState = ShellNavigationState(
      selectedIndex: index,
      selectedPodcast: podcast,
    );

    if (newState == _history[_historyIndex]) {
      return;
    }

    setState(() {
      if (_historyIndex < _history.length - 1) {
        _history.removeRange(_historyIndex + 1, _history.length);
      }
      _history.add(newState);
      _historyIndex = _history.length - 1;
    });
  }

  bool goBack() {
    if (_historyIndex > 0) {
      setState(() {
        _historyIndex--;
      });
      return true;
    }
    return false;
  }

  bool goForward() {
    if (_historyIndex < _history.length - 1) {
      setState(() {
        _historyIndex++;
      });
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;

        final pages = [
          PodcastCatalogView(
            onPodcastSelected: (pod) {
              navigateTo(1, podcast: pod);
            },
          ),
          EpisodeListView(
            podcast: selectedPodcast,
            onBackPressed: _historyIndex > 0 ? () => goBack() : null,
          ),
          const PodcastDiscoveryView(),
          const SettingsView(),
        ];

        return Scaffold(
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: SvgPicture.asset(
                      'assets/images/logo.svg',
                      width: 40,
                      height: 40,
                    ),
                  ),
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) {
                    navigateTo(index, podcast: index == 1 ? selectedPodcast : null);
                  },
                  labelType: NavigationRailLabelType.selected,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.podcasts_outlined),
                      selectedIcon: Icon(Icons.podcasts),
                      label: Text('Catalog'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.playlist_play_outlined),
                      selectedIcon: Icon(Icons.playlist_play),
                      label: Text('Episodes'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.explore_outlined),
                      selectedIcon: Icon(Icons.explore),
                      label: Text('Discover'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
              if (isDesktop) const VerticalDivider(thickness: 1, width: 1),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: selectedIndex,
                        children: pages,
                      ),
                    ),
                    const PlayerDock(),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: !isDesktop
              ? BottomNavigationBar(
                  currentIndex: selectedIndex,
                  type: BottomNavigationBarType.fixed,
                  onTap: (index) {
                    navigateTo(index, podcast: index == 1 ? selectedPodcast : null);
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.podcasts),
                      label: 'Catalog',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.playlist_play),
                      label: 'Episodes',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.explore),
                      label: 'Discover',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.settings),
                      label: 'Settings',
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }
}
