import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util';

import 'package:better_player/better_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:better_player/src/video_player/video_player_platform_interface.dart';
import 'shaka.dart' as shaka;
import 'utils.dart';
import 'video_element_player.dart';

const String _kMuxScriptUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/mux.js/5.10.0/mux.min.js';
const String _kShakaScriptUrl = kReleaseMode
    ? 'https://cdnjs.cloudflare.com/ajax/libs/shaka-player/4.1.0/shaka-player.compiled.min.js'
    : 'https://cdnjs.cloudflare.com/ajax/libs/shaka-player/4.1.0/shaka-player.compiled.debug.js';

class ShakaVideoPlayer extends VideoElementPlayer {
  ShakaVideoPlayer({
    required String src,
    required String key,
    BetterPlayerDrmConfiguration? drmConfiguration,
    bool withCredentials = false,
    @visibleForTesting StreamController<VideoEvent>? eventController,
  })  : _drmConfiguration = drmConfiguration,
        _withCredentials = withCredentials,
        super(src: src, eventController: eventController, key: key);

  late shaka.Player _player;

  final BetterPlayerDrmConfiguration? _drmConfiguration;
  final bool _withCredentials;

  bool get _hasDrm => _drmConfiguration != null;

  String get _drmServer {
    if (_drmConfiguration?.drmType == BetterPlayerDrmType.widevine) {
      return 'com.widevine.alpha';
    }

    return '';
  }

  @override
  html.VideoElement createElement(int textureId) {
    return html.VideoElement()
      ..id = 'videoPlayer-$textureId'
      ..style.border = 'none'
      ..style.height = '100%'
      ..style.width = '100%';
  }

  @override
  Future<void> initialize() async {
    try {
      await _loadScript();
      await _afterLoadScript();
    } on html.Event catch (ex) {
      eventController.addError(PlatformException(
        code: ex.type,
        message: 'Error loading Shaka Player: $_kShakaScriptUrl',
      ));
    }
  }

  Future<dynamic> _loadScript() async {
    if (shaka.isNotLoaded) {
      await loadScript('muxjs', _kMuxScriptUrl);
      await loadScript('shaka', _kShakaScriptUrl);
    }
  }

  Future<void> _afterLoadScript() async {
    videoElement
      // Set autoplay to false since most browsers won't autoplay a video unless it is muted
      ..autoplay = false
      ..controls = false;

    // Allows Safari iOS to play the video inline
    videoElement.setAttribute('playsinline', 'true');

    shaka.installPolyfills();

    if (shaka.Player.isBrowserSupported()) {
      _player = shaka.Player(videoElement);

      setupListeners();

      try {
        if (_hasDrm) {
          _player.configure(
            jsify({
              "drm": {
                "servers": {_drmServer: _drmConfiguration?.licenseUrl!}
              }
            }),
          );
        }

        _player
            .getNetworkingEngine()
            .registerRequestFilter(allowInterop((type, request) {
          request.allowCrossSiteCredentials = _withCredentials;

          if (type == shaka.RequestType.license &&
              _hasDrm &&
              _drmConfiguration?.headers?.isNotEmpty == true) {
            request.headers = jsify(_drmConfiguration?.headers!);
          }
        }));

        await promiseToFuture(_player.load(src));
      } on shaka.Error catch (ex) {
        _onShakaPlayerError(ex);
      }
    } else {
      throw UnsupportedError(
          'web implementation of video_player does not support your browser');
    }
  }

  void _onShakaPlayerError(shaka.Error error) {
    eventController.addError(PlatformException(
      code: shaka.errorCodeName(error.code),
      message: shaka.errorCategoryName(error.category),
      details: error,
    ));
  }

  @override
  @protected
  void setupListeners() {
    super.setupListeners();

    // Listen for error events.
    _player.addEventListener(
      'error',
      allowInterop((event) => _onShakaPlayerError(event.detail)),
    );
  }

  @override
  void dispose() {
    _player.destroy();
    super.dispose();
  }
}
