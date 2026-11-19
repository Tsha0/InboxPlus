package com.inboxplus.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.provider.OpenableColumns
import android.system.Os
import android.system.OsConstants
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File

class MainActivity : FlutterActivity() {
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var fileRequest: FileRequest? = null

    private sealed interface FileRequest {
        val result: MethodChannel.Result
        data class Pick(val limit: Int, override val result: MethodChannel.Result) : FileRequest
        data class Export(val bytes: ByteArray, override val result: MethodChannel.Result) : FileRequest
    }

    private companion object {
        const val PRIVATE_FILE_REQUEST = 6014
    }

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
                    "pickPrivateFile" -> pickPrivateFile(
                        call.argument<String>("type"),
                        call.argument<Number>("limit")?.toInt(),
                        result,
                    )
                    "exportPrivateFile" -> exportPrivateFile(
                        call.argument<String>("name"),
                        call.argument<String>("mimeType"),
                        call.argument<ByteArray>("bytes"),
                        result,
                    )
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

    private fun pickPrivateFile(type: String?, limit: Int?, result: MethodChannel.Result) {
        if (type !in setOf("any", "image", "media") || limit == null || limit <= 0) {
            return result.error("invalid_request", null, null)
        }
        val intent = Intent(Intent.ACTION_GET_CONTENT).addCategory(Intent.CATEGORY_OPENABLE)
        intent.type = if (type == "image") "image/*" else "*/*"
        if (type == "media") intent.putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
        startFileRequest(intent, FileRequest.Pick(limit, result))
    }

    private fun exportPrivateFile(name: String?, mimeType: String?, bytes: ByteArray?, result: MethodChannel.Result) {
        if (name.isNullOrEmpty() || name == "." || name == ".." || name.any { it == '/' || it == '\\' || it == '\u0000' } ||
            mimeType.isNullOrEmpty() || bytes == null) {
            return result.error("invalid_request", null, null)
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mimeType).putExtra(Intent.EXTRA_TITLE, name)
        startFileRequest(intent, FileRequest.Export(bytes, result))
    }

    private fun startFileRequest(intent: Intent, request: FileRequest) {
        if (fileRequest != null) return request.result.error("file_picker_busy", null, null)
        try {
            fileRequest = request
            startActivityForResult(intent, PRIVATE_FILE_REQUEST)
        } catch (_: ActivityNotFoundException) {
            fileRequest = null
            request.result.error("file_picker_unavailable", null, null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PRIVATE_FILE_REQUEST) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val request = fileRequest ?: return
        if (resultCode != RESULT_OK) {
            settleFileRequest(request) { it.success(null) }
            return
        }
        val uri = data?.data
        val error = if (request is FileRequest.Export) "file_export_failed" else "picked_file_unreadable"
        if (uri?.scheme != ContentResolver.SCHEME_CONTENT) {
            settleFileRequest(request) { it.error(error, null, null) }
            return
        }
        Thread {
            try {
                if (request is FileRequest.Export) {
                    val output = contentResolver.openOutputStream(uri) ?: throw java.io.IOException()
                    output.use { it.write(request.bytes) }
                    settleFileRequest(request) { it.success(null) }
                    return@Thread
                }
                check(request is FileRequest.Pick)
                val name = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) it.getString(0) else null
                } ?: "Attachment"
                val bytes = contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count > request.limit - output.size()) {
                            settleFileRequest(request) { it.error("picked_file_too_large", null, null) }
                            return@Thread
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                } ?: throw java.io.IOException()
                settleFileRequest(request) { it.success(mapOf("name" to name, "bytes" to bytes)) }
            } catch (_: Exception) {
                settleFileRequest(request) { it.error(error, null, null) }
            }
        }.start()
    }

    private fun settleFileRequest(request: FileRequest, complete: (MethodChannel.Result) -> Unit) {
        runOnUiThread {
            if (fileRequest === request) {
                fileRequest = null
                complete(request.result)
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
        fileRequest?.result?.success(null)
        fileRequest = null
        notificationPermissionResult?.error("permission_request_cancelled", null, null)
        notificationPermissionResult = null
        super.onDestroy()
    }
}
