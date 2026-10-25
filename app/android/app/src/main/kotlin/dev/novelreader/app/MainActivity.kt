package dev.novelreader.app

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val debuggable get() = applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 集成测试要跑几分钟，中途息屏 app 就退到后台被冻结；只在可调试的构建里开
        if (debuggable) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 阅读页的屏幕常亮（complete-reader-settings 设计 D4）。可调试的构建一直常亮，见 onCreate，关闭时不清掉
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "novel_reader/screen").setMethodCallHandler { call, result ->
            if (call.method != "keepOn") return@setMethodCallHandler result.notImplemented()
            if (call.arguments as Boolean) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else if (!debuggable) {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            result.success(null)
        }
    }
}
