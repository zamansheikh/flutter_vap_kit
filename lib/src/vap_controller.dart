import 'package:flutter/foundation.dart';

import 'vap_source.dart';

/// Where a [VapPlayer] is in its playback.
enum VapPlaybackState {
  /// Nothing has been asked to play yet, or playback was stopped.
  idle,

  /// The clip is being prepared (copied, downloaded, decoder starting).
  loading,

  /// Frames are on screen.
  playing,

  /// A non-looping clip ran to its end.
  completed,

  /// The clip could not be played. See [VapController.error].
  error,
}

/// The surface a controller drives. Implemented by the player widget.
@internal
abstract interface class VapPlayerHandle {
  Future<void> play([VapSource? source]);
  Future<void> stop();
}

/// Optional remote control for a [VapPlayer].
///
/// Only needed when you want to start, stop or swap clips from code — for
/// example a gift queue that plays one clip after another. A player with
/// `autoPlay: true` needs no controller.
///
/// ```dart
/// final controller = VapController();
/// VapPlayer(controller: controller, autoPlay: false, source: ...);
/// controller.play(const VapSource.asset('assets/gift.mp4'));
/// ```
class VapController extends ChangeNotifier {
  VapPlayerHandle? _handle;
  VapSource? _queued;
  bool _playQueued = false;

  VapPlaybackState _state = VapPlaybackState.idle;
  Object? _error;

  /// Current playback state. Listen to the controller to follow it.
  VapPlaybackState get state => _state;

  /// What went wrong, when [state] is [VapPlaybackState.error].
  Object? get error => _error;

  bool get isPlaying => _state == VapPlaybackState.playing;

  /// Plays the player's clip from the start, or [source] if given.
  ///
  /// May be called before the player is on screen; it starts as soon as the
  /// player is ready.
  Future<void> play([VapSource? source]) async {
    final handle = _handle;
    if (handle == null) {
      _playQueued = true;
      _queued = source;
      return;
    }
    await handle.play(source);
  }

  /// Stops playback and clears the picture.
  Future<void> stop() async {
    _playQueued = false;
    _queued = null;
    await _handle?.stop();
  }

  @internal
  void attach(VapPlayerHandle handle) {
    _handle = handle;
    if (_playQueued) {
      final source = _queued;
      _playQueued = false;
      _queued = null;
      handle.play(source);
    }
  }

  @internal
  void detach(VapPlayerHandle handle) {
    if (identical(_handle, handle)) _handle = null;
  }

  @internal
  void update(VapPlaybackState state, [Object? error]) {
    if (_state == state && _error == error) return;
    _state = state;
    _error = error;
    notifyListeners();
  }
}
