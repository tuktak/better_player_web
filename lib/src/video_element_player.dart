import 'dart:async';
import 'dart:developer';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:math';

import 'package:better_player_web/better_player_web.dart';
import 'package:better_player_web/src/video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:better_player/src/video_player/video_player_platform_interface.dart';
// import 'video_player.dart';

import '../src/shims/dart_ui.dart' as ui;

// An error code value to error name Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorName = <int, String>{
  1: 'MEDIA_ERR_ABORTED',
  2: 'MEDIA_ERR_NETWORK',
  3: 'MEDIA_ERR_DECODE',
  4: 'MEDIA_ERR_SRC_NOT_SUPPORTED',
};

// An error code value to description Map.
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/code
const Map<int, String> _kErrorValueToErrorDescription = <int, String>{
  1: 'The user canceled the fetching of the video.',
  2: 'A network error occurred while fetching the video, despite having previously been available.',
  3: 'An error occurred while trying to decode the video, despite having previously been determined to be usable.',
  4: 'The video has been found to be unsuitable (missing or in a format not supported by your browser).',
};

// The default error message, when the error is an empty string
// See: https://developer.mozilla.org/en-US/docs/Web/API/MediaError/message
const String _kDefaultErrorMessage =
    'No further diagnostic information can be determined or provided.';

abstract class VideoElementPlayer implements VideoPlayer {
  /// Create a [VideoElementPlayer] from a [html.VideoElement] instance.
  VideoElementPlayer({
    String? src,
    required String key,
    StreamController<VideoEvent>? eventController,
  })  : _src = src,
        _key = key,
        _eventController = eventController ?? StreamController<VideoEvent>();

  String? _src;
  final String _key;
  final StreamController<VideoEvent> _eventController;
  late html.VideoElement _videoElement;
  bool _isBuffering = false;
  bool _isInitialized = false;

  @protected
  bool get isInitialized => _isInitialized;

  @override
  String? get src => _src;

  StreamController<VideoEvent> get eventController => _eventController;
  html.VideoElement get videoElement => _videoElement;
  set videoElement(e) => _videoElement = e;

  /// Returns the [Stream] of [VideoEvent]s.
  @override
  Stream<VideoEvent> get events => _eventController.stream;

  /// Creates the [html.VideoElement].
  html.VideoElement createElement(int textureId);

  /// Registers the [html.VideoElement].
  @override
  void registerElement(int textureId) {
    _videoElement = createElement(textureId);
    // TODO(hterkelsen): Use initialization parameters once they are available
    ui.platformViewRegistry
        .registerViewFactory(_videoElement.id, (int viewId) => _videoElement);
  }

  bool isAlreadySetup= false;
  @protected
  void setupListeners() {
    if(isAlreadySetup) {
      return;
    }
    isAlreadySetup=true;
    videoElement.onCanPlay.listen((dynamic _) => markAsInitializedIfNeeded());
    // it's not possible to programmatically use the canplay event reliably in Safari in iOS
    if (isIPhone) {
      videoElement.onLoadedMetadata.listen((_) => markAsInitializedIfNeeded());
    }

    // videoElement.onCanPlayThrough.listen((dynamic _) {
    //   setBuffering(false);
    // });
    //
    // videoElement.onPlaying.listen((dynamic _) {
    //   setBuffering(false);
    // });

    videoElement.onWaiting.listen((dynamic _) {
      // setBuffering(true);
      _sendBufferingRangesUpdate();
    });

    // The error event fires when some form of error occurs while attempting to load or perform the media.
    videoElement.onError.listen((html.Event _) {
      setBuffering(false);
      // The Event itself (_) doesn't contain info about the actual error.
      // We need to look at the HTMLMediaElement.error.
      // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/error
      final html.MediaError error = videoElement.error!;

      eventController.addError(PlatformException(
        code: _kErrorValueToErrorName[error.code]!,
        message: error.message != '' ? error.message : _kDefaultErrorMessage,
        details: _kErrorValueToErrorDescription[error.code],
      ));
    });

    videoElement.onEnded.listen((dynamic event) {
      // setBuffering(false);
      // eventController
      //     .add(VideoEvent(eventType: VideoEventType.completed, key: _key));
      // debugPrint("ended will be paused");
      // videoElement.pause();
      eventController.add(VideoEvent(eventType: VideoEventType.pause, key: _key));
    });
    videoElement.addEventListener('webkitfullscreenchange', onFullscreenChanged);
    videoElement.addEventListener('webkitendfullscreen', onFullscreenChanged);
    videoElement.addEventListener('webkitbeginfullscreen', onFullscreenChanged);
    videoElement.addEventListener('fullscreenchange', onFullscreenChanged);
    videoElement.addEventListener('leavepictureinpicture', onFullscreenChanged);
    videoElement.addEventListener('play', (event) {
      // if(!videoPlayed) {
        videoPlayed = true;
        eventController.add(VideoEvent(
            eventType: VideoEventType.played,
            position: getPosition(),
            key: _key
        ));
      // }
      // if(html.window.document.fullscreenElement != null) {
      // }
    });
    videoElement.onSeeked.listen((event) {
      eventController.add(VideoEvent(
          eventType: VideoEventType.seeked,
          position: getPosition(),
          duration: Duration(microseconds: (videoElement.duration*1000000).round()),
          key: _key
      ));
    });

    videoElement.addEventListener('pause', (event) {
      // if(videoPlayed) {
        videoPlayed =false;
        // if(html.window.document.fullscreenElement != null) {
          eventController.add(VideoEvent(eventType: VideoEventType.paused, key: _key));
        // }
      // }
    });
    // videoElement.addEventListener('ended',(event) {
    //   videoPlayed=false;
    //   videoElement.pause();
    //   eventController.add(VideoEvent(eventType: VideoEventType.completed, key: _key));
    // });
    //
    videoElement.addEventListener('playing', (event){
      if(DateTime.now().difference(beforePlayingTime) < const Duration(milliseconds: 500)) {
        debugPrint("${DateTime.now().toString()} - ${beforePlayingTime.toString()} = ${DateTime.now().difference(beforePlayingTime)} " );
        return;
      }
      beforePlayingTime = DateTime.now();
      videoPlayed= true;
      eventController.add(VideoEvent(
          eventType: VideoEventType.playing,
          position: getPosition(),
          key: _key
      ));
    });
  }
  DateTime beforePlayingTime = DateTime.now();
  bool videoPlayed = false;
  void onFullscreenChanged(html.Event event) {
    bool ret = js.context.callMethod('checkFullscreen', [videoElement]);
    if(ret) {
      eventController.add(VideoEvent(eventType: VideoEventType.enterFullscreen, key: _key));
    } else {
      eventController.add(VideoEvent(eventType: VideoEventType.exitFullscreen, key: _key));
    }
  }

  /// Attempts to play the video.
  ///
  /// If this method is called programmatically (without user interaction), it
  /// might fail unless the video is completely muted (or it has no Audio tracks).
  ///
  /// When called from some user interaction (a tap on a button), the above
  /// limitation should disappear.
  @override
  Future<void> play() {
    // if(videoElement.duration.round() == videoElement.currentTime.round()) {
    //   videoElement.currentTime = 0;
    // }
    return videoElement.play();
    // .catchError((Object e) {
    //   // play() attempts to begin playback of the media. It returns
    //   // a Promise which can get rejected in case of failure to begin
    //   // playback for any reason, such as permission issues.
    //   // The rejection handler is called with a DomException.
    //   // See: https://developer.mozilla.org/en-US/docs/Web/API/HTMLMediaElement/play
    //   final html.DomException exception = e as html.DomException;
    //   _eventController.addError(PlatformException(
    //     code: exception.name,
    //     message: exception.message,
    //   ));
    // }, test: (Object e) => e is html.DomException);
  }

  /// Pauses the video in the current position.
  @override
  void pause() {
    videoElement.pause();
  }

  /// Controls whether the video should start again after it finishes.
  @override
  void setLooping(bool value) {
    videoElement.loop = value;
  }

  /// Sets the volume at which the media will be played.
  ///
  /// Values must fall between 0 and 1, where 0 is muted and 1 is the loudest.
  ///
  /// When volume is set to 0, the `muted` property is also applied to the
  /// [html.VideoElement]. This is required for auto-play on the web.
  @override
  void setVolume(double volume) {
    assert(volume >= 0 && volume <= 1);

    // TODO(ditman): Do we need to expose a "muted" API?
    // https://github.com/flutter/flutter/issues/60721
    videoElement.muted = !(volume > 0.0);
    videoElement.volume = volume;
  }

  /// Sets the playback `speed`.
  ///
  /// A `speed` of 1.0 is "normal speed," values lower than 1.0 make the media
  /// play slower than normal, higher values make it play faster.
  ///
  /// `speed` cannot be negative.
  ///
  /// The audio is muted when the fast forward or slow motion is outside a useful
  /// range (for example, Gecko mutes the sound outside the range 0.25 to 4.0).
  ///
  /// The pitch of the audio is corrected by default.
  @override
  void setPlaybackSpeed(double speed) {
    assert(speed > 0);

    _videoElement.playbackRate = speed;
  }

  // DateTime beforeSeek = DateTime.now();
  /// Moves the playback head to a new `position`.
  ///
  /// `position` cannot be negative.
  @override
  void seekTo(Duration position) {
    if(position.isNegative) {
      return;
    }
    var time =position.inMicroseconds.toDouble() / 1000000;
    if(time +0.5 >= videoElement.duration) {
      videoElement.currentTime=videoElement.duration;
    } else {
      videoElement.currentTime = time;
    }
  }

  DateTime _lastTime = DateTime.now();
  Duration _beforePos = Duration.zero;
  /// Returns the current playback head position as a [Duration].
  @override
  Duration getPosition() {
    if(DateTime.now().difference(_lastTime) < const Duration(milliseconds: 300)) {
      return _beforePos;
    }
    _lastTime = DateTime.now();
    // _sendBufferingRangesUpdate();
    _beforePos = Duration(microseconds: (videoElement.currentTime * 1000000).round());
    if(videoElement.duration - videoElement.currentTime < 0.9) {
      _beforePos = Duration(microseconds: (videoElement.duration * 1000000).round());
    }
    return _beforePos;
  }

  /// Disposes of the current [html.VideoElement].
  @override
  void dispose() {
    _videoElement.removeAttribute('src');
    _videoElement.load();
  }

  // Sends an [VideoEventType.initialized] [VideoEvent] with info about the wrapped video.
  @protected
  void markAsInitializedIfNeeded() {
    if (!_isInitialized) {
      _isInitialized = true;
      _sendInitialized();
    }
  }

  void _sendInitialized() {
    final Duration? duration = !_videoElement.duration.isNaN
        ? Duration(
            microseconds: (_videoElement.duration * 1000000).round(),
          )
        : null;

    final Size? size = !_videoElement.videoHeight.isNaN
        ? Size(
            _videoElement.videoWidth.toDouble(),
            _videoElement.videoHeight.toDouble(),
          )
        : null;

    _eventController.add(
      VideoEvent(
          eventType: VideoEventType.initialized,
          duration: duration,
          size: size,
          key: _key),
    );
  }

  /// Caches the current "buffering" state of the video.
  ///
  /// If the current buffering state is different from the previous one
  /// ([_isBuffering]), this dispatches a [VideoEvent].
  @protected
  @visibleForTesting
  void setBuffering(bool buffering) {
    // if (_isBuffering != buffering) {
    //   _isBuffering = buffering;
    //   _eventController.add(VideoEvent(
    //       eventType: _isBuffering
    //           ? VideoEventType.bufferingStart
    //           : VideoEventType.bufferingEnd,
    //       key: _key));
    // }
  }

  double beforeStart = 0;
  double beforeEnd = 0;
  // Broadcasts the [html.VideoElement.buffered] status through the [events] stream.
  void _sendBufferingRangesUpdate() {
    var vBuffer =  _videoElement.buffered;
    if(vBuffer.length == 1) {
      var start = vBuffer.start(0);
      var end = vBuffer.end(0);
      if(start == beforeStart && end == beforeEnd) {
        return;
      }
      beforeStart=start;
      beforeEnd=end;
      _eventController.add(VideoEvent(
          buffered: _toDurationRange(vBuffer),
          eventType: VideoEventType.bufferingUpdate,
          key: _key));
    } else  {
      _eventController.add(VideoEvent(
          buffered: _toDurationRange(vBuffer),
          eventType: VideoEventType.bufferingUpdate,
          key: _key));
    }
  }

  // Converts from [html.TimeRanges] to our own List<DurationRange>.
  List<DurationRange> _toDurationRange(html.TimeRanges buffered) {

    final List<DurationRange> durationRange = <DurationRange>[];
    for (int i = 0; i < buffered.length; i++) {
      durationRange.add(DurationRange(
        Duration(microseconds: (buffered.start(i) * 1000000).round()),
        Duration(microseconds: (buffered.end(i) * 1000000).round()),
      ));
    }
    return durationRange;
  }
}
