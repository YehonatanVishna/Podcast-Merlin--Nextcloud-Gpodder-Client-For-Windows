import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/database/database_helper.dart';
import '../../core/models/episode.dart';
import '../../core/models/gpodder_action.dart';

class MerlinAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final DatabaseHelper _db = DatabaseHelper.instance;

  Episode? _currentEpisode;
  Timer? _positionSyncTimer;
  int _lastSyncedPosition = -1;

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  MerlinAudioHandler() {
    _initPlayerListeners();
  }

  Episode? get currentEpisode => _currentEpisode;

  void _initPlayerListeners() {
    _playbackEventSub = _player.playbackEventStream.listen(
      (event) {
        final playing = _player.playing;
        playbackState.add(
          playbackState.value.copyWith(
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
            },
            androidCompactActionIndices: const [1],
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
          ),
        );
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

  Future<void> playEpisode(Episode episode) async {
    _currentEpisode = episode;
    _lastSyncedPosition = -1; // Reset stale position marker

    mediaItem.add(
      MediaItem(
        id: episode.mediaUrl,
        album: episode.podcastRss,
        title: episode.title,
        artUri: episode.imageUrl.isNotEmpty ? Uri.tryParse(episode.imageUrl) : null,
        duration: Duration(seconds: episode.duration),
      ),
    );

    try {
      await _player.setUrl(episode.mediaUrl);
      if (episode.position > 0 && episode.position < (episode.duration - 5)) {
        await _player.seek(Duration(seconds: episode.position));
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
    final currentSec = _player.position.inSeconds;
    final totalSec = (_player.duration?.inSeconds ?? _currentEpisode!.duration);

    if (currentSec == _lastSyncedPosition) return;
    _lastSyncedPosition = currentSec;

    final isPlayed = (totalSec > 0 && currentSec >= (totalSec - 10));
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, currentSec, isPlayed: isPlayed);

    final action = GPodderAction(
      podcast: _currentEpisode!.podcastRss,
      episode: _currentEpisode!.mediaUrl,
      action: 'play',
      timestamp: DateTime.now(),
      position: currentSec,
      started: 0,
      total: totalSec,
    );
    await _db.enqueueAction(action);
  }

  Future<void> _onPlaybackCompleted() async {
    if (_currentEpisode == null) return;
    final totalSec = (_player.duration?.inSeconds ?? _currentEpisode!.duration);
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, totalSec, isPlayed: true);

    final action = GPodderAction(
      podcast: _currentEpisode!.podcastRss,
      episode: _currentEpisode!.mediaUrl,
      action: 'play',
      timestamp: DateTime.now(),
      position: totalSec,
      started: 0,
      total: totalSec,
    );
    await _db.enqueueAction(action);
    _stopPeriodicPositionSync();
  }

  void dispose() {
    _stopPeriodicPositionSync();
    _playbackEventSub?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
  }
}
