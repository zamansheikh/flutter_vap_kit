import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vap_kit/flutter_vap_kit.dart';
import 'package:flutter_vap_kit/src/vap_controller.dart';
import 'package:flutter_vap_kit/src/vap_kit.dart' as internal;

class _FakeHandle implements VapPlayerHandle {
  final List<VapSource?> plays = [];
  int stops = 0;

  @override
  Future<void> play([VapSource? source]) async => plays.add(source);

  @override
  Future<void> stop() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_vap_kit');
  final calls = <MethodCall>[];

  setUp(() async {
    calls.clear();
    await VapKit.clearCache();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'resolveAsset':
              final args = call.arguments as Map;
              if (args['asset'] == 'missing.mp4') {
                throw PlatformException(code: 'vap_kit_error');
              }
              return '/cache/${args['asset']}';
            case 'poster':
              return Uint8List.fromList([1, 2, 3]);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('VapSource', () {
    test('sources with the same target are equal', () {
      expect(
        const VapSource.asset('a.mp4'),
        equals(const VapSource.asset('a.mp4')),
      );
      expect(
        const VapSource.asset('a.mp4'),
        isNot(const VapSource.asset('a.mp4', package: 'other')),
      );
      expect(const VapSource.file('/x'), equals(const VapSource.file('/x')));
      expect(
        const VapSource.asset('a.mp4'),
        isNot(const VapSource.file('a.mp4')),
      );
    });

    test('headers do not change which network clip it is', () {
      expect(
        const VapSource.network('https://x/a.mp4', headers: {'k': 'v'}),
        equals(const VapSource.network('https://x/a.mp4')),
      );
    });
  });

  group('VapKit', () {
    test('an asset is resolved once and then reused', () async {
      const source = VapSource.asset('a.mp4');
      final first = await internal.VapKit.resolve(source);
      final second = await internal.VapKit.resolve(source);

      expect(first, '/cache/a.mp4');
      expect(second, first);
      expect(calls.where((c) => c.method == 'resolveAsset'), hasLength(1));
    });

    test('a file source needs no platform call', () async {
      expect(
        await internal.VapKit.resolve(const VapSource.file('/tmp/a.mp4')),
        '/tmp/a.mp4',
      );
      expect(calls, isEmpty);
    });

    test('a failed resolve is retried on the next attempt', () async {
      const source = VapSource.asset('missing.mp4');
      await expectLater(
        internal.VapKit.resolve(source),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(
        internal.VapKit.resolve(source),
        throwsA(isA<PlatformException>()),
      );
      expect(calls.where((c) => c.method == 'resolveAsset'), hasLength(2));
    });

    test('preload resolves the clip and renders its poster once', () async {
      const source = VapSource.asset('a.mp4');
      await VapKit.preload(source);
      await VapKit.preload(source);

      expect(calls.map((c) => c.method), ['resolveAsset', 'poster']);
    });
  });

  group('VapController', () {
    test('play before the player exists starts once it attaches', () async {
      final controller = VapController();
      const source = VapSource.asset('a.mp4');
      await controller.play(source);

      final handle = _FakeHandle();
      controller.attach(handle);
      expect(handle.plays, [source]);

      await controller.play();
      expect(handle.plays, [source, null]);
    });

    test('stop cancels a queued play', () async {
      final controller = VapController();
      await controller.play();
      await controller.stop();

      final handle = _FakeHandle();
      controller.attach(handle);
      expect(handle.plays, isEmpty);
    });

    test('notifies listeners only when the state changes', () {
      final controller = VapController();
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.update(VapPlaybackState.loading);
      controller.update(VapPlaybackState.loading);
      controller.update(VapPlaybackState.playing);

      expect(notifications, 2);
      expect(controller.isPlaying, isTrue);
    });
  });
}
