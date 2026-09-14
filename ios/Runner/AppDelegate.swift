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
    let channel = FlutterMethodChannel(
      name: "com.hagulu.nook.bbbook/social_config",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isNaverConfigured":
        let keys = ["NidClientID", "NidClientSecret", "NidUrlScheme"]
        let isConfigured = keys.allSatisfy { key in
          guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return false
          }
          return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !value.contains("$(")
        }
        result(isConfigured)
      case "getKakaoNativeAppKey":
        result(Bundle.main.object(forInfoDictionaryKey: "KakaoNativeAppKey") as? String ?? "")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
