## 0.1.0

First release.

- `VapPlayer` widget with `.asset`, `.file` and `.network` constructors.
- Seamless looping (`loop: true`) and fixed repeat counts, on Android and iOS.
- The clip's first frame is shown automatically until playback starts.
- Assets are copied out of the app bundle once; network clips are downloaded
  once and reused from disk.
- `VapController` for starting, stopping and swapping clips from code.
- `VapKit.preload` to get a clip ready before it is shown.
- Touches pass through the animation to the widgets around it.
- Looping clips resume when the app returns to the foreground.
- iOS: renders on the simulator, and no longer crashes when frames are
  software-decoded.
