import 'package:flutter/material.dart';
import 'podcast_catalog_view.dart';
import 'episode_list_view.dart';
import 'settings_view.dart';
import '../widgets/player_dock.dart';
import '../../../core/models/podcast.dart';

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

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => MainShellState();
}

class MainShellState extends State<MainShell> {
  final List<ShellNavigationState> _history = [
    const ShellNavigationState(selectedIndex: 0, selectedPodcast: null),
  ];
  int _historyIndex = 0;

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
          const SettingsView(),
        ];

        return Scaffold(
          body: Row(
            children: [
              if (isDesktop)
                NavigationRail(
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 40,
                      height: 40,
                      cacheWidth: 80,
                      cacheHeight: 80,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.podcasts, size: 40),
                    ),
                  ),
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) {
                    navigateTo(index, podcast: index == 0 ? null : (index == 1 ? selectedPodcast : null));
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
                  onTap: (index) {
                    navigateTo(index, podcast: index == 0 ? null : (index == 1 ? selectedPodcast : null));
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
