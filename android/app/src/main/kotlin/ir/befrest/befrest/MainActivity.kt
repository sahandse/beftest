package ir.befrest.befrest

import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "ir.befrest/app_export"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
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
                            Regex("[^a-zA-Z0-9._\u0600-\u06FF-]+"),
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
    }
}
