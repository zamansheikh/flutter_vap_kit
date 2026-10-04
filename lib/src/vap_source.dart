import 'package:flutter/foundation.dart';

/// Where a VAP clip comes from.
@immutable
sealed class VapSource {
  const VapSource();

  /// A clip bundled with the app, e.g. `assets/gift.mp4`. Pass [package] when
  /// the asset ships inside another package.
  const factory VapSource.asset(String name, {String? package}) =
      VapAssetSource;

  /// A clip already on the device.
  const factory VapSource.file(String path) = VapFileSource;

  /// A clip on the network. It is downloaded once and reused from disk.
  const factory VapSource.network(String url, {Map<String, String>? headers}) =
      VapNetworkSource;
}

final class VapAssetSource extends VapSource {
  const VapAssetSource(this.name, {this.package});

  final String name;
  final String? package;

  @override
  bool operator ==(Object other) =>
      other is VapAssetSource && other.name == name && other.package == package;

  @override
  int get hashCode => Object.hash(name, package);

  @override
  String toString() => 'VapSource.asset($name)';
}

final class VapFileSource extends VapSource {
  const VapFileSource(this.path);

  final String path;

  @override
  bool operator ==(Object other) =>
      other is VapFileSource && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'VapSource.file($path)';
}

final class VapNetworkSource extends VapSource {
  const VapNetworkSource(this.url, {this.headers});

  final String url;
  final Map<String, String>? headers;

  // Headers are credentials, not identity: two requests for the same URL are
  // the same clip.
  @override
  bool operator ==(Object other) =>
      other is VapNetworkSource && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'VapSource.network($url)';
}
