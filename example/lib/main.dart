import 'package:flutter/material.dart';
import 'package:flutter_vap_kit/flutter_vap_kit.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_vap_kit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const ShowcasePage(),
    );
  }
}

/// A small "live room" scene built from three players:
///
///  * a looping banner with ordinary Flutter widgets laid over it,
///  * a looping rocket on a stage,
///  * a one-shot effect fired from a button.
class ShowcasePage extends StatefulWidget {
  const ShowcasePage({super.key});

  @override
  State<ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<ShowcasePage> {
  final VapController _gift = VapController();

  @override
  void initState() {
    super.initState();
    // Optional: get the one-shot clip ready before it is first needed.
    VapKit.preload(const VapSource.asset('assets/gift.mp4'));
  }

  @override
  void dispose() {
    _gift.dispose();
    super.dispose();
  }

  void _joinRoom() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
          content: Text('The button sits on top of the animation — and works.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1030), Color(0xFF1B0F3D), Color(0xFF07060F)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              RocketBanner(onGo: _joinRoom),
              // The whole integration for a looping animation:
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const _StageGlow(),
                    VapPlayer.asset('assets/rocket.mp4', loop: true),
                    // The one-shot effect plays over the stage.
                    VapPlayer.asset(
                      'assets/gift.mp4',
                      controller: _gift,
                      autoPlay: false,
                      showPoster: false,
                    ),
                  ],
                ),
              ),
              ListenableBuilder(
                listenable: _gift,
                builder: (context, _) => _SendButton(
                  busy:
                      _gift.state == VapPlaybackState.loading ||
                      _gift.isPlaying,
                  onPressed: _gift.play,
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

/// The banner artwork is a looping VAP clip; the text, avatar slot and button
/// are plain Flutter widgets placed as fractions of the artwork (750 x 176),
/// so they sit in the same spot at any width.
class RocketBanner extends StatelessWidget {
  const RocketBanner({super.key, required this.onGo});

  final VoidCallback onGo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: AspectRatio(
        aspectRatio: 750 / 176,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;
            final h = constraints.maxHeight;
            final unit = w / 351;
            final centreY = h * 0.534;
            final band = h * 0.56;
            final slot = w * 0.066;

            return Stack(
              children: [
                Positioned.fill(
                  child: VapPlayer.asset(
                    'assets/banner.mp4',
                    loop: true,
                    fit: BoxFit.fill,
                  ),
                ),
                Positioned(
                  left: w * 0.065,
                  width: w * 0.41,
                  top: centreY - band / 2,
                  height: band,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'LV.6 Rocket Launched',
                          maxLines: 1,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12.5 * unit,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                            shadows: const [
                              Shadow(color: Colors.black45, blurRadius: 3),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 2 * unit),
                      Text(
                        'Starlight Lounge takes off',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 10 * unit,
                          fontWeight: FontWeight.w600,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: w * 0.533 - slot / 2,
                  top: centreY - slot / 2,
                  width: slot,
                  height: slot,
                  child: Icon(
                    Icons.rocket_launch,
                    size: slot * 0.62,
                    color: Colors.amberAccent,
                  ),
                ),
                Positioned(
                  left: w * 0.805,
                  width: w * 0.14,
                  top: centreY - 10 * unit,
                  height: 20 * unit,
                  child: GestureDetector(
                    onTap: onGo,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFFE27A), Color(0xFFFFB300)],
                        ),
                        borderRadius: BorderRadius.circular(10 * unit),
                        border: Border.all(color: Colors.white),
                      ),
                      child: Center(
                        child: Text(
                          'Go',
                          style: TextStyle(
                            color: const Color(0xFF6B3A00),
                            fontSize: 11.5 * unit,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StageGlow extends StatelessWidget {
  const _StageGlow();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          radius: 0.62,
          colors: [Color(0x553B6BFF), Color(0x00000000)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: AnimatedOpacity(
        opacity: busy ? 0.55 : 1,
        duration: const Duration(milliseconds: 150),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 13),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5E9C), Color(0xFF8B5CF6)],
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x668B5CF6),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.card_giftcard, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                busy ? 'Sending…' : 'Send gift',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
