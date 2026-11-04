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
    screen.setMethodCallHandler { [weak self] call, result in
      switch (call.method, call.arguments) {
      // 阅读页的屏幕常亮（complete-reader-settings 设计 D4）
      case ("keepOn", let on as Bool):
        UIApplication.shared.isIdleTimerDisabled = on
      case ("brightness", let value):
        self?.setBrightness(value as? Double)
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 阅读页改亮度之前的系统亮度；没有改过时为空。
  private var systemBrightness: CGFloat?

  /// 阅读页亮度（add-reader-brightness 设计 D2）：iOS 只能改整块屏幕，所以第一次改时记下原来的亮度，nil 时设回去。
  private func setBrightness(_ value: Double?) {
    if let value {
      if systemBrightness == nil { systemBrightness = UIScreen.main.brightness }
      UIScreen.main.brightness = CGFloat(value)
    } else if let original = systemBrightness {
      UIScreen.main.brightness = original
      systemBrightness = nil
    }
  }
}
