import 'package:flutter/material.dart';
import 'package:flutter_vap_kit/flutter_vap_kit.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_vap_kit',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final VapController _gift = VapController();
  int _taps = 0;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_vap_kit')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Label('Looping — one line'),
          // The whole integration for a looping animation:
          SizedBox(
            height: 260,
            child: VapPlayer.asset('assets/rocket.mp4', loop: true),
          ),

          const _Label('Looping banner, touches pass through'),
          Stack(
            alignment: Alignment.centerRight,
            children: [
              AspectRatio(
                aspectRatio: 750 / 176,
                child: VapPlayer.asset(
                  'assets/banner.mp4',
                  loop: true,
                  fit: BoxFit.fill,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: FilledButton(
                  onPressed: () => setState(() => _taps++),
                  child: Text('Tapped $_taps'),
                ),
              ),
            ],
          ),

          const _Label('One-shot, driven by a controller'),
          SizedBox(
            height: 260,
            child: VapPlayer.asset(
              'assets/gift.mp4',
              controller: _gift,
              autoPlay: false,
              onComplete: () => debugPrint('reward finished'),
            ),
          ),
          ListenableBuilder(
            listenable: _gift,
            builder: (context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton(onPressed: _gift.play, child: const Text('Play')),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _gift.stop,
                  child: const Text('Stop'),
                ),
                const SizedBox(width: 12),
                Text(_gift.state.name),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}
