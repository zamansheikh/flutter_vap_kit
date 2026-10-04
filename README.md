<h1 align="center">flutter_vap_kit</h1>

<p align="center">
  Transparent video animations for Flutter — gift effects, entry animations,<br>
  banners and badges — in <b>one line</b>.
</p>

<p align="center">
  <a href="https://pub.dev/packages/flutter_vap_kit"><img src="https://img.shields.io/pub/v/flutter_vap_kit.svg" alt="pub version"></a>
  <a href="https://pub.dev/packages/flutter_vap_kit/score"><img src="https://img.shields.io/pub/points/flutter_vap_kit" alt="pub points"></a>
  <img src="https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue" alt="platforms">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSD--3--Clause-green" alt="BSD-3-Clause license"></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/zamansheikh/flutter_vap_kit/main/doc/preview.gif" width="320" alt="An animated banner with a Go button on top, and a looping rocket">
</p>

```dart
VapPlayer.asset('assets/rocket.mp4', loop: true)
```

That is the whole integration. No controller to create, no waiting for a native
view, no restarting the clip yourself to make it loop.

---

## What is VAP?

[VAP](https://github.com/Tencent/vap) is Tencent's format for video with a real
alpha channel: an ordinary H.264 MP4 that carries its own transparency. It is
what live-streaming and social apps use for full-screen gift effects, because it
is far smaller than a PNG sequence, far richer than Lottie or SVGA can be, and
hardware-decoded.

`flutter_vap_kit` plays those files on Android and iOS.

## Why this package

Playing a VAP file is easy. Playing it *well* inside a Flutter app is where the
time goes. This package handles the parts you would otherwise write yourself:

| You get | What it means |
|---|---|
| **Seamless looping** | Loops run inside the native player on both platforms. No blink between runs. |
| **Never an empty box** | The clip's own first frame is shown, with its transparency, until playback starts. |
| **No dropped starts** | Play requests wait for the native view and are retried if it does not answer. |
| **Assets copied once** | Bundled clips are extracted one time, not on every play. |
| **Network clips cached** | Downloaded once, then played from disk. |
| **Touches pass through** | Buttons under or over an animation keep working. |
| **Survives backgrounding** | Looping clips resume when the app comes back, and restart themselves if the decoder is lost. |
| **Works on the iOS simulator** | Most VAP plugins show nothing there; this one renders. |
| **Declarative** | Change `source`, `loop` or `fit` and the player follows. |

## Install

```yaml
dependencies:
  flutter_vap_kit: ^0.1.1
```

| | Minimum |
|---|---|
| Android | `minSdk 24` |
| iOS | 12.0 — Swift Package Manager or CocoaPods |

No permissions, no manifest or Info.plist changes.

## Quick start

### A looping animation

```dart
SizedBox(
  height: 260,
  child: VapPlayer.asset('assets/rocket.mp4', loop: true),
)
```

The player fills the box its parent gives it, so give it a size: a `SizedBox`,
an `AspectRatio`, a `Positioned`.

### A one-shot effect

```dart
VapPlayer.network(
  'https://example.com/gift.mp4',
  onComplete: () => showNextGift(),
)
```

### An animated banner with a button on top

```dart
Stack(
  alignment: Alignment.centerRight,
  children: [
    AspectRatio(
      aspectRatio: 750 / 176,
      child: VapPlayer.asset('assets/banner.mp4', loop: true, fit: BoxFit.fill),
    ),
    FilledButton(onPressed: join, child: const Text('Go')),
  ],
)
```

### A gift queue, driven from code

```dart
final controller = VapController();

VapPlayer.asset(
  'assets/gift.mp4',
  controller: controller,
  autoPlay: false,
  onComplete: playNextGift,
);

controller.play();                                        // the player's clip
controller.play(const VapSource.network(nextGiftUrl));    // a different clip
controller.stop();
```

`controller.state` is `idle`, `loading`, `playing`, `completed` or `error`. The
controller is a `Listenable`, so it works with `ListenableBuilder`.

### Warm clips up before they are needed

```dart
await VapKit.preload(const VapSource.network('https://example.com/gift.mp4'));
```

Copies or downloads the clip and renders its first frame, so the player that
shows it later starts at once. Good for the gifts on a gift panel.

## API at a glance

### `VapPlayer`

| Parameter | Default | |
|---|---|---|
| `source` | — | `VapSource.asset`, `.file` or `.network`. Or use the `VapPlayer.asset` / `.file` / `.network` constructors. |
| `loop` | `false` | Repeat forever, seamlessly. |
| `repeat` | `1` | Times to play when `loop` is false. |
| `autoPlay` | `true` | Start as soon as the player is on screen. |
| `fit` | `BoxFit.contain` | `contain`, `cover` or `fill`. |
| `showPoster` | `true` | Show the first frame while the clip gets ready. |
| `placeholder` | — | Your own widget for that moment instead. |
| `controller` | — | A `VapController`, when you need one. |
| `onStart` / `onComplete` / `onError` | — | Playback callbacks. |

### `VapKit`

| | |
|---|---|
| `VapKit.preload(source)` | Get a clip ready ahead of time. |
| `VapKit.clearCache()` | Forget cached clips and delete downloads. |

## Making VAP files

Export your animation as a PNG sequence with transparency, then convert it with
Tencent's [VapTool](https://github.com/Tencent/vap/tree/master/tool). The result
is a single `.mp4` you drop into `assets/`.

## Good to know

- **One player per animation.** Each `VapPlayer` owns a hardware video decoder.
  A handful on screen is fine; a long scrolling list of them is not — show a
  still there and play on tap.
- **Fusion animations** (text or images merged into a clip at play time) are
  not exposed yet.
- **Do not combine with other VAP plugins.** This package ships its own copy of
  the iOS player, so adding another plugin that brings `QGVAPlayer` produces
  duplicate classes.

## Example

The [example app](example) is the scene in the preview above: an animated
banner with text and a working button laid over it, a looping rocket, and a
one-shot effect fired from a button.

```sh
cd example
flutter run
```

## Credits and license

BSD-3-Clause — see [LICENSE](LICENSE).

Built on [Tencent VAP](https://github.com/Tencent/vap), which is MIT-licensed
and stays so. The Android side
uses Tencent's published library; the iOS side includes a copy of Tencent's
player source with two fixes — a crash in decoder set-up, and rendering when
frames are software-decoded — see `ios/flutter_vap_kit/Sources/flutter_vap_kit_player/LICENSE.txt`.
