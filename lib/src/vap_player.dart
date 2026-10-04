import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'vap_controller.dart';
import 'vap_kit.dart';
import 'vap_source.dart';

/// Plays a VAP (alpha-channel MP4) animation.
///
/// ```dart
/// // Decorative, looping:
/// VapPlayer.asset('assets/rocket.mp4', loop: true)
///
/// // A one-shot effect:
/// VapPlayer.network(url, onComplete: () => showNextGift())
/// ```
///
/// The player fills the space its parent gives it, so put it in something with
/// a size — a [SizedBox], an [AspectRatio], a [Positioned].
///
/// Until the first frame is on screen the clip's own first frame is shown as a
/// still, so the space is never empty. Touches pass straight through to the
/// widgets around it.
class VapPlayer extends StatefulWidget {
  const VapPlayer({
    super.key,
    required this.source,
    this.loop = false,
    this.repeat = 1,
    this.autoPlay = true,
    this.fit = BoxFit.contain,
    this.showPoster = true,
    this.placeholder,
    this.controller,
    this.onStart,
    this.onComplete,
    this.onError,
    this.onFrame,
  }) : assert(repeat >= 1, 'repeat must be at least 1');

  /// Plays a clip bundled with the app.
  VapPlayer.asset(
    String name, {
    Key? key,
    String? package,
    bool loop = false,
    int repeat = 1,
    bool autoPlay = true,
    BoxFit fit = BoxFit.contain,
    bool showPoster = true,
    Widget? placeholder,
    VapController? controller,
    VoidCallback? onStart,
    VoidCallback? onComplete,
    ValueChanged<Object>? onError,
    ValueChanged<int>? onFrame,
  }) : this(
         key: key,
         source: VapSource.asset(name, package: package),
         loop: loop,
         repeat: repeat,
         autoPlay: autoPlay,
         fit: fit,
         showPoster: showPoster,
         placeholder: placeholder,
         controller: controller,
         onStart: onStart,
         onComplete: onComplete,
         onError: onError,
         onFrame: onFrame,
       );

  /// Plays a clip stored on the device.
  VapPlayer.file(
    String path, {
    Key? key,
    bool loop = false,
    int repeat = 1,
    bool autoPlay = true,
    BoxFit fit = BoxFit.contain,
    bool showPoster = true,
    Widget? placeholder,
    VapController? controller,
    VoidCallback? onStart,
    VoidCallback? onComplete,
    ValueChanged<Object>? onError,
    ValueChanged<int>? onFrame,
  }) : this(
         key: key,
         source: VapSource.file(path),
         loop: loop,
         repeat: repeat,
         autoPlay: autoPlay,
         fit: fit,
         showPoster: showPoster,
         placeholder: placeholder,
         controller: controller,
         onStart: onStart,
         onComplete: onComplete,
         onError: onError,
         onFrame: onFrame,
       );

  /// Plays a clip from the network. It is downloaded once and kept on disk.
  VapPlayer.network(
    String url, {
    Key? key,
    Map<String, String>? headers,
    bool loop = false,
    int repeat = 1,
    bool autoPlay = true,
    BoxFit fit = BoxFit.contain,
    bool showPoster = true,
    Widget? placeholder,
    VapController? controller,
    VoidCallback? onStart,
    VoidCallback? onComplete,
    ValueChanged<Object>? onError,
    ValueChanged<int>? onFrame,
  }) : this(
         key: key,
         source: VapSource.network(url, headers: headers),
         loop: loop,
         repeat: repeat,
         autoPlay: autoPlay,
         fit: fit,
         showPoster: showPoster,
         placeholder: placeholder,
         controller: controller,
         onStart: onStart,
         onComplete: onComplete,
         onError: onError,
         onFrame: onFrame,
       );

  /// The clip to play. Changing it switches clips.
  final VapSource source;

  /// Repeat forever, seamlessly. When true, [repeat] is ignored and
  /// [onComplete] never fires.
  final bool loop;

  /// How many times to play when [loop] is false.
  final int repeat;

  /// Start as soon as the player is on screen. Turn off to start it yourself
  /// through a [controller].
  final bool autoPlay;

  /// How the clip is fitted into the player's box. [BoxFit.contain],
  /// [BoxFit.cover] and [BoxFit.fill] are supported; anything else behaves
  /// like `contain`.
  final BoxFit fit;

  /// Show the clip's first frame while it is getting ready.
  final bool showPoster;

  /// Shown while the clip is getting ready, in place of the first frame — or
  /// alongside [showPoster]`: false` for a custom loading look.
  final Widget? placeholder;

  /// Optional remote control. See [VapController].
  final VapController? controller;

  /// The first frame is on screen.
  final VoidCallback? onStart;

  /// A non-looping clip finished.
  final VoidCallback? onComplete;

  /// The clip could not be played.
  final ValueChanged<Object>? onError;

  /// Called with the index of each video frame as it is drawn (0-based, and
  /// starting again from 0 on every loop).
  ///
  /// Use it to keep your own widgets in step with the clip — for example a
  /// profile picture that has to follow a moving frame in the artwork. Leave
  /// it null when you do not need it; frames are then not reported at all.
  final ValueChanged<int>? onFrame;

  @override
  State<VapPlayer> createState() => _VapPlayerState();
}

class _VapPlayerState extends State<VapPlayer>
    with WidgetsBindingObserver
    implements VapPlayerHandle {
  static const String _viewType = 'flutter_vap_kit/view';

  /// The native player gives no error when a play request arrives before its
  /// surface can draw, so an unanswered request is sent again.
  static const Duration _startTimeout = Duration(milliseconds: 1500);
  static const int _maxAttempts = 4;

  MethodChannel? _channel;
  final Completer<void> _viewReady = Completer<void>();

  /// Identifies the current play request. Anything asynchronous that finishes
  /// holding an older ticket belongs to a request that was replaced.
  int _ticket = 0;

  VapPlaybackState _state = VapPlaybackState.idle;
  VapSource? _override;
  Uint8List? _poster;
  Timer? _startTimer;
  int _attempts = 0;

  /// Automatic restarts of a looping clip since it was last asked to play.
  int _recoveries = 0;
  static const int _maxRecoveries = 3;

  /// A looping clip was on screen when the app went to the background.
  bool _resumeOnForeground = false;

  VapSource get _source => _override ?? widget.source;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller?.attach(this);
    if (widget.autoPlay) {
      play();
    } else {
      _loadPoster();
    }
  }

  /// Gets the first frame for a player that is waiting to be started, so it
  /// shows the clip rather than an empty box.
  Future<void> _loadPoster() async {
    if (!widget.showPoster) return;
    final ticket = _ticket;
    try {
      final path = await VapKit.resolve(_source);
      final bytes = await VapKit.posterFor(path);
      if (!mounted || ticket != _ticket || bytes == null) return;
      setState(() => _poster = bytes);
    } catch (_) {
      // The poster is optional; a real failure surfaces when play() runs.
    }
  }

  @override
  void didUpdateWidget(VapPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(this);
      widget.controller?.attach(this);
      widget.controller?.update(_state);
    }
    final changed =
        oldWidget.source != widget.source ||
        oldWidget.loop != widget.loop ||
        oldWidget.repeat != widget.repeat ||
        oldWidget.fit != widget.fit;
    if (!changed) return;

    if (oldWidget.source != widget.source) {
      _override = null;
      _poster = null;
    }
    final wasActive =
        _state == VapPlaybackState.playing ||
        _state == VapPlaybackState.loading;
    if (widget.autoPlay || wasActive) {
      play();
    } else {
      _loadPoster();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The decoder loses its surface in the background and does not pick a
    // looping clip back up by itself.
    if (state == AppLifecycleState.paused) {
      _resumeOnForeground =
          widget.loop &&
          (_state == VapPlaybackState.playing ||
              _state == VapPlaybackState.loading);
    } else if (state == AppLifecycleState.resumed && _resumeOnForeground) {
      _resumeOnForeground = false;
      play(_override);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller?.detach(this);
    _ticket++;
    _startTimer?.cancel();
    final channel = _channel;
    if (channel != null) {
      channel.setMethodCallHandler(null);
      // The native view may already be gone; that is not an error here.
      channel.invokeMethod<void>('stop').catchError((Object _) {});
    }
    super.dispose();
  }

  // ── Playback ────────────────────────────────────────────────────────────

  @override
  Future<void> play([VapSource? source]) {
    _recoveries = 0;
    return _restart(source);
  }

  Future<void> _restart([VapSource? source]) async {
    if (!mounted) return;
    if (source != null && source != _source) {
      _override = source;
      _poster = null;
    }
    final ticket = ++_ticket;
    _attempts = 0;
    _startTimer?.cancel();
    _setState(VapPlaybackState.loading);

    final clip = _source;
    try {
      final path = await VapKit.resolve(clip);
      if (!mounted || ticket != _ticket) return;

      if (widget.showPoster && _poster == null) {
        // Not awaited: the poster is a nicety and must not delay playback.
        VapKit.posterFor(path).then((bytes) {
          if (!mounted || ticket != _ticket || bytes == null) return;
          setState(() => _poster = bytes);
        });
      }

      await _viewReady.future;
      if (!mounted || ticket != _ticket) return;
      await _send(path, ticket);
    } catch (error) {
      if (!mounted || ticket != _ticket) return;
      _fail(error);
    }
  }

  Future<void> _send(String path, int ticket) async {
    _attempts++;
    await _channel!.invokeMethod<void>('play', {
      'path': path,
      'loop': widget.loop ? -1 : widget.repeat,
      'fit': switch (widget.fit) {
        BoxFit.cover => 'cover',
        BoxFit.fill => 'fill',
        _ => 'contain',
      },
      'ticket': ticket,
      'frames': widget.onFrame != null,
    });
    if (!mounted || ticket != _ticket) return;

    _startTimer?.cancel();
    _startTimer = Timer(_startTimeout, () {
      if (!mounted || ticket != _ticket) return;
      if (_state != VapPlaybackState.loading) return;
      if (_attempts < _maxAttempts) {
        _send(path, ticket).catchError(_onSendError);
      } else {
        _fail(TimeoutException('The clip did not start', _startTimeout));
      }
    });
  }

  void _onSendError(Object error) {
    if (mounted) _fail(error);
  }

  @override
  Future<void> stop() async {
    _ticket++;
    _startTimer?.cancel();
    _resumeOnForeground = false;
    _setState(VapPlaybackState.idle);
    try {
      await _channel?.invokeMethod<void>('stop');
    } catch (_) {
      // Nothing to stop.
    }
  }

  Future<void> _onNativeEvent(MethodCall call) async {
    final args = (call.arguments as Map?) ?? const {};
    if (args['ticket'] != _ticket || !mounted) return;
    switch (call.method) {
      case 'onStart':
        _startTimer?.cancel();
        _setState(VapPlaybackState.playing);
        widget.onStart?.call();
      case 'onFrame':
        widget.onFrame?.call((args['frame'] as num).toInt());
      case 'onComplete':
        if (widget.loop) {
          // A looping clip is not supposed to end. If the native player
          // stops anyway, start it again rather than leave an empty box.
          _recoverLoop();
          return;
        }
        _setState(VapPlaybackState.completed);
        widget.onComplete?.call();
      case 'onError':
        final error = PlatformException(
          code: '${args['code']}',
          message: args['message'] as String?,
        );
        // A decoder can be lost while running (the system reclaims it, the
        // surface goes away). A looping clip gets a few chances to come back
        // before the error is reported.
        if (widget.loop &&
            _state == VapPlaybackState.playing &&
            _recoveries < _maxRecoveries) {
          _recoverLoop();
          return;
        }
        _fail(error);
    }
  }

  void _recoverLoop() {
    _recoveries++;
    final ticket = _ticket;
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      if (mounted && ticket == _ticket) _restart();
    });
  }

  void _fail(Object error) {
    _startTimer?.cancel();
    _setState(VapPlaybackState.error, error);
    widget.onError?.call(error);
  }

  void _setState(VapPlaybackState state, [Object? error]) {
    widget.controller?.update(state, error);
    if (_state == state) return;
    setState(() => _state = state);
  }

  void _onPlatformViewCreated(int id) {
    final channel = MethodChannel('flutter_vap_kit/view_$id');
    channel.setMethodCallHandler(_onNativeEvent);
    _channel = channel;
    if (!_viewReady.isCompleted) _viewReady.complete();
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final Widget view;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        view = AndroidView(
          viewType: _viewType,
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.iOS:
        view = UiKitView(
          viewType: _viewType,
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      default:
        view = const SizedBox.shrink();
    }

    // Shown until frames are actually on screen.
    final waiting =
        _state == VapPlaybackState.idle || _state == VapPlaybackState.loading;
    Widget? cover;
    if (waiting) {
      if (widget.showPoster && _poster != null) {
        cover = Image.memory(
          _poster!,
          fit: switch (widget.fit) {
            BoxFit.cover => BoxFit.cover,
            BoxFit.fill => BoxFit.fill,
            _ => BoxFit.contain,
          },
          gaplessPlayback: true,
        );
      } else {
        cover = widget.placeholder;
      }
    }

    // The animation is decoration: let touches reach whatever is around it.
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Keyed, so the cover appearing and disappearing next to it can
          // never make Flutter rebuild the native view.
          KeyedSubtree(key: const ValueKey('vap-view'), child: view),
          if (cover != null)
            KeyedSubtree(key: const ValueKey('vap-cover'), child: cover),
        ],
      ),
    );
  }
}
