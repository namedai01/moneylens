package vn.moneylens.moneylens

import android.app.Notification
import android.content.ComponentName
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.io.File
import java.util.concurrent.Executors

/**
 * Bound directly by the system while notification access is granted, so it
 * keeps working after the app is swiped away, killed or the phone reboots —
 * no Flutter engine needs to be alive.
 */
class VcbNotificationListener : NotificationListenerService() {
    private val io = Executors.newSingleThreadExecutor()

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val extras = sbn.notification.extras
        val n = CapturedNotification(
            packageName = sbn.packageName,
            title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
            text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
            bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString(),
            postedAt = sbn.postTime,
        )
        io.execute {
            try {
                CaptureLogStore(logFile(this)).record(n)
            } catch (e: Exception) {
                // Never log notification content: it may belong to any app.
                Log.e(TAG, "failed to record notification from ${n.packageName}", e)
            }
        }
    }

    override fun onListenerDisconnected() {
        // Ask the system to bind us again instead of staying silent.
        requestRebind(ComponentName(this, VcbNotificationListener::class.java))
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "VcbNotificationListener"

        /** Same directory Flutter's path_provider calls "documents" (app_flutter). */
        fun logFile(context: Context): File =
            File(context.getDir("flutter", Context.MODE_PRIVATE), CaptureLogStore.FILE_NAME)
    }
}
