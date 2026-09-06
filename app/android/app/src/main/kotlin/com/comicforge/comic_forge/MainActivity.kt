package com.comicforge.comic_forge

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 音量键翻页：阅读器激活时拦截音量键转发给 Flutter 并抑制系统音量；
 * 未激活时走系统默认行为。通道名 `comic-forge/reader`：
 * - Flutter → 原生：setVolumeKeysEnabled(enabled: Bool)
 * - 原生 → Flutter：volumeUp() / volumeDown()
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var volumeKeysEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "comic-forge/reader"
        ).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setVolumeKeysEnabled" -> {
                        volumeKeysEnabled = call.argument<Boolean>("enabled") == true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeysEnabled) {
            when (keyCode) {
                KeyEvent.KEYCODE_VOLUME_UP -> {
                    channel?.invokeMethod("volumeUp", null)
                    return true
                }
                KeyEvent.KEYCODE_VOLUME_DOWN -> {
                    channel?.invokeMethod("volumeDown", null)
                    return true
                }
            }
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (volumeKeysEnabled &&
            (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            return true // 抑制系统音量弹窗
        }
        return super.onKeyUp(keyCode, event)
    }
}
