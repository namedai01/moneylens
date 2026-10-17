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

private val shbSegment = Regex("""(^|\.)shb""")

/**
 * True for the bank apps MoneyLens reads: Vietcombank, and SHB matched on a
 * package segment so names like `cashbook` stay out.
 */
fun isBankPackage(packageName: String): Boolean {
    val p = packageName.lowercase()
    return p.contains("vcb") || p.contains("vietcombank") || shbSegment.containsMatchIn(p)
}
