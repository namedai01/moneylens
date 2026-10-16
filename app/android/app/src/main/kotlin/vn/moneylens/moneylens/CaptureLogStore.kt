package vn.moneylens.moneylens

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

data class CapturedNotification(
    val packageName: String,
    val title: String?,
    val text: String?,
    val bigText: String?,
    /** Notification post time, epoch milliseconds. */
    val postedAt: Long,
)

/** True for Vietcombank apps (exact package id is confirmed during the spike). */
fun isVcbPackage(packageName: String): Boolean {
    val p = packageName.lowercase()
    return p.contains("vcb") || p.contains("vietcombank")
}

/**
 * Local debug log shared with Dart (`lib/capture/capture_log.dart` reads it).
 *
 * Keeps the full content of the latest [MAX_VCB_ENTRIES] VCB notifications and
 * only a per-package counter for everything else, so other apps' content is
 * never stored.
 */
class CaptureLogStore(private val file: File) {
    fun record(n: CapturedNotification) = synchronized(LOCK) {
        val root = read()
        val counts = root.getJSONObject("counts")
        counts.put(n.packageName, counts.optInt(n.packageName, 0) + 1)

        if (isVcbPackage(n.packageName)) {
            val entries = root.getJSONArray("vcb").let { a -> (0 until a.length()).map { a.getJSONObject(it) } }
            val kept = (entries + toJson(n))
                .sortedByDescending { it.getLong("postedAt") }
                .take(MAX_VCB_ENTRIES)
            root.put("vcb", JSONArray(kept))
        }
        write(root)
    }

    private fun read(): JSONObject = try {
        JSONObject(file.readText()).also {
            it.getJSONArray("vcb")
            it.getJSONObject("counts")
        }
    } catch (_: Exception) {
        // Missing or corrupt log must never break capturing; start over.
        JSONObject().put("vcb", JSONArray()).put("counts", JSONObject())
    }

    private fun write(root: JSONObject) {
        val tmp = File(file.path + ".tmp")
        tmp.writeText(root.toString())
        if (!tmp.renameTo(file)) throw IllegalStateException("cannot replace ${file.path}")
    }

    private fun toJson(n: CapturedNotification) = JSONObject()
        .put("packageName", n.packageName)
        .put("title", n.title ?: JSONObject.NULL)
        .put("text", n.text ?: JSONObject.NULL)
        .put("bigText", n.bigText ?: JSONObject.NULL)
        .put("postedAt", n.postedAt)

    companion object {
        const val MAX_VCB_ENTRIES = 50
        const val FILE_NAME = "capture_log.json"

        // One lock per process: the service and any other caller share the file.
        private val LOCK = Any()
    }
}
