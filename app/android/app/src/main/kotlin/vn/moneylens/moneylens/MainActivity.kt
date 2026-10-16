package vn.moneylens.moneylens

import android.content.Intent
import android.content.pm.ApplicationInfo
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasAccess" -> result.success(
                        NotificationManagerCompat.getEnabledListenerPackages(this)
                            .contains(packageName),
                    )
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    "captureDbPath" -> {
                        val db = CaptureDb.get(this)
                        db.importLegacyLog(VcbNotificationListener.legacyLogFile(this))
                        db.writableDatabase // creates the file before Dart opens it read-only
                        result.success(getDatabasePath(CaptureDb.FILE_NAME).path)
                    }
                    "debugInjectVcb" -> {
                        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                            result.notImplemented()
                        } else {
                            val inserted = CaptureDb.get(this).insert(
                                CapturedNotification(
                                    packageName = "debug.vcb",
                                    title = call.argument<String>("title"),
                                    text = call.argument<String>("bigText"),
                                    bigText = call.argument<String>("bigText"),
                                    postedAt = System.currentTimeMillis(),
                                ),
                                receivedAt = System.currentTimeMillis(),
                            )
                            result.success(inserted)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val CHANNEL = "moneylens/listener"
    }
}
