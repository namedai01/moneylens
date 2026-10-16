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
        // Other apps' notifications are never read, stored or counted.
        if (!isVcbPackage(sbn.packageName)) return
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
                val db = CaptureDb.get(this)
                db.insert(n, receivedAt = System.currentTimeMillis())
                db.setState("last_vcb_at", n.postedAt)
            } catch (e: Exception) {
                // Never log notification content: it may belong to any app.
                Log.e(TAG, "failed to record notification from ${n.packageName}", e)
            }
        }
    }

    override fun onListenerConnected() {
        io.execute {
            try {
                val db = CaptureDb.get(this)
                db.importLegacyLog(legacyLogFile(this))
                db.setState("connected_at", System.currentTimeMillis())
            } catch (e: Exception) {
                Log.e(TAG, "failed to record listener connection", e)
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

        /** Phase-0 JSON log (app_flutter/capture_log.json), imported once into [CaptureDb]. */
        fun legacyLogFile(context: Context): File =
            File(context.getDir("flutter", Context.MODE_PRIVATE), "capture_log.json")
    }
}
