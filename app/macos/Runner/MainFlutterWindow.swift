import Cocoa
import FlutterMacOS
import IOKit.pwr_mgt

class MainFlutterWindow: NSWindow {
  /// 阻止显示器空闲熄灭的断言，0 表示没有。
  private var displayAssertion: IOPMAssertionID = 0

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // 阅读页的屏幕常亮（complete-reader-settings 设计 D4）
    let screen = FlutterMethodChannel(name: "novel_reader/screen", binaryMessenger: flutterViewController.engine.binaryMessenger)
    screen.setMethodCallHandler { [weak self] call, result in
      guard let self, call.method == "keepOn", let on = call.arguments as? Bool else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.keepDisplayOn(on)
      result(nil)
    }

    super.awakeFromNib()
  }

  /// 按当前有没有断言决定是否创建、释放：热重启后 Dart 侧记的状态清零，可能再要一次常亮，不能重复创建。
  private func keepDisplayOn(_ on: Bool) {
    if on, displayAssertion == 0 {
      IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        "novel_reader reading" as CFString,
        &displayAssertion
      )
    } else if !on, displayAssertion != 0 {
      IOPMAssertionRelease(displayAssertion)
      displayAssertion = 0
    }
  }
}
