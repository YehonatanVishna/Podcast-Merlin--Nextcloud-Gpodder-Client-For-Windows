import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/episode.dart';
import '../../core/models/gpodder_action.dart';
import '../sync/sync_service.dart';
import 'linux_mpris_service.dart';

class MerlinAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final DatabaseHelper _db = DatabaseHelper.instance;
  final SyncService _syncService = SyncService();

  Episode? _currentEpisode;
  Timer? _positionSyncTimer;
  int _lastSyncedPosition = -1;

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  MerlinAudioHandler() {
    _initAudioSession();
    _initPlayerListeners();
    LinuxMprisService.instance.init(this);
  }

  Episode? get currentEpisode => _currentEpisode;

  Future<void> _initAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());

      session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(0.5);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              pause();
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              _player.setVolume(1.0);
              break;
            case AudioInterruptionType.pause:
              play();
              break;
            case AudioInterruptionType.unknown:
              break;
          }
        }
      });

      session.becomingNoisyEventStream.listen((_) {
        pause();
      });
    } catch (e) {
      if (kDebugMode) print('AudioSession initialization error: $e');
    }
  }

  void _initPlayerListeners() {
    _playbackEventSub = _player.playbackEventStream.listen(
      (event) {
        final playing = _player.playing;
        final newState = playbackState.value.copyWith(
          controls: [
            MediaControl.rewind,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.fastForward,
            MediaControl.stop,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
            MediaAction.setSpeed,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: const {
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[_player.processingState]!,
          playing: playing,
          updatePosition: _player.position,
          bufferedPosition: _player.bufferedPosition,
          speed: _player.speed,
        );
        playbackState.add(newState);
        LinuxMprisService.instance.updateState(newState, mediaItem.value);
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) print('PlaybackEventStream error: $e');
      },
    );

    _playerStateSub = _player.playerStateStream.listen(
      (state) {
        if (state.processingState == ProcessingState.completed) {
          _onPlaybackCompleted();
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) print('PlayerStateStream error: $e');
      },
    );
  }

  @override
  Future<void> rewind() async {
    await seekRelative(-15);
  }

  @override
  Future<void> fastForward() async {
    await seekRelative(30);
  }

  Future<void> playEpisode(Episode episode) async {
    Episode epToPlay = episode;
    if (epToPlay.podcastRss.isEmpty && epToPlay.podcastId != null && epToPlay.podcastId! > 0) {
      final pod = await _db.getPodcastById(epToPlay.podcastId!);
      if (pod != null) {
        epToPlay = epToPlay.copyWith(podcastRss: pod.rssUrl);
      }
    }

    _currentEpisode = epToPlay;
    _lastSyncedPosition = -1; // Reset stale position marker

    final newItem = MediaItem(
      id: epToPlay.mediaUrl,
      album: epToPlay.podcastRss,
      title: epToPlay.title,
      artUri: epToPlay.imageUrl.isNotEmpty ? Uri.tryParse(epToPlay.imageUrl) : null,
      duration: Duration(seconds: epToPlay.duration),
    );
    mediaItem.add(newItem);
    LinuxMprisService.instance.updateState(playbackState.value, newItem);

    try {
      await _player.setUrl(epToPlay.mediaUrl);
      if (epToPlay.position > 0 && epToPlay.position < (epToPlay.duration - 5)) {
        await _player.seek(Duration(seconds: epToPlay.position));
      }
      await play();
      _startPeriodicPositionSync();
    } on PlayerInterruptedException {
      // Swallowed on rapid track change
    } catch (e) {
      if (kDebugMode) print('Error playing episode: $e');
    }
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
      _startPeriodicPositionSync();
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
      _stopPeriodicPositionSync();
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      _stopPeriodicPositionSync();
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> setSpeed(double speed) async {
    try {
      await _player.setSpeed(speed);
    } catch (_) {}
  }

  Future<void> seekRelative(int seconds) async {
    final currentPos = _player.position;
    final newPos = currentPos + Duration(seconds: seconds);
    final duration = _player.duration;

    if (newPos < Duration.zero) {
      await seek(Duration.zero);
    } else if (duration != null && duration > Duration.zero && newPos > duration) {
      await seek(duration);
    } else {
      await seek(newPos);
    }
  }

  void _startPeriodicPositionSync() {
    _stopPeriodicPositionSync();
    _positionSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _enqueueCurrentPositionAction();
    });
  }

  void _stopPeriodicPositionSync() {
    _positionSyncTimer?.cancel();
    _positionSyncTimer = null;
  }

  Future<void> _enqueueCurrentPositionAction() async {
    if (_currentEpisode == null) return;
    var podcastRss = _currentEpisode!.podcastRss;
    if (podcastRss.isEmpty && _currentEpisode!.podcastId != null && _currentEpisode!.podcastId! > 0) {
      final pod = await _db.getPodcastById(_currentEpisode!.podcastId!);
      if (pod != null) {
        podcastRss = pod.rssUrl;
        _currentEpisode = _currentEpisode!.copyWith(podcastRss: podcastRss);
      }
    }

    final currentSec = _player.position.inSeconds;
    final totalSec = (_player.duration?.inSeconds ?? _currentEpisode!.duration);

    if (currentSec == _lastSyncedPosition) return;
    _lastSyncedPosition = currentSec;

    final isPlayed = (totalSec > 0 && currentSec >= (totalSec - 10));
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, currentSec, isPlayed: isPlayed);

    if (podcastRss.isNotEmpty) {
      final action = GPodderAction(
        podcast: podcastRss,
        episode: _currentEpisode!.mediaUrl,
        action: 'play',
        timestamp: DateTime.now(),
        position: currentSec,
        started: 0,
        total: totalSec,
      );
      await _db.enqueueAction(action);

      // Trigger automatic background push to gPodder server
      _syncService.pushPendingActions().catchError((_) => false);
    }
  }

  Future<void> _onPlaybackCompleted() async {
    if (_currentEpisode == null) return;
    var podcastRss = _currentEpisode!.podcastRss;
    if (podcastRss.isEmpty && _currentEpisode!.podcastId != null && _currentEpisode!.podcastId! > 0) {
      final pod = await _db.getPodcastById(_currentEpisode!.podcastId!);
      if (pod != null) {
        podcastRss = pod.rssUrl;
      }
    }

    final totalSec = (_player.duration?.inSeconds ?? _currentEpisode!.duration);
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, totalSec, isPlayed: true);

    if (podcastRss.isNotEmpty) {
      final action = GPodderAction(
        podcast: podcastRss,
        episode: _currentEpisode!.mediaUrl,
        action: 'play',
        timestamp: DateTime.now(),
        position: totalSec,
        started: 0,
        total: totalSec,
      );
      await _db.enqueueAction(action);
      _syncService.pushPendingActions().catchError((_) => false);
    }
    _stopPeriodicPositionSync();
  }

  void dispose() {
    _stopPeriodicPositionSync();
    _playbackEventSub?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
  }
}
