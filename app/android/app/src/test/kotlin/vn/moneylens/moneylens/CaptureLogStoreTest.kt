package vn.moneylens.moneylens

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.nio.file.Files

class CaptureLogStoreTest {
    private lateinit var dir: File
    private lateinit var file: File

    @Before
    fun setUp() {
        dir = Files.createTempDirectory("capture_log_store").toFile()
        file = File(dir, "capture_log.json")
    }

    @After
    fun tearDown() {
        dir.deleteRecursively()
    }

    private fun n(pkg: String, minute: Int) = CapturedNotification(
        packageName = pkg,
        title = "title $minute",
        text = "text $minute",
        bigText = null,
        postedAt = 1_760_580_000_000L + minute * 60_000L,
    )

    private fun vcbEntries() = JSONObject(file.readText()).getJSONArray("vcb")

    @Test
    fun storesVcbContentOnlyCountsOthers() {
        val store = CaptureLogStore(file)
        store.record(n("com.VCB", 1))
        store.record(n("com.zing", 2))

        val json = file.readText()
        assertEquals(1, vcbEntries().length())
        assertFalse(json.contains("text 2"))
        val counts = JSONObject(json).getJSONObject("counts")
        assertEquals(1, counts.getInt("com.zing"))
        assertEquals(1, counts.getInt("com.VCB"))
    }

    @Test
    fun keepsNewestFirst() {
        val store = CaptureLogStore(file)
        store.record(n("com.VCB", 1))
        store.record(n("com.VCB", 3))
        store.record(n("com.VCB", 2))

        val titles = (0 until 3).map { vcbEntries().getJSONObject(it).getString("title") }
        assertEquals(listOf("title 3", "title 2", "title 1"), titles)
    }

    @Test
    fun capsAtFifty() {
        val store = CaptureLogStore(file)
        for (i in 0 until 60) store.record(n("com.VCB", i))

        val vcb = vcbEntries()
        assertEquals(50, vcb.length())
        assertEquals("title 59", vcb.getJSONObject(0).getString("title"))
        assertEquals("title 10", vcb.getJSONObject(49).getString("title"))
    }

    @Test
    fun corruptFileStartsOver() {
        file.writeText("not json")
        CaptureLogStore(file).record(n("com.VCB", 1))

        assertEquals(1, vcbEntries().length())
    }

    /** Dart's CapturedNotification.fromJson reads exactly these keys. */
    @Test
    fun entrySchemaMatchesDart() {
        CaptureLogStore(file).record(
            CapturedNotification("com.VCB", null, "t", "big", 1_760_585_067_123L),
        )

        val e = vcbEntries().getJSONObject(0)
        assertEquals(setOf("packageName", "title", "text", "bigText", "postedAt"), e.keys().asSequence().toSet())
        assertTrue(e.isNull("title"))
        assertEquals("big", e.getString("bigText"))
        assertEquals(1_760_585_067_123L, e.getLong("postedAt"))
    }

    @Test
    fun concurrentRecordsAreAllKept() {
        val store = CaptureLogStore(file)
        val threads = (0 until 8).map { i -> Thread { store.record(n("com.VCB", i)) } }
        threads.forEach { it.start() }
        threads.forEach { it.join() }

        assertEquals(8, vcbEntries().length())
    }

    @Test
    fun isVcbPackageMatchesVietcombankApps() {
        assertTrue(isVcbPackage("com.VCB"))
        assertTrue(isVcbPackage("com.vietcombank.digibank"))
        assertFalse(isVcbPackage("com.google.android.gm"))
    }
}
