import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let screen = FlutterMethodChannel(name: "novel_reader/screen", binaryMessenger: registrar(forPlugin: "ScreenAwake")!.messenger())
    screen.setMethodCallHandler { call, result in
      switch (call.method, call.arguments) {
      // 阅读页的屏幕常亮（complete-reader-settings 设计 D4）
      case ("keepOn", let on as Bool):
        UIApplication.shared.isIdleTimerDisabled = on
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

}
