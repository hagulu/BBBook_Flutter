package com.hagulu.nook.bbbook

import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.ArrayDeque
import java.util.UUID

class MainActivity : FlutterActivity() {
    private val socialConfigChannelName = "com.hagulu.nook.bbbook/social_config"
    private val methodChannelName = "com.hagulu.nook.bbbook/external_import"
    private val eventChannelName = "com.hagulu.nook.bbbook/external_import/events"
    private val pendingFiles = ArrayDeque<Map<String, String>>()
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, socialConfigChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "isNaverConfigured" && call.method != "getKakaoNativeAppKey") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val metadata = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA).metaData
                    when (call.method) {
                        "isNaverConfigured" -> {
                            val clientId = metadata?.getString("com.naver.sdk.clientId")
                            val clientSecret = metadata?.getString("com.naver.sdk.clientSecret")
                            result.success(!clientId.isNullOrBlank() && !clientSecret.isNullOrBlank())
                        }
                        "getKakaoNativeAppKey" -> {
                            result.success(metadata?.getString("com.hagulu.nook.bbbook.kakaoNativeAppKey") ?: "")
                        }
                    }
                } catch (_: Exception) {
                    result.error("SOCIAL_CONFIG_UNAVAILABLE", "Social configuration is unavailable", null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "getInitialSharedFile") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                result.success(pollPendingFile())
            }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                    emitPendingFiles()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val receivedIntent = intent ?: return
        val uri = when (receivedIntent.action) {
            Intent.ACTION_SEND -> sharedUri(receivedIntent)
            Intent.ACTION_VIEW -> receivedIntent.data
            else -> null
        } ?: return
        val displayName = normalizedDisplayName(
            queryDisplayName(uri) ?: uri.lastPathSegment,
            receivedIntent.type,
        )

        // content:// 권한이 살아 있는 동안 바로 앱 캐시로 복사한다. SQLite
        // 파서나 이후 화면은 외부 URI를 보관하거나 직접 열지 않는다.
        Thread {
            val payload = try {
                cleanupOldCachedFiles()
                val copied = copyToCache(uri, displayName)
                mapOf("path" to copied.absolutePath, "displayName" to displayName)
            } catch (_: Exception) {
                Log.w("BBBookExternalImport", "Shared file copy failed")
                mapOf(
                    "path" to "",
                    "displayName" to displayName,
                    "errorMessage" to "공유받은 파일을 읽을 수 없어요. 파일을 저장한 뒤 다시 시도해 주세요.",
                )
            }
            runOnUiThread {
                synchronized(pendingFiles) { pendingFiles.addLast(payload) }
                emitPendingFiles()
            }
        }.start()

        // 동일 Activity 인스턴스가 구성 변경 등으로 Intent를 다시 처리해
        // 파일을 중복 복사하지 않게 소비한 값을 제거한다.
        receivedIntent.removeExtra(Intent.EXTRA_STREAM)
        receivedIntent.clipData = null
        receivedIntent.data = null
        receivedIntent.action = null
    }

    @Suppress("DEPRECATION")
    private fun sharedUri(intent: Intent): Uri? {
        val direct = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        return direct ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
    }

    private fun queryDisplayName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } catch (_: Exception) {
            uri.lastPathSegment
        } finally {
            cursor?.close()
        }
    }

    private fun normalizedDisplayName(name: String?, mimeType: String?): String {
        val extension = when (mimeType?.lowercase()) {
            "text/csv", "text/comma-separated-values", "application/csv",
            "application/vnd.ms-excel" -> ".csv"
            "application/zip", "application/x-zip-compressed",
            "application/x-bookmory", "application/octet-stream" -> ".bookmory"
            else -> ""
        }
        val baseName = name?.substringAfterLast('/')?.ifEmpty { null } ?: "shared_file"
        return if (baseName.substringAfterLast('.', "").isEmpty()) {
            "$baseName$extension"
        } else {
            baseName
        }
    }

    private fun copyToCache(uri: Uri, originalName: String): File {
        val directory = File(cacheDir, "external_imports").apply { mkdirs() }
        val safeName = originalName
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._가-힣-]"), "_")
            .take(120)
            .ifEmpty { "shared_file" }
        val destination = File(directory, "${UUID.randomUUID()}_$safeName")
        try {
            val input = contentResolver.openInputStream(uri)
                ?: throw IllegalArgumentException("Unable to open shared URI")
            input.use { stream ->
                FileOutputStream(destination).use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > MAX_SHARED_FILE_BYTES) {
                            throw IllegalArgumentException("Shared file is too large")
                        }
                        output.write(buffer, 0, read)
                    }
                    output.flush()
                }
            }
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
        return destination
    }

    private fun cleanupOldCachedFiles() {
        val directory = File(cacheDir, "external_imports")
        val cutoff = System.currentTimeMillis() - CACHE_RETENTION_MILLIS
        directory.listFiles()?.forEach { file ->
            if (file.isFile && file.lastModified() < cutoff) file.delete()
        }
    }

    private fun pollPendingFile(): Map<String, String>? =
        synchronized(pendingFiles) {
            if (pendingFiles.isEmpty()) null else pendingFiles.removeFirst()
        }

    private fun emitPendingFiles() {
        val sink = eventSink ?: return
        while (true) {
            val next = pollPendingFile() ?: break
            sink.success(next)
        }
    }

    companion object {
        private const val MAX_SHARED_FILE_BYTES = 512L * 1024L * 1024L
        private const val CACHE_RETENTION_MILLIS = 24L * 60L * 60L * 1000L
    }
}
