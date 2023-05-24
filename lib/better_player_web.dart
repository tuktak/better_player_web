import 'dart:async';

import 'package:better_player/better_player.dart';
import 'package:better_player_web/src/shaka_video_player.dart';
import 'package:better_player_web/src/video_player.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:flutter/widgets.dart';
import 'src/shims/dart_ui.dart' as ui;
// ignore: implementation_imports
import 'package:better_player/src/video_player/video_player_platform_interface.dart';

/// An implementation of [BetterPlayerPlatform] that uses method channels.
class BetterPlayerPlugin extends VideoPlayerPlatform {
  /// Registers this class as the default instance of [VideoPlayerPlatform].
  static void registerWith(Registrar registrar) {
    VideoPlayerPlatform.instance = BetterPlayerPlugin();
  }

  // Map of textureId -> VideoPlayer instances
  final Map<int, VideoPlayer> _videoPlayers = <int, VideoPlayer>{};

  @override
  Future<void> init() async {
    return _disposeAllPlayers();
  }

  @override
  Future<void> dispose(int? textureId) async {
    _player(textureId!).dispose();
    _videoPlayers.remove(textureId);
    return;
  }

  void _disposeAllPlayers() {
    for (final VideoPlayer videoPlayer in _videoPlayers.values) {
      videoPlayer.dispose();
    }
    _videoPlayers.clear();
  }

  @override
  Future<int?> create(
      {BetterPlayerBufferingConfiguration? bufferingConfiguration}) {
    // TODO: implement create
    return super.create(bufferingConfiguration: bufferingConfiguration);
  }

  @override
  Future<int> setDataSource(int? textureId, DataSource dataSource) async {
    // final int textureId = textureId;

    late String uri;
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        // Do NOT modify the incoming uri, it can be a Blob, and Safari doesn't
        // like blobs that have changed.
        uri = dataSource.uri ?? '';
        break;
      case DataSourceType.asset:
        String assetUrl = dataSource.asset!;
        if (dataSource.package != null && dataSource.package!.isNotEmpty) {
          assetUrl = 'packages/${dataSource.package}/$assetUrl';
        }
        assetUrl = ui.webOnlyAssetManager.getAssetUrl(assetUrl);
        uri = assetUrl;
        break;
      case DataSourceType.file:
        return Future<int>.error(UnimplementedError(
            'web implementation of video_player cannot play local files'));
    }

    final VideoPlayer player = ShakaVideoPlayer(
      key: textureId.toString(),
      src: uri,
      drmConfiguration: BetterPlayerDrmConfiguration(
        certificateUrl: dataSource.certificateUrl,
        clearKey: dataSource.clearKey,
        drmType: BetterPlayerDrmType.widevine,
        headers: dataSource.drmHeaders,
        licenseUrl: dataSource.licenseUrl,
      ),
    );

    player.registerElement(textureId!);
    await player.initialize();

    _videoPlayers[textureId] = player;

    return textureId;
  }

  @override
  Future<void> setLooping(int? textureId, bool looping) async {
    return _player(textureId!).setLooping(looping);
  }

  @override
  Future<void> play(int? textureId) async {
    return _player(textureId!).play();
  }

  @override
  Future<void> pause(int? textureId) async {
    return _player(textureId!).pause();
  }

  @override
  Future<void> setVolume(int? textureId, double volume) async {
    return _player(textureId!).setVolume(volume);
  }

  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    return _player(textureId).setPlaybackSpeed(speed);
  }

  @override
  Future<void> seekTo(int? textureId, Duration? position) async {
    return _player(textureId!).seekTo(position!);
  }

  @override
  Future<Duration> getPosition(int? textureId) async {
    return _player(textureId!).getPosition();
  }

  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) {
    return _player(textureId!).events;
  }

  // Retrieves a [VideoPlayer] by its internal `id`.
  // It must have been created earlier from the [create] method.
  VideoPlayer _player(int id) {
    return _videoPlayers[id]!;
  }

  @override
  Widget buildView(int? textureId) {
    return HtmlElementView(viewType: 'videoPlayer-$textureId');
  }

  /// Sets the audio mode to mix with other sources (ignored)
  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) =>
      Future<void>.value();
}
