import Flutter
import UIKit
import Vision

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
    TextRecognizer.register(
      with: engineBridge.applicationRegistrar.messenger()
    )
  }
}

/// On-device text recognition (Apple Vision) for the ingredient scanner.
/// The photo is read from a local file and never leaves the phone.
/// Channel: `cosmetix/ocr`, method `recognizeText({path})` -> String
/// (recognized lines separated by "\n").
final class TextRecognizer {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "cosmetix/ocr",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(
          FlutterError(code: "bad_args", message: "path is required", details: nil)
        )
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        recognize(path: path) { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success(let text):
              result(text)
            case .failure(let error):
              result(
                FlutterError(
                  code: "ocr_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }
      }
    }
  }

  private static func recognize(
    path: String,
    completion: @escaping (Result<String, Error>) -> Void
  ) {
    guard let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage
    else {
      completion(
        .failure(
          NSError(
            domain: "cosmetix.ocr",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Cannot read the image"]
          )
        )
      )
      return
    }
    let request = VNRecognizeTextRequest { request, error in
      if let error = error {
        completion(.failure(error))
        return
      }
      let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
      let lines = observations.compactMap { $0.topCandidates(1).first?.string }
      completion(.success(lines.joined(separator: "\n")))
    }
    request.recognitionLevel = .accurate
    // ingredient names are not dictionary words: do not "correct" them
    request.usesLanguageCorrection = false
    if #available(iOS 16.0, *) {
      request.revision = VNRecognizeTextRequestRevision3
      request.automaticallyDetectsLanguage = true
    }
    let handler = VNImageRequestHandler(
      cgImage: cgImage,
      orientation: orientation(of: image),
      options: [:]
    )
    do {
      try handler.perform([request])
    } catch {
      completion(.failure(error))
    }
  }

  private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
    switch image.imageOrientation {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    case .upMirrored: return .upMirrored
    case .downMirrored: return .downMirrored
    case .leftMirrored: return .leftMirrored
    case .rightMirrored: return .rightMirrored
    @unknown default: return .up
    }
  }
}
