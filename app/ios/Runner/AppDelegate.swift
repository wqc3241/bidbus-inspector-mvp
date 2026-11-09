import AVFoundation
import Flutter
import ImageIO
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    _ = PhotoSize.held
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpinFrames") else { return }
    // 360 view: 36 evenly spaced frames from the walk-around, frame k at (k - 0.5) / 36 x duration, long side 1600 px
    FlutterMethodChannel(name: "bidbus/frames", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
      // a recorded video made smaller in place: see squeezeVideo
      if call.method == "squeeze", let a = call.arguments as? [String: Any], let video = a["video"] as? String,
        let bitrate = a["bitrate"] as? Int, let max = a["max"] as? Int
      {
        // all of it off the main thread (Flutter draws on it): the set-up alone takes up to ~150 ms
        DispatchQueue.global(qos: .utility).async {
          squeezeVideo(path: video, bitrate: bitrate, maxSide: max) { done in DispatchQueue.main.async { result(done) } }
        }
        return
      }
      guard call.method == "spin", let a = call.arguments as? [String: Any], let video = a["video"] as? String, let dir = a["dir"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let asset = AVURLAsset(url: URL(fileURLWithPath: video))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 1600, height: 1600)
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let dur = CMTimeGetSeconds(asset.duration)
        var out: [String] = []
        for k in 1...36 {
          let t = CMTime(seconds: (Double(k) - 0.5) / 36 * dur, preferredTimescale: 600)
          guard let cg = try? gen.copyCGImage(at: t, actualTime: nil), let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.85) else { continue }
          let p = "\(dir)/spin-\(String(format: "%02d", k)).jpg"
          if (try? data.write(to: URL(fileURLWithPath: p))) != nil { out.append(p) }
        }
        DispatchQueue.main.async { result(out) }
      }
    }
    // photos: turned upright, long side at most `max` px, JPEG of quality `q`, no metadata; returns the clockwise turn applied, -1 with no orientation
    FlutterMethodChannel(name: "bidbus/photo", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
      guard call.method == "upright", let a = call.arguments as? [String: Any], let from = a["from"] as? String, let to = a["to"] as? String,
        let max = a["max"] as? Int, let q = a["q"] as? Double
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let r = uprightPhoto(from: from, to: to, max: max, quality: q)
        DispatchQueue.main.async { result(r ?? FlutterError(code: "photo", message: "cannot read or write \(from)", details: nil)) }
      }
    }
  }
}

// MARK: native media (no Flutter types below this line)

// Photos: the camera plugin asks the 4:3 format for its largest photo, 48 MP on recent iPhones: slower to take and ten times
// what is kept (2560 px). The photo output's largest size is held to the largest the format offers within 12 MP, the iPhone
// camera's own default, and the plugin takes every photo at the output's largest size.
enum PhotoSize {
  static let limit: Int64 = 12_200_000
  static let held: Void = {
    if #available(iOS 16.0, macOS 13.0, *),
      let a = class_getInstanceMethod(AVCapturePhotoOutput.self, #selector(setter: AVCapturePhotoOutput.maxPhotoDimensions)),
      let b = class_getInstanceMethod(AVCapturePhotoOutput.self, #selector(AVCapturePhotoOutput.bidbusSetMaxPhotoDimensions(_:)))
    {
      method_exchangeImplementations(a, b)
    }
  }()
}

@available(iOS 16.0, macOS 13.0, *)
extension AVCapturePhotoOutput {
  @objc func bidbusSetMaxPhotoDimensions(_ d: CMVideoDimensions) {
    let px = { (x: CMVideoDimensions) in Int64(x.width) * Int64(x.height) }
    var pick = d
    if px(d) > PhotoSize.limit, let input = connection(with: .video)?.inputPorts.first?.input as? AVCaptureDeviceInput,
      let best = input.device.activeFormat.supportedMaxPhotoDimensions.filter({ px($0) > 0 && px($0) <= PhotoSize.limit }).max(by: { px($0) < px($1) })
    {
      pick = best
    }
    bidbusSetMaxPhotoDimensions(pick)  // the system's own setter, after the exchange
  }
}

// the clockwise turn applied, -1 when the file had no orientation, nil when it cannot be read or written
func uprightPhoto(from: String, to: String, max: Int, quality: Double) -> Int? {
  let fail: Int? = nil
  guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: from) as CFURL, nil),
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
  else { return fail }
  let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
  let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
  let side = w > 0 && h > 0 ? Swift.min(max, Swift.max(w, h)) : max
  let opts: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: side, kCGImageSourceShouldCacheImmediately: true,
  ]
  guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary),
    let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: to) as CFURL, "public.jpeg" as CFString, 1, nil)
  else { return fail }
  CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
  guard CGImageDestinationFinalize(dst) else { return fail }
  guard let o = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue else { return -1 }
  return [1: 0, 3: 180, 6: 90, 8: 270][o] ?? 0
}

// A recorded video re-encoded smaller, in place: H.264 at `bitrate` bit/s, a key frame every second, long side at most `maxSide`,
// the sound copied as it is. The camera records with the system's own settings (sharp frames for the 360 view); this runs after.
// Skipped when the file is already at about that rate. done(true) when the file was replaced by the smaller one.
func squeezeVideo(path: String, bitrate: Int, maxSide: Int, done: @escaping (Bool) -> Void) {
  let src = URL(fileURLWithPath: path), fm = FileManager.default
  let asset = AVURLAsset(url: src)
  guard let vt = asset.tracks(withMediaType: .video).first else { return done(false) }
  if vt.estimatedDataRate > 0 && vt.estimatedDataRate <= Float(bitrate) * 1.25 { return done(false) }
  // the work file in the app's temp folder (same volume, so the replace is a rename): a kill mid-way leaves nothing behind for good
  let tmp = fm.temporaryDirectory.appendingPathComponent("squeeze-\(UUID().uuidString).\(src.pathExtension)")
  let fail = { try? fm.removeItem(at: tmp); done(false) }
  guard let reader = try? AVAssetReader(asset: asset),
    let writer = try? AVAssetWriter(outputURL: tmp, fileType: src.pathExtension.lowercased() == "mov" ? .mov : .mp4)
  else { return done(false) }
  let size = vt.naturalSize, scale = Swift.min(1, CGFloat(maxSide) / Swift.max(size.width, size.height, 1))
  let w = Int((size.width * scale / 2).rounded()) * 2, h = Int((size.height * scale / 2).rounded()) * 2
  let vOut = AVAssetReaderTrackOutput(track: vt, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange])
  vOut.alwaysCopiesSampleData = false
  let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h, AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
    AVVideoCompressionPropertiesKey: [
      AVVideoAverageBitRateKey: bitrate, AVVideoMaxKeyFrameIntervalDurationKey: 1, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
      AVVideoExpectedSourceFrameRateKey: vt.nominalFrameRate > 0 ? vt.nominalFrameRate : 30,
    ],
  ])
  vIn.transform = vt.preferredTransform
  guard reader.canAdd(vOut), writer.canAdd(vIn) else { return done(false) }
  reader.add(vOut)
  writer.add(vIn)
  var pairs: [(AVAssetReaderOutput, AVAssetWriterInput)] = [(vOut, vIn)]
  // only a video as the camera records it, one picture track and one sound track the system reads, is made smaller,
  // its sound copied as it is; anything else (a sound format AVFoundation does not see, several sound tracks, no sound)
  // is left as it was, so a smaller file never loses its sound
  let audio = asset.tracks(withMediaType: .audio)
  guard asset.tracks(withMediaType: .video).count == 1, audio.count == 1, let at = audio.first, let hint = at.formatDescriptions.first else { return done(false) }
  let aOut = AVAssetReaderTrackOutput(track: at, outputSettings: nil)
  let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: (hint as! CMFormatDescription))
  guard reader.canAdd(aOut), writer.canAdd(aIn) else { return done(false) }
  reader.add(aOut)
  writer.add(aIn)
  pairs.append((aOut, aIn))
  guard reader.startReading(), writer.startWriting() else {
    reader.cancelReading()
    return fail()
  }
  writer.startSession(atSourceTime: vt.timeRange.start)
  let group = DispatchGroup()
  for (k, (out, inp)) in pairs.enumerated() {
    group.enter()
    var over = false
    inp.requestMediaDataWhenReady(on: DispatchQueue(label: "squeeze-\(k)", qos: .utility)) {
      while !over && inp.isReadyForMoreMediaData {
        if let b = out.copyNextSampleBuffer(), inp.append(b) { continue }
        over = true
        inp.markAsFinished()
        group.leave()
      }
    }
  }
  group.notify(queue: .global(qos: .utility)) {
    guard reader.status == .completed else {
      writer.cancelWriting()
      return fail()
    }
    writer.finishWriting {
      let was = (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
      let now = (try? fm.attributesOfItem(atPath: tmp.path)[.size] as? Int) ?? 0
      // the new file must hold the picture and the sound;
      // the inspector may have recorded it again meanwhile: the old file is gone, nothing to replace
      let out = AVURLAsset(url: tmp)
      guard writer.status == .completed, now > 0, now < was, out.tracks(withMediaType: .video).count == 1,
        out.tracks(withMediaType: .audio).count == 1, fm.fileExists(atPath: path),
        (try? fm.replaceItemAt(src, withItemAt: tmp)) != nil
      else { return fail() }
      done(true)
    }
  }
}
