package com.comicforge.comic_forge

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/**
 * 书架更新的本机通知：创建渠道、申请权限、展示/取消，以及把点按回传给 Flutter。
 */
class ShelfUpdateNotifications(private val activity: Activity) {
    companion object {
        const val CHANNEL_ID = "shelf_updates"
        const val EXTRA_BOOK_URL = "com.comicforge.comic_forge.BOOK_URL"
        const val EXTRA_SOURCE_ID = "com.comicforge.comic_forge.SOURCE_ID"
        const val REQ_POST_NOTIFICATIONS = 5401
    }

    private val manager =
        activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private var pendingOpen: Map<String, String>? = null
    private var permissionResult: MethodChannel.Result? = null
    private var flutterChannel: MethodChannel? = null

    fun attach(channel: MethodChannel) {
        flutterChannel = channel
        handleIntent(activity.intent, fromLaunch = true)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    ensureChannel()
                    result.success(consumePending())
                }
                "requestPermission" -> requestPermission(result)
                "show" -> result.success(show(call.arguments))
                "cancelAll" -> {
                    manager.cancelAll()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun handleIntent(intent: Intent?, fromLaunch: Boolean) {
        val request = openRequest(intent) ?: return
        if (fromLaunch || flutterChannel == null) {
            pendingOpen = request
        } else {
            flutterChannel?.invokeMethod("opened", request)
        }
    }

    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQ_POST_NOTIFICATIONS) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        permissionResult?.success(granted)
        permissionResult = null
        return true
    }

    private fun consumePending(): Map<String, String>? {
        val pending = pendingOpen
        pendingOpen = null
        return pending
    }

    private fun openRequest(intent: Intent?): Map<String, String>? {
        val bookUrl = intent?.getStringExtra(EXTRA_BOOK_URL) ?: return null
        if (bookUrl.isEmpty()) return null
        return mapOf(
            "bookUrl" to bookUrl,
            "sourceId" to (intent.getStringExtra(EXTRA_SOURCE_ID) ?: ""),
        )
    }

    private fun requestPermission(result: MethodChannel.Result) {
        if (canPost()) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < 33) {
            result.success(false)
            return
        }
        if (permissionResult != null) {
            result.success(false)
            return
        }
        permissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_POST_NOTIFICATIONS,
        )
    }

    private fun show(raw: Any?): Boolean {
        if (raw !is Map<*, *>) return false
        if (!canPost()) return false
        val id = (raw["id"] as? Number)?.toInt() ?: return false
        val title = raw["title"] as? String ?: return false
        val body = raw["body"] as? String ?: return false
        val bookUrl = raw["bookUrl"] as? String ?: return false
        val sourceId = raw["sourceId"] as? String ?: ""
        ensureChannel()
        val pending = pendingIntent(id, bookUrl, sourceId)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(activity, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(activity)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_update)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        manager.notify(id, notification)
        return true
    }

    private fun pendingIntent(id: Int, bookUrl: String, sourceId: String): PendingIntent {
        val intent = Intent(activity, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_BOOK_URL, bookUrl)
            putExtra(EXTRA_SOURCE_ID, sourceId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(activity, id, intent, flags)
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "书架更新",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "书架漫画有新章节时提醒"
            },
        )
    }

    private fun canPost(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return manager.areNotificationsEnabled()
    }
}
