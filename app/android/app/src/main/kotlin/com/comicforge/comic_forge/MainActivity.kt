package com.comicforge.comic_forge

import android.content.Intent
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 音量键翻页：阅读器激活时拦截音量键转发给 Flutter 并抑制系统音量；
 * 未激活时走系统默认行为。通道名 `comic-forge/reader`：
 * - Flutter → 原生：setVolumeKeysEnabled(enabled: Bool)
 * - 原生 → Flutter：volumeUp() / volumeDown()
 *
 * 书架更新通知通道名 `comic-forge/notifications`，点按通知以 singleTop 回到本页。
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var volumeKeysEnabled = false
    private lateinit var shelfUpdateNotifications: ShelfUpdateNotifications

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        shelfUpdateNotifications = ShelfUpdateNotifications(this)
        shelfUpdateNotifications.attach(
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "comic-forge/notifications",
            )
        )
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (::shelfUpdateNotifications.isInitialized) {
            shelfUpdateNotifications.handleIntent(intent, fromLaunch = false)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (::shelfUpdateNotifications.isInitialized) {
            shelfUpdateNotifications.onRequestPermissionsResult(requestCode, grantResults)
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
