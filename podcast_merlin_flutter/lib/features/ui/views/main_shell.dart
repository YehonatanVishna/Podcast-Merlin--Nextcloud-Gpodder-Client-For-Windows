import 'package:flutter/material.dart';
import 'podcast_catalog_view.dart';
import 'episode_list_view.dart';
import 'settings_view.dart';
import '../widgets/player_dock.dart';
import '../../../core/models/podcast.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  Podcast? _selectedPodcast;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 768;

        final pages = [
          PodcastCatalogView(
            onPodcastSelected: (pod) {
              setState(() {
                _selectedPodcast = pod;
                _selectedIndex = 1;
              });
            },
          ),
          EpisodeListView(
            podcast: _selectedPodcast,
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
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _selectedIndex = index;
                      if (index == 0) _selectedPodcast = null;
                    });
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
                        index: _selectedIndex,
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
                  currentIndex: _selectedIndex,
                  onTap: (index) {
                    setState(() {
                      _selectedIndex = index;
                      if (index == 0) _selectedPodcast = null;
                    });
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
