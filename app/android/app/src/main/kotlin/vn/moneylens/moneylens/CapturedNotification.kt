package vn.moneylens.moneylens

data class CapturedNotification(
    val packageName: String,
    val title: String?,
    val text: String?,
    val bigText: String?,
    /** Notification post time, epoch milliseconds. */
    val postedAt: Long,
) {
    /** Expanded text when the app provides it, otherwise the short text. */
    val body: String get() = bigText?.takeIf { it.isNotEmpty() } ?: text ?: ""
}

/** True for Vietcombank apps (exact package id is confirmed during the spike). */
fun isVcbPackage(packageName: String): Boolean {
    val p = packageName.lowercase()
    return p.contains("vcb") || p.contains("vietcombank")
}
