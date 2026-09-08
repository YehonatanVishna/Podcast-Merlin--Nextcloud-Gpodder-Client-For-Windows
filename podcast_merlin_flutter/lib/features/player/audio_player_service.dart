import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../../core/database/database_helper.dart';
import '../../core/database/ffi_init.dart';
import '../../core/models/episode.dart';
import '../../core/models/gpodder_action.dart';
import '../../core/services/image_cache_service.dart';
import '../sync/secure_storage_service.dart';
import '../sync/sync_service.dart';
import 'linux_mpris_service.dart';

typedef PositionUpdateEvent = ({String mediaUrl, int position, bool isPlayed});
enum SleepTimerMode { none, duration, endOfEpisode }

class MerlinAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player;
  final DatabaseHelper _db;
  final SyncService _syncService;
  final StreamController<PositionUpdateEvent> _positionUpdateController =
      StreamController<PositionUpdateEvent>.broadcast();

  // Queue state
  List<Episode> _queue = [];
  final StreamController<List<Episode>> _queueController =
      StreamController<List<Episode>>.broadcast();

  // Sleep timer state
  Timer? _sleepTimer;
  Duration? _sleepTimerRemaining;
  SleepTimerMode _sleepTimerMode = SleepTimerMode.none;
  final StreamController<Duration?> _sleepTimerController =
      StreamController<Duration?>.broadcast();

  // Seek durations state
  int rewindDuration = 10;
  int fastForwardDuration = 30;
  final StreamController<({int rewind, int fastForward})> _seekDurationsController =
      StreamController<({int rewind, int fastForward})>.broadcast();
  final StreamController<String> _playbackErrorController =
      StreamController<String>.broadcast();

  Stream<String> get onPlaybackError => _playbackErrorController.stream;

  Episode? _currentEpisode;
  Timer? _positionSyncTimer;
  int _lastSyncedPosition = -1;

  StreamSubscription<PlaybackEvent>? _playbackEventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;

  final Future<void> Function(String url)? urlLoader;
  double _speed = 1.0;

  MerlinAudioHandler({
    DatabaseHelper? db,
    SyncService? syncService,
    AudioPlayer? player,
    this.urlLoader,
  })  : _db = db ?? DatabaseHelper.instance,
        _syncService = syncService ?? SyncService(),
        _player = player ?? AudioPlayer() {
    if (urlLoader == null) {
      _initAudioSession();
      _initPlayerListeners();
      LinuxMprisService.instance.init(this);
    }
    _loadInitialQueue();
    _loadSeekDurations();
  }

  Stream<PositionUpdateEvent> get onPositionUpdated => _positionUpdateController.stream;
  Episode? get currentEpisode => _currentEpisode;

  // Queue getters
  Stream<List<Episode>> get queueStream => _queueController.stream;
  List<Episode> get currentQueue => List.unmodifiable(_queue);
  List<Episode> get episodeQueue => List.unmodifiable(_queue);

  // Sleep timer getters
  Stream<Duration?> get sleepTimerStream => _sleepTimerController.stream;
  Duration? get sleepTimerRemaining => _sleepTimerRemaining;
  SleepTimerMode get sleepTimerMode => _sleepTimerMode;
  bool get isSleepTimerActive => _sleepTimerMode != SleepTimerMode.none;
  bool get isSleepTimerEndOfEpisode => _sleepTimerMode == SleepTimerMode.endOfEpisode;

  // Seek durations getters
  Stream<({int rewind, int fastForward})> get seekDurationsStream => _seekDurationsController.stream;
  double get speed => urlLoader != null ? _speed : _player.speed;

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
            MediaAction.play,
            MediaAction.pause,
            MediaAction.playPause,
            MediaAction.stop,
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
            MediaAction.rewind,
            MediaAction.fastForward,
            MediaAction.skipToNext,
            MediaAction.skipToPrevious,
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

    _positionSub = _player.positionStream.listen(
      (position) {
        if (_player.playing) {
          final newState = playbackState.value.copyWith(
            updatePosition: position,
            bufferedPosition: _player.bufferedPosition,
          );
          playbackState.add(newState);
          LinuxMprisService.instance.updateState(newState, mediaItem.value);
        }
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) print('PositionStream error: $e');
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

  Future<void> _setActiveAudioSession(bool active) async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(active);
    } catch (e) {
      if (kDebugMode) print('AudioSession setActive error: $e');
    }
  }

  @override
  Future<void> rewind() async {
    await seekRelative(-rewindDuration);
  }

  @override
  Future<void> fastForward() async {
    await seekRelative(fastForwardDuration);
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isNotEmpty) {
      await playNextInQueue();
    } else {
      await fastForward();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    await rewind();
  }

  Future<void> playEpisode(Episode episode) async {
    if (episode.id != null) {
      await removeFromQueue(episode.id!);
    }

    if (_currentEpisode != null && _currentEpisode!.mediaUrl != episode.mediaUrl) {
      if (!_currentEpisode!.isPlayed && !_currentEpisode!.isFinished) {
        await _enqueueCurrentPositionAction();
      }
    }

    Episode epToPlay = episode;
    String showTitle = 'Podcast Merlin';
    if (epToPlay.podcastId != null && epToPlay.podcastId! > 0) {
      final pod = await _db.getPodcastById(epToPlay.podcastId!);
      if (pod != null) {
        if (pod.rssUrl.isNotEmpty) {
          epToPlay = epToPlay.copyWith(podcastRss: pod.rssUrl);
        }
        if (pod.title.isNotEmpty) {
          showTitle = pod.title;
        }
      }
    }

    final bool wasFinished = epToPlay.isFinished;
    if (wasFinished) {
      epToPlay = epToPlay.copyWith(position: 0, isPlayed: false);
      await _db.updateEpisodePlaybackState(epToPlay.mediaUrl, 0, isPlayed: false);
      if (!_positionUpdateController.isClosed) {
        _positionUpdateController.add((mediaUrl: epToPlay.mediaUrl, position: 0, isPlayed: false));
      }
      if (epToPlay.podcastRss.isNotEmpty) {
        final resetAction = GPodderAction(
          podcast: epToPlay.podcastRss,
          episode: epToPlay.mediaUrl,
          guid: epToPlay.guid,
          action: 'play',
          timestamp: DateTime.now(),
          position: 0,
          started: 0,
          total: epToPlay.duration,
        );
        await _db.enqueueAction(resetAction);
        _syncService.pushPendingActions().catchError((_) => false);
      }
    }

    _currentEpisode = epToPlay;
    _lastSyncedPosition = -1; // Reset stale position marker

    // Pre-cache episode artwork asynchronously
    if (epToPlay.imageUrl.isNotEmpty) {
      ImageCacheService.precacheImageUrl(epToPlay.imageUrl);
    }

    // Use local file URI for MPRIS/OS playback art if on Linux and cached; use network URL on Android/Web
    Uri? artUri;
    if (epToPlay.imageUrl.isNotEmpty) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        final cachedFilePath = await ImageCacheService.getCachedFilePath(epToPlay.imageUrl);
        if (cachedFilePath != null) {
          artUri = Uri.file(cachedFilePath);
        } else {
          artUri = Uri.tryParse(epToPlay.imageUrl);
        }
      } else {
        artUri = Uri.tryParse(epToPlay.imageUrl);
      }
    }

    final newItem = MediaItem(
      id: epToPlay.mediaUrl,
      album: showTitle,
      artist: showTitle,
      title: epToPlay.title,
      artUri: artUri,
      duration: Duration(seconds: epToPlay.duration),
    );
    mediaItem.add(newItem);

    final initialLoadingState = playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        MediaControl.pause,
        MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.playPause,
        MediaAction.stop,
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.rewind,
        MediaAction.fastForward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.setSpeed,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: AudioProcessingState.loading,
      playing: true,
      updatePosition: Duration(seconds: epToPlay.position),
    );
    playbackState.add(initialLoadingState);
    if (urlLoader == null) {
      LinuxMprisService.instance.updateState(initialLoadingState, newItem);
    }

    if (urlLoader != null) {
      try {
        await urlLoader!(epToPlay.mediaUrl);
      } catch (_) {}
      final readyState = initialLoadingState.copyWith(
        playing: true,
        processingState: AudioProcessingState.ready,
      );
      playbackState.add(readyState);
      _startPeriodicPositionSync();
      return;
    }

    if (audioBackendInitError != null && urlLoader == null) {
      final errorMsg = formatAudioBackendError(audioBackendInitError);
      if (kDebugMode) print(errorMsg);
      final errorState = playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      );
      playbackState.add(errorState);
      if (urlLoader == null) {
        LinuxMprisService.instance.updateState(errorState, mediaItem.value);
      }
      if (!_playbackErrorController.isClosed) {
        _playbackErrorController.add(errorMsg);
      }
      return;
    }

    try {
      await _player.setUrl(epToPlay.mediaUrl).timeout(const Duration(seconds: 30));
      if (epToPlay.position > 0 && !epToPlay.isFinished && epToPlay.position < (epToPlay.duration - 5)) {
        await _player.seek(Duration(seconds: epToPlay.position));
      } else {
        await _player.seek(Duration.zero);
      }
      await play();
      _startPeriodicPositionSync();
    } on PlayerInterruptedException {
      // Swallowed on rapid track change
    } catch (e) {
      final errorMsg = formatAudioBackendError(e);
      if (kDebugMode) print(errorMsg);
      final errorState = playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
      );
      playbackState.add(errorState);
      if (urlLoader == null) {
        LinuxMprisService.instance.updateState(errorState, mediaItem.value);
      }
      if (!_playbackErrorController.isClosed) {
        _playbackErrorController.add(errorMsg);
      }
    }
  }

  static String formatAudioBackendError(dynamic error) {
    final s = error.toString();
    if (s.contains('libmpv') || s.contains('MediaKit')) {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) {
        return 'Audio playback on Linux requires libmpv.\n'
            'Please install it using:\n'
            '  sudo dnf install mpv-libs (Fedora / RHEL)\n'
            '  sudo apt install libmpv-dev (Ubuntu / Debian)\n'
            '  sudo pacman -S mpv (Arch Linux)';
      } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        return 'Audio playback requires libmpv-2.dll on Windows.';
      }
    }
    return 'Playback error: $s';
  }


  @override
  Future<void> play() async {
    try {
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(playing: true));
        _startPeriodicPositionSync();
        return;
      }
      await _setActiveAudioSession(true);
      await _player.play();
      _startPeriodicPositionSync();
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    try {
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(playing: false));
        _stopPeriodicPositionSync();
        await _enqueueCurrentPositionAction();
        return;
      }
      await _player.pause();
      _stopPeriodicPositionSync();
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(playing: false));
        _stopPeriodicPositionSync();
        await _enqueueCurrentPositionAction();
        return;
      }
      await _player.stop();
      await _setActiveAudioSession(false);
      _stopPeriodicPositionSync();
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(updatePosition: position));
        await _enqueueCurrentPositionAction();
        return;
      }
      await _player.seek(position);
      await _enqueueCurrentPositionAction();
    } catch (_) {}
  }

  @override
  Future<void> setSpeed(double speed) async {
    try {
      _speed = speed;
      if (urlLoader != null) {
        playbackState.add(playbackState.value.copyWith(speed: speed));
        return;
      }
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
    if (urlLoader != null) return;
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
    if (_currentEpisode!.isPlayed || _currentEpisode!.isFinished) return;
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

    bool isPlayed = false;
    if (totalSec > 0 && currentSec > 0) {
      if (totalSec > 60) {
        if ((totalSec - currentSec) <= 60) {
          isPlayed = true;
        }
      } else {
        if (currentSec >= (totalSec > 10 ? totalSec - 10 : totalSec)) {
          isPlayed = true;
        }
      }
    }
    _currentEpisode = _currentEpisode!.copyWith(position: currentSec, isPlayed: isPlayed);
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, currentSec, isPlayed: isPlayed);
    if (!_positionUpdateController.isClosed) {
      _positionUpdateController.add((mediaUrl: _currentEpisode!.mediaUrl, position: currentSec, isPlayed: isPlayed));
    }

    if (podcastRss.isNotEmpty) {
      final action = GPodderAction(
        podcast: podcastRss,
        episode: _currentEpisode!.mediaUrl,
        guid: _currentEpisode!.guid,
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

    final totalSec = (urlLoader != null
        ? _currentEpisode!.duration
        : (_player.duration?.inSeconds ?? _currentEpisode!.duration));
    _currentEpisode = _currentEpisode!.copyWith(position: totalSec, isPlayed: true);
    await _db.updateEpisodePlaybackState(_currentEpisode!.mediaUrl, totalSec, isPlayed: true);
    if (!_positionUpdateController.isClosed) {
      _positionUpdateController.add((mediaUrl: _currentEpisode!.mediaUrl, position: totalSec, isPlayed: true));
    }

    if (podcastRss.isNotEmpty) {
      final action = GPodderAction(
        podcast: podcastRss,
        episode: _currentEpisode!.mediaUrl,
        guid: _currentEpisode!.guid,
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

    // Check Sleep Timer: if endOfEpisode, stop and cancel timer!
    if (_sleepTimerMode == SleepTimerMode.endOfEpisode) {
      cancelSleepTimer();
      await pause();
      return;
    }

    // Automatically pop and play next episode if queue has items!
    if (_queue.isNotEmpty) {
      await playNextInQueue();
    }
  }

  @visibleForTesting
  Future<void> onPlaybackCompletedForTesting() => _onPlaybackCompleted();

  // --- QUEUE CONTROLS ---

  Future<void> _loadInitialQueue() async {
    try {
      _queue = await _db.getQueue();
      _syncMediaItemQueue();
    } catch (e) {
      if (kDebugMode) print('Error loading initial queue: $e');
    }
  }

  void _syncMediaItemQueue() {
    final mediaItems = _queue.map((ep) => MediaItem(
      id: ep.mediaUrl,
      album: ep.podcastRss,
      artist: ep.podcastRss,
      title: ep.title,
      duration: Duration(seconds: ep.duration),
      artUri: Uri.tryParse(ep.imageUrl),
    )).toList();
    queue.add(mediaItems);
    if (!_queueController.isClosed) {
      _queueController.add(List.unmodifiable(_queue));
    }
  }

  Future<void> addToQueue(Episode episode, {bool playNext = false}) async {
    await _db.addToQueue(episode, playNext: playNext);
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
  }

  Future<void> removeFromQueue(int episodeId) async {
    await _db.removeFromQueue(episodeId);
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    await _db.reorderQueue(oldIndex, newIndex);
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
  }

  Future<void> clearQueue() async {
    await _db.clearQueue();
    _queue.clear();
    _syncMediaItemQueue();
  }

  Future<void> playNextInQueue() async {
    if (_queue.isEmpty) return;
    final nextEpisode = _queue.first;
    if (nextEpisode.id != null) {
      await _db.removeFromQueue(nextEpisode.id!);
    }
    _queue = await _db.getQueue();
    _syncMediaItemQueue();
    await playEpisode(nextEpisode);
  }

  // --- SLEEP TIMER CONTROLS ---

  void setSleepTimer(Duration duration) {
    cancelSleepTimer();
    _sleepTimerMode = SleepTimerMode.duration;
    _sleepTimerRemaining = duration;
    if (!_sleepTimerController.isClosed) {
      _sleepTimerController.add(_sleepTimerRemaining);
    }

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_sleepTimerRemaining == null || _sleepTimerRemaining! <= const Duration(seconds: 1)) {
        timer.cancel();
        _sleepTimer = null;
        _sleepTimerRemaining = null;
        _sleepTimerMode = SleepTimerMode.none;
        if (!_sleepTimerController.isClosed) {
          _sleepTimerController.add(null);
        }
        await pause();
        if (urlLoader == null) {
          await _player.setVolume(1.0);
        }
      } else {
        _sleepTimerRemaining = _sleepTimerRemaining! - const Duration(seconds: 1);
        if (!_sleepTimerController.isClosed) {
          _sleepTimerController.add(_sleepTimerRemaining);
        }

        // Smooth volume fade out in the last 15 seconds
        if (_sleepTimerRemaining!.inSeconds <= 15) {
          final fade = (_sleepTimerRemaining!.inSeconds / 15.0).clamp(0.05, 1.0);
          if (urlLoader == null) {
            await _player.setVolume(fade);
          }
        } else if (urlLoader == null && _player.volume < 1.0) {
          await _player.setVolume(1.0);
        }
      }
    });
  }

  void setSleepTimerEndOfEpisode() {
    cancelSleepTimer();
    _sleepTimerMode = SleepTimerMode.endOfEpisode;
    _sleepTimerRemaining = null;
    if (!_sleepTimerController.isClosed) {
      _sleepTimerController.add(null);
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerRemaining = null;
    _sleepTimerMode = SleepTimerMode.none;
    if (!_sleepTimerController.isClosed) {
      _sleepTimerController.add(null);
    }
    if (urlLoader == null) {
      _player.setVolume(1.0).catchError((_) {});
    }
  }

  // --- SEEK DURATIONS & SETTINGS ---

  Future<void> _loadSeekDurations() async {
    try {
      final storage = SecureStorageService();
      final rew = await storage.read(SecureStorageService.keyRewindDuration);
      final ff = await storage.read(SecureStorageService.keyFastForwardDuration);
      if (rew != null) {
        final parsed = int.tryParse(rew);
        if (parsed != null && parsed > 0) rewindDuration = parsed;
      }
      if (ff != null) {
        final parsed = int.tryParse(ff);
        if (parsed != null && parsed > 0) fastForwardDuration = parsed;
      }
      if (!_seekDurationsController.isClosed) {
        _seekDurationsController.add((rewind: rewindDuration, fastForward: fastForwardDuration));
      }
    } catch (_) {}
  }

  Future<void> setSeekDurations({int? rewind, int? fastForward}) async {
    if (rewind != null && rewind > 0) {
      rewindDuration = rewind;
      await SecureStorageService().write(SecureStorageService.keyRewindDuration, rewind.toString());
    }
    if (fastForward != null && fastForward > 0) {
      fastForwardDuration = fastForward;
      await SecureStorageService().write(SecureStorageService.keyFastForwardDuration, fastForward.toString());
    }
    if (!_seekDurationsController.isClosed) {
      _seekDurationsController.add((rewind: rewindDuration, fastForward: fastForwardDuration));
    }
  }

  void dispose() {
    _stopPeriodicPositionSync();
    _sleepTimer?.cancel();
    _playbackEventSub?.cancel();
    _positionSub?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
    _positionUpdateController.close();
    _queueController.close();
    _sleepTimerController.close();
    _seekDurationsController.close();
    _playbackErrorController.close();
  }

}
