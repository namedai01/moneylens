package vn.moneylens.moneylens

import android.content.Intent
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
                    "logPath" -> result.success(VcbNotificationListener.logFile(this).path)
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val CHANNEL = "moneylens/listener"
    }
}
