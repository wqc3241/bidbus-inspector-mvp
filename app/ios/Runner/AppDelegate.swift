import AVFoundation
import Flutter
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
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpinFrames") else { return }
    // 360 view: 36 evenly spaced frames from the walk-around, frame k at (k - 0.5) / 36 x duration, long side 1600 px
    FlutterMethodChannel(name: "bidbus/frames", binaryMessenger: registrar.messenger()).setMethodCallHandler { call, result in
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
  }
}
