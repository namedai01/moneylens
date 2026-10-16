package vn.moneylens.moneylens

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

/**
 * Raw VCB notifications, written only by this process.
 *
 * Kotlin owns this file's schema; Dart (`lib/capture/raw_event_source.dart`)
 * opens it read-only. Keep column names in sync with
 * `test/support/capture_db_fixture.dart`.
 */
class CaptureDb(context: Context, name: String = FILE_NAME) :
    SQLiteOpenHelper(context, name, null, VERSION) {

    init {
        setWriteAheadLoggingEnabled(true)
    }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE raw_events (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              source TEXT NOT NULL DEFAULT 'android_notif',
              package_name TEXT NOT NULL,
              title TEXT, text TEXT, big_text TEXT,
              posted_at INTEGER NOT NULL,
              received_at INTEGER NOT NULL,
              dedup_hash TEXT NOT NULL UNIQUE
            )
            """.trimIndent(),
        )
        db.execSQL("CREATE TABLE listener_state (key TEXT PRIMARY KEY, value INTEGER NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit

    /** Stores [n] unless an identical notification is already there. */
    fun insert(n: CapturedNotification, receivedAt: Long): Boolean {
        val values = ContentValues().apply {
            put("package_name", n.packageName)
            put("title", n.title)
            put("text", n.text)
            put("big_text", n.bigText)
            put("posted_at", n.postedAt)
            put("received_at", receivedAt)
            put("dedup_hash", dedupHash(n))
        }
        return writableDatabase.insertWithOnConflict(
            "raw_events", null, values, SQLiteDatabase.CONFLICT_IGNORE,
        ) != -1L
    }

    fun setState(key: String, value: Long) {
        val values = ContentValues().apply {
            put("key", key)
            put("value", value)
        }
        writableDatabase.insertWithOnConflict(
            "listener_state", null, values, SQLiteDatabase.CONFLICT_REPLACE,
        )
    }

    /**
     * One-time move of the phase-0 `capture_log.json` into this database.
     * The file is deleted afterwards, even when it cannot be read.
     */
    fun importLegacyLog(file: File): Int {
        if (!file.exists()) return 0
        var imported = 0
        try {
            val entries = JSONObject(file.readText()).getJSONArray("vcb")
            for (i in 0 until entries.length()) {
                val e = entries.getJSONObject(i)
                val n = CapturedNotification(
                    packageName = e.getString("packageName"),
                    title = e.optStringOrNull("title"),
                    text = e.optStringOrNull("text"),
                    bigText = e.optStringOrNull("bigText"),
                    postedAt = e.getLong("postedAt"),
                )
                if (insert(n, receivedAt = n.postedAt)) imported++
            }
        } catch (_: Exception) {
            // Corrupt log: nothing worth keeping.
        }
        file.delete()
        return imported
    }

    companion object {
        const val FILE_NAME = "capture.db"
        private const val VERSION = 1

        @Volatile private var instance: CaptureDb? = null

        /** One helper per process so every writer shares one connection pool. */
        fun get(context: Context): CaptureDb =
            instance ?: synchronized(this) {
                instance ?: CaptureDb(context.applicationContext).also { instance = it }
            }
    }
}

fun dedupHash(n: CapturedNotification): String {
    val bytes = MessageDigest.getInstance("SHA-256")
        .digest("${n.packageName}\n${n.postedAt}\n${n.body}".toByteArray())
    return bytes.joinToString("") { "%02x".format(it) }
}

private fun JSONObject.optStringOrNull(key: String): String? =
    if (isNull(key)) null else optString(key)
