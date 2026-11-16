package com.inboxplus.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.system.Os
import android.system.OsConstants
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "inboxplus/native")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "capabilities" -> result.success(
                        mapOf("web_login_platforms" to emptyList<String>(), "imessage" to false),
                    )
                    "webLogin" -> result.error("web_login_unavailable", null, null)
                    "cancelWebLogin" -> result.success(null)
                    "imessageSnapshot", "imessageSend" -> result.error("imessage_unavailable", null, null)
                    "legacyProfileStatus" -> result.success(
                        mapOf("has_legacy_profile" to false, "profile_names" to emptyList<String>()),
                    )
                    "setHasUnfinishedWork" -> result.success(null)
                    "openFile" -> {
                        val path = call.argument<String>("path")
                        if (path != null && openFile(path, call.argument<String>("mime_type"))) {
                            result.success(true)
                        } else {
                            result.error("attachment_unavailable", null, null)
                        }
                    }
                    "protectPath" -> {
                        val path = call.argument<String>("path")
                        val mode = call.argument<Number>("mode")?.toInt()
                        if (path == null || mode == null) {
                            result.error("invalid_arguments", null, null)
                        } else if (protectPath(path, mode)) {
                            result.success(true)
                        } else {
                            result.error("path_protection_failed", null, null)
                        }
                    }
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "notify" -> {
                        result.success(showNotification(
                            call.argument<String>("title") ?: "Inbox+",
                            call.argument<String>("body") ?: "New message",
                            call.argument<Boolean>("sound") != false,
                        ))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openFile(path: String, mimeType: String?): Boolean {
        return try {
            val requested = File(path)
            if (!requested.isAbsolute || !OsConstants.S_ISREG(Os.lstat(path).st_mode)) return false
            val file = requested.canonicalFile
            val profiles = File(filesDir, "InboxPlus/profiles").canonicalFile
            if (!file.path.startsWith(profiles.path + File.separator)) return false
            val relative = file.relativeTo(profiles).invariantSeparatorsPath.split('/')
            if (relative.size < 4 || relative[1] != "flutter" || relative[2] !in setOf("media", "staging")) return false
            val uri = FileProvider.getUriForFile(this, "$packageName.attachments", file)
            val inferredType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase())
            val intent = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mimeType ?: inferredType ?: "application/octet-stream")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            intent.clipData = ClipData.newRawUri("Attachment", uri)
            startActivity(Intent.createChooser(intent, "Open attachment"))
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: IllegalArgumentException) {
            false
        } catch (_: SecurityException) {
            false
        } catch (_: android.system.ErrnoException) {
            false
        } catch (_: java.io.IOException) {
            false
        }
    }

    private fun protectPath(path: String, mode: Int): Boolean {
        if (!File(path).isAbsolute || (mode != 448 && mode != 384)) return false
        return try {
            if (OsConstants.S_ISLNK(Os.lstat(path).st_mode)) return false
            val target = File(path).canonicalFile
            val root = File(applicationInfo.dataDir).canonicalFile
            if (target != root && !target.path.startsWith(root.path + File.separator)) return false
            val descriptor = Os.open(target.path, OsConstants.O_RDONLY or OsConstants.O_CLOEXEC or OsConstants.O_NOFOLLOW, 0)
            try {
                val metadata = Os.fstat(descriptor)
                val validKind = (mode == 448 && OsConstants.S_ISDIR(metadata.st_mode)) ||
                    (mode == 384 && OsConstants.S_ISREG(metadata.st_mode))
                if (metadata.st_uid != Process.myUid() || !validKind) false
                else {
                    Os.fchmod(descriptor, mode)
                    true
                }
            } finally {
                Os.close(descriptor)
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            result.success(manager.areNotificationsEnabled())
        } else if (notificationPermissionResult != null) {
            result.error("permission_request_in_progress", null, null)
        } else {
            notificationPermissionResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            notificationPermissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            notificationPermissionResult = null
        }
    }

    private fun showNotification(title: String, body: String, playSound: Boolean): Boolean {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (!manager.areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return false
        val channelId = if (playSound) "messages" else "messages-silent"
        if (Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel(channelId,
                if (playSound) "Messages" else "Silent messages", NotificationManager.IMPORTANCE_DEFAULT)
            if (!playSound) {
                channel.setSound(null, null)
                channel.enableVibration(false)
            }
            manager.createNotificationChannel(channel)
        }
        val openApp = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channelId) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title).setContentText(body)
            .setDefaults(if (playSound) Notification.DEFAULT_SOUND else 0)
            .setVisibility(Notification.VISIBILITY_PRIVATE).setContentIntent(openApp)
            .setAutoCancel(true).build()
        return try {
            manager.notify(1, notification)
            true
        } catch (_: SecurityException) {
            false
        }
    }

    override fun onDestroy() {
        notificationPermissionResult?.error("permission_request_cancelled", null, null)
        notificationPermissionResult = null
        super.onDestroy()
    }
}
