import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'vap_source.dart';

/// Package-level helpers: warming clips up before they are shown, and
/// clearing what the package has stored.
abstract final class VapKit {
  static const MethodChannel _channel = MethodChannel('flutter_vap_kit');

  static final Map<VapSource, Future<String>> _paths = {};
  static final Map<String, Future<Uint8List?>> _posters = {};

  /// Gets [source] ready to play: copies an asset out of the bundle or
  /// downloads a network clip, and renders its first frame. A [VapPlayer]
  /// shown afterwards starts without that delay.
  ///
  /// Safe to call more than once; the work is only done the first time.
  static Future<void> preload(VapSource source, {bool poster = true}) async {
    final path = await resolve(source);
    if (poster) await posterFor(path);
  }

  /// Local file path for [source].
  @internal
  static Future<String> resolve(VapSource source) {
    final cached = _paths[source];
    if (cached != null) return cached;
    final future = _resolve(source);
    _paths[source] = future;
    // A failed attempt must not be remembered — the next play should retry.
    future.then<void>(
      (_) {},
      onError: (Object _) {
        _paths.remove(source);
      },
    );
    return future;
  }

  static Future<String> _resolve(VapSource source) async {
    switch (source) {
      case VapFileSource(:final path):
        return path;
      case VapAssetSource(:final name, :final package):
        final path = await _channel.invokeMethod<String>('resolveAsset', {
          'asset': name,
          'package': package,
        });
        if (path == null) throw StateError('Could not resolve asset $name');
        return path;
      case VapNetworkSource(:final url, :final headers):
        return _download(url, headers);
    }
  }

  /// First frame of the clip at [path] as a PNG, or null when the file has no
  /// VAP layout information.
  @internal
  static Future<Uint8List?> posterFor(String path) {
    return _posters.putIfAbsent(path, () async {
      try {
        return await _channel.invokeMethod<Uint8List>('poster', {'path': path});
      } catch (e) {
        debugPrint('flutter_vap_kit: poster failed for $path: $e');
        return null;
      }
    });
  }

  static Directory get _downloadDir =>
      Directory('${Directory.systemTemp.path}/flutter_vap_kit');

  static Future<String> _download(
    String url,
    Map<String, String>? headers,
  ) async {
    final dir = _downloadDir;
    await dir.create(recursive: true);
    final file = File('${dir.path}/${_fileNameFor(url)}');
    if (await file.exists() && await file.length() > 0) return file.path;

    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      headers?.forEach(request.headers.set);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
      }
      // Write beside the target and rename, so a half-finished download is
      // never mistaken for a complete clip.
      final partial = File('${file.path}.part');
      await response.pipe(partial.openWrite());
      await partial.rename(file.path);
      return file.path;
    } finally {
      client.close();
    }
  }

  /// Stable, file-system-safe name for [url] (64-bit FNV-1a).
  static String _fileNameFor(String url) {
    var hash = 0xcbf29ce484222325;
    for (final unit in url.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x100000001b3) & 0x7fffffffffffffff;
    }
    return '${hash.toRadixString(16)}.mp4';
  }

  /// Forgets everything held in memory and deletes downloaded clips.
  static Future<void> clearCache() async {
    _paths.clear();
    _posters.clear();
    final dir = _downloadDir;
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
