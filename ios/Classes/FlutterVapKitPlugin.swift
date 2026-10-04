import AVFoundation
import Flutter
import UIKit

/// Registers the VAP platform view and a small utility channel:
///
///  - `resolveAsset` turns a Flutter asset key into a file path the player
///    can open.
///  - `poster` renders a clip's first frame, with its alpha applied, as a PNG.
public class FlutterVapKitPlugin: NSObject, FlutterPlugin {
  private let registrar: FlutterPluginRegistrar
  private let work = DispatchQueue(label: "flutter_vap_kit.work", qos: .userInitiated)

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_vap_kit", binaryMessenger: registrar.messenger())
    let instance = FlutterVapKitPlugin(registrar: registrar)
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(
      VapKitViewFactory(messenger: registrar.messenger()),
      withId: "flutter_vap_kit/view")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "resolveAsset":
      guard let asset = args["asset"] as? String else {
        result(FlutterError(code: "bad_args", message: "asset is required", details: nil))
        return
      }
      let key: String
      if let package = args["package"] as? String {
        key = registrar.lookupKey(forAsset: asset, fromPackage: package)
      } else {
        key = registrar.lookupKey(forAsset: asset)
      }
      if let path = Bundle.main.path(forResource: key, ofType: nil) {
        result(path)
      } else {
        result(FlutterError(code: "vap_kit_error", message: "Asset not found: \(asset)", details: nil))
      }
    case "poster":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path is required", details: nil))
        return
      }
      work.async {
        let png = VapPoster.render(path: path)
        DispatchQueue.main.async {
          result(png.map { FlutterStandardTypedData(bytes: $0) })
        }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

private class VapKitViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    VapKitView(frame: frame, viewId: viewId, messenger: messenger)
  }
}

/// A plain view that reports every layout pass. Flutter creates platform views
/// with an empty frame and sizes them a moment later; the player has to wait
/// for that, because it sizes its drawing surface when playback starts.
private class VapContainerView: UIView {
  var onLayout: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    onLayout?()
  }
}

/// One VAP player surface.
///
/// Channel `flutter_vap_kit/view_<id>`:
///   play { path, loop, fit, ticket }  — loop < 0 means "forever"
///   stop
/// and back to Dart: onStart, onComplete, onError { code, message }.
///
/// Every play request carries a ticket; callbacks from a clip that has since
/// been replaced or stopped are dropped, so Dart never sees a stale event.
private class VapKitView: NSObject, FlutterPlatformView, VAPWrapViewDelegate {
  private struct Request {
    let path: String
    let loop: Int
    let fit: String
    let ticket: Int
    /// The clip's own size, from its `vapc` box. Nil when it has none.
    let clipSize: CGSize?
  }

  private let container: VapContainerView
  private let channel: FlutterMethodChannel
  private var player: QGVAPWrapView?

  /// The clip on screen, or waiting for the view to get a size.
  private var request: Request?
  private var waitingForLayout = false

  /// Ticket of the clip currently playing; 0 when nothing is.
  private var ticket = 0
  private var loopsForever = false

  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = VapContainerView(frame: frame)
    container.backgroundColor = .clear
    // Taps belong to the Flutter widgets around the animation.
    container.isUserInteractionEnabled = false
    channel = FlutterMethodChannel(
      name: "flutter_vap_kit/view_\(viewId)", binaryMessenger: messenger)
    super.init()
    container.onLayout = { [weak self] in self?.containerDidLayout() }
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    player?.stopHWDMP4()
  }

  func view() -> UIView { container }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "play":
      guard let path = args["path"] as? String else {
        result(FlutterError(code: "bad_args", message: "path is required", details: nil))
        return
      }
      play(
        path: path,
        loop: args["loop"] as? Int ?? 1,
        fit: args["fit"] as? String ?? "contain",
        id: args["ticket"] as? Int ?? 0)
      result(nil)
    case "stop":
      ticket = 0
      request = nil
      waitingForLayout = false
      player?.stopHWDMP4()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func play(path: String, loop: Int, fit: String, id: Int) {
    guard FileManager.default.fileExists(atPath: path) else {
      emitError(id, code: -1, message: "File does not exist: \(path)")
      return
    }

    // Silence the outgoing clip before stopping it.
    ticket = 0
    player?.stopHWDMP4()

    request = Request(
      path: path, loop: loop, fit: fit, ticket: id, clipSize: VapPoster.clipSize(path: path))

    if container.bounds.isEmpty {
      // Not laid out yet — containerDidLayout() starts it.
      waitingForLayout = true
    } else {
      start()
    }
  }

  private func containerDidLayout() {
    guard !container.bounds.isEmpty, let request = request else { return }
    if waitingForLayout {
      start()
    } else {
      // The box changed size (rotation, a resizing parent): keep the fit.
      player?.frame = fittedFrame(for: request)
    }
  }

  private func start() {
    guard let request = request else { return }
    waitingForLayout = false

    let view = player ?? makePlayer()
    // The player view itself is given the fitted rectangle and fills it, which
    // keeps the fit correct when the box is resized later.
    view.contentMode = .scaleToFill
    view.frame = fittedFrame(for: request)
    container.clipsToBounds = request.fit == "cover"

    ticket = request.ticket
    loopsForever = request.loop < 0
    // QGVAPlayer: repeatCount is the number of EXTRA plays; -1 loops forever.
    view.playHWDMP4(
      request.path, repeatCount: request.loop < 0 ? -1 : max(request.loop - 1, 0),
      delegate: self)
    for subview in view.subviews {
      subview.frame = view.bounds
      subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }
  }

  /// Where the clip goes inside the container for the requested fit.
  private func fittedFrame(for request: Request) -> CGRect {
    let box = container.bounds
    guard request.fit != "fill", let clip = request.clipSize,
      clip.width > 0, clip.height > 0, box.width > 0, box.height > 0
    else { return box }

    let scale =
      request.fit == "cover"
      ? max(box.width / clip.width, box.height / clip.height)
      : min(box.width / clip.width, box.height / clip.height)
    let size = CGSize(width: clip.width * scale, height: clip.height * scale)
    return CGRect(
      x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
      width: size.width, height: size.height)
  }

  private func makePlayer() -> QGVAPWrapView {
    let view = QGVAPWrapView(frame: container.bounds)
    view.backgroundColor = .clear
    view.isUserInteractionEnabled = false
    container.addSubview(view)
    player = view
    return view
  }

  // MARK: VAPWrapViewDelegate (may arrive off the main thread)

  func vapWrap_viewDidStartPlayMP4(_ container: UIView) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.ticket != 0 else { return }
      self.channel.invokeMethod("onStart", arguments: ["ticket": self.ticket])
    }
  }

  func vapWrap_viewDidFinishPlayMP4(_ totalFrameCount: Int, view container: UIView) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.ticket != 0, !self.loopsForever else { return }
      let id = self.ticket
      self.ticket = 0
      self.request = nil
      self.channel.invokeMethod("onComplete", arguments: ["ticket": id])
    }
  }

  func vapWrap_viewDidFailPlayMP4(_ error: Error) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.ticket != 0 else { return }
      self.emitError(self.ticket, code: -1, message: error.localizedDescription)
    }
  }

  private func emitError(_ id: Int, code: Int, message: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      if id == self.ticket { self.ticket = 0 }
      self.channel.invokeMethod(
        "onError", arguments: ["ticket": id, "code": code, "message": message])
    }
  }
}

/// Renders the first frame of a VAP clip as a transparent PNG.
///
/// A VAP file is an ordinary MP4 whose picture holds the colour image and its
/// alpha mask side by side; a JSON `vapc` box describes where each one sits.
enum VapPoster {
  static func render(path: String) -> Data? {
    guard let info = readInfo(path: path),
      let width = info["w"] as? Int, let height = info["h"] as? Int,
      let rgb = info["rgbFrame"] as? [Int], rgb.count >= 4,
      let alpha = info["aFrame"] as? [Int], alpha.count >= 4,
      width > 0, height > 0
    else { return nil }

    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .positiveInfinity
    guard let frame = try? generator.copyCGImage(at: .zero, actualTime: nil) else { return nil }

    let sw = frame.width
    let sh = frame.height
    let space = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    var source = [UInt8](repeating: 0, count: sw * sh * 4)
    guard
      let sourceContext = CGContext(
        data: &source, width: sw, height: sh, bitsPerComponent: 8, bytesPerRow: sw * 4,
        space: space, bitmapInfo: bitmapInfo)
    else { return nil }
    sourceContext.draw(frame, in: CGRect(x: 0, y: 0, width: sw, height: sh))

    // The generator may hand back a frame scaled from the coded size.
    let scaleX = Double(sw) / Double(max(info["videoW"] as? Int ?? sw, 1))
    let scaleY = Double(sh) / Double(max(info["videoH"] as? Int ?? sh, 1))
    let rx = Double(rgb[0]) * scaleX, ry = Double(rgb[1]) * scaleY
    let rw = Double(rgb[2]) * scaleX, rh = Double(rgb[3]) * scaleY
    let ax = Double(alpha[0]) * scaleX, ay = Double(alpha[1]) * scaleY
    let aw = Double(alpha[2]) * scaleX, ah = Double(alpha[3]) * scaleY

    var out = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
      let fy = (Double(y) + 0.5) / Double(height)
      let cy = min(max(Int(ry + fy * rh), 0), sh - 1)
      let my = min(max(Int(ay + fy * ah), 0), sh - 1)
      for x in 0..<width {
        let fx = (Double(x) + 0.5) / Double(width)
        let cx = min(max(Int(rx + fx * rw), 0), sw - 1)
        let mx = min(max(Int(ax + fx * aw), 0), sw - 1)
        let c = (cy * sw + cx) * 4
        // The mask is greyscale; its red channel carries the alpha value.
        let a = Int(source[(my * sw + mx) * 4])
        let o = (y * width + x) * 4
        // Output is premultiplied.
        out[o] = UInt8(Int(source[c]) * a / 255)
        out[o + 1] = UInt8(Int(source[c + 1]) * a / 255)
        out[o + 2] = UInt8(Int(source[c + 2]) * a / 255)
        out[o + 3] = UInt8(a)
      }
    }

    guard
      let outContext = CGContext(
        data: &out, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: space, bitmapInfo: bitmapInfo),
      let image = outContext.makeImage()
    else { return nil }
    return UIImage(cgImage: image).pngData()
  }

  /// The clip's display size, or nil when the file has no VAP layout.
  static func clipSize(path: String) -> CGSize? {
    guard let info = readInfo(path: path),
      let width = info["w"] as? Int, let height = info["h"] as? Int,
      width > 0, height > 0
    else { return nil }
    return CGSize(width: width, height: height)
  }

  /// The `info` object of the file's `vapc` box, or nil if there is none.
  private static func readInfo(path: String) -> [String: Any]? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { handle.closeFile() }
    let length = handle.seekToEndOfFile()
    var offset: UInt64 = 0

    func bigEndian(_ data: Data) -> UInt64 {
      data.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }

    // Top-level MP4 boxes: [4-byte size][4-byte type][payload].
    while offset + 8 <= length {
      handle.seek(toFileOffset: offset)
      let head = handle.readData(ofLength: 8)
      guard head.count == 8 else { return nil }
      var size = bigEndian(head.subdata(in: 0..<4))
      let type = String(data: head.subdata(in: 4..<8), encoding: .isoLatin1)
      var header: UInt64 = 8
      if size == 1 {
        size = bigEndian(handle.readData(ofLength: 8))
        header = 16
      } else if size == 0 {
        size = length - offset
      }
      guard size >= header else { return nil }

      if type == "vapc" {
        let payload = size - header
        guard payload > 0, payload <= 4 * 1024 * 1024 else { return nil }
        let json = handle.readData(ofLength: Int(payload))
        let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any]
        return object?["info"] as? [String: Any]
      }
      offset += size
    }
    return nil
  }
}
