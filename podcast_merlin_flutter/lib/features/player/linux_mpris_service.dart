import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';

class LinuxMprisService {
  static final LinuxMprisService instance = LinuxMprisService._internal();

  DBusClient? _client;
  _MprisDBusObject? _dbusObject;

  LinuxMprisService._internal();

  Future<void> init(BaseAudioHandler audioHandler) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.linux) return;
    try {
      _client = DBusClient.session();
      _dbusObject = _MprisDBusObject(audioHandler);
      await _client!.registerObject(_dbusObject!);
      await _client!.requestName('org.mpris.MediaPlayer2.podcast_merlin');
    } catch (e) {
      if (kDebugMode) print('Linux MPRIS initialization error: $e');
    }
  }

  void updateState(PlaybackState state, MediaItem? item) {
    _dbusObject?.update(state, item);
  }

  Future<void> dispose() async {
    try {
      if (_dbusObject != null && _client != null) {
        await _client!.unregisterObject(_dbusObject!);
      }
      await _client!.close();
    } catch (_) {}
    _client = null;
    _dbusObject = null;
  }
}

class _MprisDBusObject extends DBusObject {
  final BaseAudioHandler _audioHandler;

  PlaybackState _state = PlaybackState();
  MediaItem? _item;

  _MprisDBusObject(this._audioHandler) : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  void update(PlaybackState state, MediaItem? item) {
    final oldState = _state;
    final oldItem = _item;
    _state = state;
    _item = item;

    final changedProps = <String, DBusValue>{};

    if (oldState.playing != state.playing) {
      changedProps['PlaybackStatus'] = DBusString(state.playing ? 'Playing' : 'Paused');
    }
    if (oldState.updatePosition != state.updatePosition) {
      changedProps['Position'] = DBusInt64(state.updatePosition.inMicroseconds);
    }
    if (oldState.speed != state.speed) {
      changedProps['Rate'] = DBusDouble(state.speed);
    }
    if (oldItem?.id != item?.id || oldItem?.title != item?.title) {
      changedProps['Metadata'] = _buildMetadata();
    }

    if (changedProps.isNotEmpty) {
      emitPropertiesChanged('org.mpris.MediaPlayer2.Player', changedProperties: changedProps);
    }
  }

  DBusValue _buildMetadata() {
    final map = <String, DBusValue>{
      'mpris:trackid': DBusObjectPath('/org/mpris/MediaPlayer2/track/0'),
      if (_item != null) ...{
        'xesam:title': DBusString(_item!.title),
        if (_item!.album != null && _item!.album!.isNotEmpty) 'xesam:album': DBusString(_item!.album!),
        if (_item!.artist != null && _item!.artist!.isNotEmpty)
          'xesam:artist': DBusArray.string([_item!.artist!]),
        if (_item!.duration != null) 'mpris:length': DBusInt64(_item!.duration!.inMicroseconds),
        if (_item!.artUri != null) 'mpris:artUrl': DBusString(_item!.artUri.toString()),
      }
    };
    return DBusDict.stringVariant(map);
  }

  Map<String, DBusValue> _getMediaPlayer2Properties() {
    return {
      'CanQuit': DBusBoolean(true),
      'CanRaise': DBusBoolean(true),
      'HasTrackList': DBusBoolean(false),
      'Identity': DBusString('Podcast Merlin'),
      'DesktopEntry': DBusString('podcast_merlin'),
      'SupportedUriSchemes': DBusArray.string(['http', 'https', 'file']),
      'SupportedMimeTypes': DBusArray.string(['audio/mpeg', 'audio/x-m4a', 'audio/ogg', 'audio/wav']),
    };
  }

  Map<String, DBusValue> _getMediaPlayer2PlayerProperties() {
    return {
      'PlaybackStatus': DBusString(_state.playing ? 'Playing' : 'Paused'),
      'LoopStatus': DBusString('None'),
      'Rate': DBusDouble(_state.speed),
      'Shuffle': DBusBoolean(false),
      'Metadata': _buildMetadata(),
      'Volume': DBusDouble(1.0),
      'Position': DBusInt64(_state.updatePosition.inMicroseconds),
      'MinimumRate': DBusDouble(0.5),
      'MaximumRate': DBusDouble(2.5),
      'CanGoNext': DBusBoolean(true),
      'CanGoPrevious': DBusBoolean(true),
      'CanPlay': DBusBoolean(true),
      'CanPause': DBusBoolean(true),
      'CanSeek': DBusBoolean(true),
      'CanControl': DBusBoolean(true),
    };
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      return DBusGetAllPropertiesResponse(_getMediaPlayer2Properties());
    } else if (interface == 'org.mpris.MediaPlayer2.Player') {
      return DBusGetAllPropertiesResponse(_getMediaPlayer2PlayerProperties());
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    if (interface == 'org.mpris.MediaPlayer2') {
      final props = _getMediaPlayer2Properties();
      if (props.containsKey(name)) return DBusGetPropertyResponse(props[name]!);
    } else if (interface == 'org.mpris.MediaPlayer2.Player') {
      final props = _getMediaPlayer2PlayerProperties();
      if (props.containsKey(name)) return DBusGetPropertyResponse(props[name]!);
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == 'org.mpris.MediaPlayer2') {
      if (methodCall.name == 'Quit') {
        _audioHandler.stop();
        return DBusMethodSuccessResponse();
      } else if (methodCall.name == 'Raise') {
        return DBusMethodSuccessResponse();
      }
    } else if (methodCall.interface == 'org.mpris.MediaPlayer2.Player') {
      switch (methodCall.name) {
        case 'Play':
          _audioHandler.play();
          return DBusMethodSuccessResponse();
        case 'Pause':
          _audioHandler.pause();
          return DBusMethodSuccessResponse();
        case 'PlayPause':
          if (_state.playing) {
            _audioHandler.pause();
          } else {
            _audioHandler.play();
          }
          return DBusMethodSuccessResponse();
        case 'Stop':
          _audioHandler.stop();
          return DBusMethodSuccessResponse();
        case 'Next':
          _audioHandler.fastForward();
          return DBusMethodSuccessResponse();
        case 'Previous':
          _audioHandler.rewind();
          return DBusMethodSuccessResponse();
        case 'Seek':
          if (methodCall.values.isNotEmpty && methodCall.values.first is DBusInt64) {
            final offsetMicros = (methodCall.values.first as DBusInt64).value;
            final seconds = (offsetMicros / 1000000).round();
            if (_audioHandler is SeekHandler) {
              final newPos = _state.updatePosition + Duration(seconds: seconds);
              _audioHandler.seek(newPos);
            }
          }
          return DBusMethodSuccessResponse();
        case 'SetPosition':
          if (methodCall.values.length >= 2 && methodCall.values[1] is DBusInt64) {
            final posMicros = (methodCall.values[1] as DBusInt64).value;
            _audioHandler.seek(Duration(microseconds: posMicros));
          }
          return DBusMethodSuccessResponse();
      }
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}
