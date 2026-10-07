package ir.befrest.befrest

import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.net.wifi.WifiManager
import android.content.Context
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val appExportChannelName = "ir.befrest/app_export"
    private val shareChannelName = "ir.befrest/share_intent"
    private val networkChannelName = "ir.befrest/network"

    private var multicastLock: WifiManager.MulticastLock? = null

    private var shareChannel: MethodChannel? = null
    private val pendingSharedPaths = mutableListOf<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appExportChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "exportApk" -> {
                    val packageName = call.argument<String>("packageName")
                    val label = call.argument<String>("label") ?: "app"
                    val version = call.argument<String>("version") ?: ""

                    if (packageName.isNullOrBlank()) {
                        result.error("INVALID_PACKAGE", "Package name is missing", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val appInfo = packageManager.getApplicationInfo(
                            packageName,
                            PackageManager.ApplicationInfoFlags.of(0)
                        )

                        val source = File(appInfo.sourceDir)
                        if (!source.exists()) {
                            result.error("APK_NOT_FOUND", "APK source file not found", null)
                            return@setMethodCallHandler
                        }

                        val safeLabel = label.replace(
                            Regex("[^a-zA-Z0-9._\\u0600-\\u06FF-]+"),
                            "_"
                        ).trim('_')

                        val safeVersion = version.replace(
                            Regex("[^a-zA-Z0-9._-]+"),
                            "_"
                        )

                        val fileName = buildString {
                            append(if (safeLabel.isBlank()) "app" else safeLabel)
                            if (safeVersion.isNotBlank()) {
                                append("-")
                                append(safeVersion)
                            }
                            append(".apk")
                        }

                        val exportDir = File(cacheDir, "shared_apks").apply {
                            mkdirs()
                        }
                        val destination = File(exportDir, fileName)

                        source.inputStream().use { input ->
                            destination.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }

                        result.success(destination.absolutePath)
                    } catch (error: Exception) {
                        result.error(
                            "APK_EXPORT_FAILED",
                            error.message ?: "Failed to export APK",
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            networkChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        if (multicastLock?.isHeld != true) {
                            val wifiManager = applicationContext
                                .getSystemService(Context.WIFI_SERVICE) as WifiManager
                            multicastLock = wifiManager
                                .createMulticastLock("befrest-multicast")
                                .apply {
                                    setReferenceCounted(false)
                                    acquire()
                                }
                        }
                        result.success(true)
                    } catch (error: Exception) {
                        result.error(
                            "MULTICAST_LOCK_FAILED",
                            error.message ?: "Unable to acquire multicast lock",
                            null
                        )
                    }
                }

                "releaseMulticastLock" -> {
                    try {
                        if (multicastLock?.isHeld == true) {
                            multicastLock?.release()
                        }
                        multicastLock = null
                        result.success(true)
                    } catch (error: Exception) {
                        result.error(
                            "MULTICAST_UNLOCK_FAILED",
                            error.message ?: "Unable to release multicast lock",
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }

        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shareChannelName
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialSharedFiles" -> {
                        val items = pendingSharedPaths.toList()
                        pendingSharedPaths.clear()
                        result.success(items)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        processShareIntent(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        processShareIntent(intent, notifyFlutter = true)
    }

    private fun processShareIntent(intent: Intent?, notifyFlutter: Boolean) {
        if (intent == null) return
        if (intent.getBooleanExtra("_befrest_processed", false)) return

        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) {
            return
        }

        val paths = mutableListOf<String>()

        try {
            if (action == Intent.ACTION_SEND) {
                intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)?.let { uri ->
                    copySharedUriToCache(uri)?.let(paths::add)
                }
            } else {
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
                    ?.forEach { uri ->
                        copySharedUriToCache(uri)?.let(paths::add)
                    }
            }

            val sharedText = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)
                ?.toString()
                ?.trim()

            if (!sharedText.isNullOrEmpty()) {
                val dir = File(cacheDir, "shared_intents").apply { mkdirs() }
                val file = File(
                    dir,
                    "shared-text-${System.currentTimeMillis()}.txt"
                )
                file.writeText(sharedText)
                paths.add(file.absolutePath)
            }

            intent.putExtra("_befrest_processed", true)

            if (paths.isNotEmpty()) {
                if (notifyFlutter) {
                    shareChannel?.invokeMethod("sharedFiles", paths)
                } else {
                    pendingSharedPaths.addAll(paths)
                }
            }
        } catch (_: Exception) {
            // Ignore malformed share intents instead of crashing the app.
        }
    }

    private fun copySharedUriToCache(uri: Uri): String? {
        if (uri.scheme == "file") {
            val path = uri.path ?: return null
            val file = File(path)
            return if (file.exists() && file.isFile) file.absolutePath else null
        }

        val input = contentResolver.openInputStream(uri) ?: return null
        val dir = File(cacheDir, "shared_intents").apply { mkdirs() }
        val originalName = queryDisplayName(uri)
            ?: "shared-${System.currentTimeMillis()}"
        val safeName = originalName
            .replace(Regex("[\\\\/:*?\"<>|]+"), "_")
            .replace("..", "_")
            .take(180)
            .ifBlank { "shared-${System.currentTimeMillis()}" }

        var destination = File(dir, safeName)
        if (destination.exists()) {
            val dot = safeName.lastIndexOf('.')
            val stem = if (dot > 0) safeName.substring(0, dot) else safeName
            val ext = if (dot > 0) safeName.substring(dot) else ""
            destination = File(
                dir,
                "$stem-${System.currentTimeMillis()}$ext"
            )
        }

        input.use { source ->
            destination.outputStream().use { output ->
                source.copyTo(output)
            }
        }

        return destination.absolutePath
    }

    override fun onDestroy() {
        try {
            if (multicastLock?.isHeld == true) {
                multicastLock?.release()
            }
        } catch (_: Exception) {
        } finally {
            multicastLock = null
        }
        super.onDestroy()
    }

    private fun queryDisplayName(uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } finally {
            cursor?.close()
        }
    }
}
