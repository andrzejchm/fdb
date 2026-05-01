import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nativeDialogChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()

    nativeDialogChannel = FlutterMethodChannel(name: "fdb_test/native_dialog", binaryMessenger: messenger)
    nativeDialogChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "showNativeAlert" {
        self?.showNativeAlert(result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

  }

  private func showNativeAlert(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      let rootVC = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first(where: { $0.isKeyWindow })?.rootViewController
      guard let rootVC else {
        result(FlutterError(code: "NO_VC", message: "No root view controller", details: nil))
        return
      }
      let alert = UIAlertController(
        title: "Native Alert",
        message: "This is a native UIAlertController — not a Flutter widget.",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
        result("CANCELLED")
      })
      alert.addAction(UIAlertAction(title: "Confirm", style: .default) { _ in
        NSLog("[fdb_test] NATIVE_ALERT_CONFIRMED")
        result("CONFIRMED")
      })
      rootVC.present(alert, animated: false)
    }
  }
}
