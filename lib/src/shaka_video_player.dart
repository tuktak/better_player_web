import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:html' as html;
import 'dart:js';
import 'package:better_player_web/src/filters.dart';
import 'package:better_player_web/src/shims/dart_ui_real.dart';
import 'package:flutter_shaka/net/net_js.dart';
import 'package:universal_io/io.dart';
import 'dart:js_interop';
import 'dart:js_util';
import 'dart:convert';
import 'package:better_player/better_player.dart';
import 'package:http/http.dart' as http;
import 'shims/dart_ui.dart' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_shaka/flutter_shaka.dart' as shaka;
// ignore: implementation_imports
import 'package:better_player/src/video_player/video_player_platform_interface.dart';
import 'utils.dart';
import 'video_element_player.dart';

const String _kMuxScriptUrl =
    'https://cdnjs.cloudflare.com/ajax/libs/mux.js/5.10.0/mux.min.js';
const String _kShakaScriptUrl = kReleaseMode
    ? 'https://cdnjs.cloudflare.com/ajax/libs/shaka-player/4.4.1/shaka-player.compiled.js'
    : 'https://cdnjs.cloudflare.com/ajax/libs/shaka-player/4.4.1/shaka-player.compiled.debug.min.js';

bool isSafari = RegExp(r'^((?!chrome|android).)*safari', caseSensitive: false)
    .hasMatch(html.window.navigator.userAgent);
// bool isSafari = true;

class ShakaVideoPlayer extends VideoElementPlayer {
  ShakaVideoPlayer({
    required String key,
    bool withCredentials = false,
    @visibleForTesting StreamController<VideoEvent>? eventController,
  })  : _withCredentials = withCredentials,
        super(eventController: eventController, key: key);

  late shaka.Player _player;

  BetterPlayerDrmConfiguration? _drmConfiguration;
  final bool _withCredentials;

  @override
  String? src;

  bool get _hasDrm =>
      _drmConfiguration?.certificateUrl != null ||
      _drmConfiguration?.licenseUrl != null;

  String get _drmServer {
    switch (_drmConfiguration?.drmType) {
      case BetterPlayerDrmType.widevine:
        return 'com.widevine.alpha';
      case BetterPlayerDrmType.playready:
        return 'com.microsoft.playready';
      case BetterPlayerDrmType.clearKey:
        return 'org.w3.clearkey';
      case BetterPlayerDrmType.fairplay:
        return 'com.apple.fps';
      default:
        return '';
    }
  }

  @override
  setDataSource(DataSource dataSource) async {
    switch (dataSource.sourceType) {
      case DataSourceType.network:
        // Do NOT modify the incoming uri, it can be a Blob, and Safari doesn't
        // like blobs that have changed.
        src = dataSource.uri ?? '';
        break;
      case DataSourceType.asset:
        String assetUrl = dataSource.asset!;
        if (dataSource.package != null && dataSource.package!.isNotEmpty) {
          assetUrl = 'packages/${dataSource.package}/$assetUrl';
        }
        assetUrl = ui.webOnlyAssetManager.getAssetUrl(assetUrl);
        src = assetUrl;
        break;
      case DataSourceType.file:
        throw UnimplementedError(
            'web implementation of video_player cannot play local files');
    }
    _drmConfiguration = BetterPlayerDrmConfiguration(
      certificateUrl: dataSource.certificateUrl,
      clearKey: dataSource.clearKey,
      drmType: dataSource.drmType,
      headers: dataSource.drmHeaders,
      licenseUrl: dataSource.licenseUrl,
    );
  }

  @override
  html.VideoElement createElement(int textureId) {
    return html.VideoElement()
      ..id = 'shakaVideoPlayer-$textureId'
      ..preload = 'auto'
      ..style.border = 'none'
      ..style.height = '100%'
      ..style.width = '100%';
  }

  @override
  Future<void> initialize() async {
    try {
      // await _loadScript();
      await _afterLoadScript();
    } on html.Event catch (ex, s) {
      eventController.addError(PlatformException(
          code: ex.type,
          message: 'Error loading Shaka Player: $_kShakaScriptUrl',
          details: ex.toString(),
          stacktrace: s.toString()));
    } catch (e, s) {
      print(e);
      print(s);
      throw ErrorDescription(e.toString());
    }
  }

  Future<dynamic> _loadScript() async {
    if (shaka.isNotLoaded) {
      await loadScript('shaka', _kShakaScriptUrl);
      await loadScript('muxjs', _kMuxScriptUrl);
    }
  }

//All FairPlay content requires setting a server certificate.
//You can either provide it directly or set a serverCertificateUri for Shaka to fetch it for you.
  Future<Uint8List?> fetchCert([String? certUrl]) async {
    final HttpClient httpClient = HttpClient();
    final request = await httpClient.getUrl(Uri.parse(certUrl!));
    // if (headers != null) {
    //   headers.forEach((name, value) => request.headers.add(name, value!));
    // }

    final response = await request.close();
    BytesBuilder data = BytesBuilder();
    await response.cast<Uint8List>().listen((content) {
      data.add(content);
    }).asFuture();

    return data.toBytes();
  }

  errorListner() {}
  // Uint8List initDataTransform(
  //     Uint8List initData, Uint8List initDataType, dynamic drmInfo) {
  //   if (initDataType != 'skd') return initData;
  //   // 'initData' is a buffer containing an 'skd://' URL as a UTF-8 string.
  //   final skdUri = shaka.StringUtils.fromBytesAutoDetect(initData);
  //   // final contentId = getMyContentId(skdUri);
  //   final cert = drmInfo.serverCertificate;
  //   return shaka.FairPlayUtils.initDataTransform(initData, skdUri, cert);
  // }

  Future<void> _afterLoadScript() async {
    videoElement
      // Set autoplay to false since most browsers won't autoplay a video unless it is muted
      ..autoplay = false
      ..controls = false;

    // Allows Safari iOS to play the video inline
    videoElement.setAttribute('playsinline', 'true');

    try {
      shaka.installPolyfills();
      // if (isSafari) shaka.installPatchedMediaKeysApple();
    } catch (e) {
      inspect(e);
    }

    if (shaka.Player.isBrowserSupported()) {
      _player = shaka.Player(videoElement);

      setupListeners();

      var f = () {
        try {
          if(_drmConfiguration?.headers != null) {
            return json.encode(_drmConfiguration?.headers).toString();
          }
        } catch(e) {
          print("$e");
        }
        return null;
      };
      context['__getDrmHeaders']= allowInterop(f);
      _player.getNetworkingEngine().clearAllRequestFilters();
      _player.getNetworkingEngine().clearAllResponseFilters();
      _player.getNetworkingEngine().registerRequestFilter(requestFilter);
      _player.getNetworkingEngine().registerResponseFilter(responseFilter);
      try {
        print('Check if video is DRM = $_hasDrm');
        if (_hasDrm) {
          if ((_drmConfiguration?.licenseUrl?.isNotEmpty ?? false) &&
              !isSafari) {
            _player.configure(
              {
                // "drm": {
                //   "servers": {_drmServer: _drmConfiguration?.licenseUrl!}
                // }
                "drm": {
                  "servers": {
                    'com.widevine.alpha': _drmConfiguration?.licenseUrl!,
                  },
                  "advanced": {
                    'com.widevine.alpha': {
                      'persistentStateRequired': true
                    }
                  }
                },
                // "streaming": {
                //   "autoLowLatencyMode": true,
                // },
              },
            );
            // _player.configure(
            //   {
            //     "drm": {
            //       "servers": {_drmServer: _drmConfiguration?.licenseUrl!}
            //     }
            //   },
            // );
          }
          if ((_drmConfiguration?.licenseUrl?.isNotEmpty ?? false) &&
              isSafari) {
            var ret = await getFairPlayCert(_drmConfiguration!.certificateUrl!);
            _player.configure({
              "drm": {
                "servers": {'com.apple.fps': _drmConfiguration?.licenseUrl},
                "advanced": {
                  'com.apple.fps': {
                    "serverCertificate": ret
                  }
                },
              },
              // "streaming": {
              //   "autoLowLatencyMode": true,
              // },
            });
          }
        }

        await _player.load(src!);
        print('Player loaded successfully');
      } on shaka.Error catch (ex) {
        _onShakaPlayerError(ex);
      } catch (e, s) {
        print(e);
        print(s);
      }
    } else {
      throw UnsupportedError(
          'web implementation of video_player does not support your browser');
    }
  }

  Future<Uint8List> getFairPlayCert(String fairplayCertUri) async{
    var client = http.Client();
    try {
      var response = await client.get(Uri.parse(fairplayCertUri));
      return base64Decode(response.body);
    } finally {
      client.close();
    }
  }

  void _onShakaPlayerError(shaka.Error error) {
    eventController.addError(PlatformException(
      code: shaka.errorCodeName(error.code),
      message: shaka.errorCategoryName(error.category),
      details: error,
    ));
    print(error.toString());
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
    final tracks = _player.getVariantTracks();
    inspect(tracks);
    // final type = tracks[0].toString();
    // final track = shaka.Track.fromMap(tracks[0] as Map<String, dynamic>);
    _player.destroy();
    super.dispose();
  }

  shaka.Track? _trackDecision(int? width, int? height, int? bitrate) {
    final tracks = _player.getVariantTracks();
    tracks.sort((a, b) => a.bandwidth!.compareTo(b.bandwidth!));
    shaka.Track? selectedTrack = tracks.isNotEmpty ? tracks[0] : null;
    // if (bitrate != null && bitrate != 0) {
    //   selectedTrack = tracks.reduce((prev, curr) =>
    //       (curr.bandwidth! - bitrate) < (prev.bandwidth! - bitrate)
    //           ? curr
    //           : prev);
    // } else
    if (width == 0 || height == 0 || bitrate == 0) {
      _player.configure('abr.enabled', true);
    } else if (height != null && height != 0) {
      selectedTrack = tracks.firstWhere((e) => e.height == height);
      _player.configure('abr.enabled', false);
    } else if (width != null && width != 0) {
      selectedTrack = tracks.firstWhere((e) => e.width == width);
      _player.configure('abr.enabled', false);
    } else if (bitrate != null && bitrate != 0) {
      selectedTrack = tracks.firstWhere((e) => e.bandwidth == bitrate);
      _player.configure('abr.enabled', false);
    }
    return selectedTrack;
  }

  @override
  Future<void> setTrackParameters(int? width, int? height, int? bitrate) async {
    shaka.Track? track = _trackDecision(width, height, bitrate);
    if (track != null) _player.selectVariantTrack(track, true, 0);
  }

  @override
  Future<DateTime?> getAbsolutePosition() async {
    return DateTime.fromMillisecondsSinceEpoch(videoElement.duration.toInt());
  }

  @override
  Future<void> setSpeed(double speed) {
    _player.trickPlay(speed);
    return Future.value();
  }

  @override
  Future<void> setAudioTrack(String? name, int? index) {
    // _player.selectAudioLanguage(name!);
    return Future.value();
  }

  @override
  Future<void> requestFullscreen() async {
    await videoElement.requestFullscreen();
    // _player.requestFullscreen();
  }

  @override
  Future<void> exitFullscreen() async {
    try{
      videoElement.exitFullscreen();
    }catch(e) {
      print(e);
    }
  }
}
