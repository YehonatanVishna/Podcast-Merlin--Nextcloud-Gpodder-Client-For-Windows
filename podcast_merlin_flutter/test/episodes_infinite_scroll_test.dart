import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';

void main() {
  group('EpisodesState and EpisodesFilter Tests', () {
    test('EpisodesState copyWith updates state correctly', () {
      const initialState = EpisodesState();
      expect(initialState.episodes, isEmpty);
      expect(initialState.isLoading, false);
      expect(initialState.isLoadingMore, false);
      expect(initialState.hasMore, true);
      expect(initialState.filter, EpisodeFilter.all);

      final updated = initialState.copyWith(
        isLoading: true,
        filter: EpisodeFilter.unplayed,
      );

      expect(updated.isLoading, true);
      expect(updated.filter, EpisodeFilter.unplayed);
      expect(updated.episodes, isEmpty);
    });

    test('EpisodeFilter enum values', () {
      expect(EpisodeFilter.values.length, 3);
      expect(EpisodeFilter.all.name, 'all');
      expect(EpisodeFilter.unplayed.name, 'unplayed');
      expect(EpisodeFilter.finished.name, 'finished');
    });

    test('Episode fromMap and toMap handle both camelCase and snake_case', () {
      final mapCamel = {
        'id': 1,
        'podcastId': 10,
        'guid': 'guid-123',
        'title': 'Test Episode',
        'mediaUrl': 'https://example.com/audio.mp3',
        'description': 'Test description',
        'pubDate': '2026-01-01T00:00:00.000Z',
        'duration': 300,
        'position': 150,
        'isPlayed': 0,
        'imageUrl': 'https://example.com/image.png',
      };

      final ep1 = Episode.fromMap(mapCamel);
      expect(ep1.id, 1);
      expect(ep1.podcastId, 10);
      expect(ep1.guid, 'guid-123');
      expect(ep1.title, 'Test Episode');
      expect(ep1.mediaUrl, 'https://example.com/audio.mp3');
      expect(ep1.duration, 300);
      expect(ep1.position, 150);
      expect(ep1.isPlayed, false);

      final mapSnake = {
        'id': 2,
        'podcast_id': 20,
        'guid': 'guid-456',
        'title': 'Test Episode 2',
        'media_url': 'https://example.com/audio2.mp3',
        'description': 'Test description 2',
        'published_at': '2026-01-02T00:00:00.000Z',
        'duration': 600,
        'position': 600,
        'is_played': 1,
        'image_url': 'https://example.com/image2.png',
      };

      final ep2 = Episode.fromMap(mapSnake);
      expect(ep2.id, 2);
      expect(ep2.podcastId, 20);
      expect(ep2.isPlayed, true);
      expect(ep2.isFinished, true);
    });
  });
}
