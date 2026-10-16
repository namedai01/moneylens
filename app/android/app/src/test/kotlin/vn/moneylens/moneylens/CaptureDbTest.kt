package vn.moneylens.moneylens

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.util.concurrent.CountDownLatch
import kotlin.concurrent.thread

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CaptureDbTest {
    private lateinit var context: Context
    private lateinit var db: CaptureDb

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        db = CaptureDb(context, "test-capture.db")
    }

    @After
    fun tearDown() {
        db.close()
        context.deleteDatabase("test-capture.db")
    }

    private fun n(minute: Int, text: String? = "text $minute", bigText: String? = null) =
        CapturedNotification(
            packageName = "com.VCB",
            title = "title $minute",
            text = text,
            bigText = bigText,
            postedAt = 1_760_580_000_000L + minute * 60_000L,
        )

    private fun count(): Int =
        db.readableDatabase.rawQuery("SELECT COUNT(*) FROM raw_events", null).use {
            it.moveToFirst()
            it.getInt(0)
        }

    @Test
    fun duplicateNotificationInsertsOnce() {
        assertTrue(db.insert(n(1), receivedAt = 1L))
        assertFalse(db.insert(n(1), receivedAt = 2L))
        assertEquals(1, count())
    }

    @Test
    fun hashUsesBigTextWhenPresent() {
        assertEquals(
            dedupHash(n(1, text = "a", bigText = "b")),
            dedupHash(n(1, text = "x", bigText = "b")),
        )
    }

    @Test
    fun storesAllColumns() {
        db.insert(n(2, text = "short", bigText = "long"), receivedAt = 42L)
        db.readableDatabase.rawQuery(
            "SELECT package_name, title, text, big_text, posted_at, received_at, source FROM raw_events",
            null,
        ).use {
            it.moveToFirst()
            assertEquals("com.VCB", it.getString(0))
            assertEquals("title 2", it.getString(1))
            assertEquals("short", it.getString(2))
            assertEquals("long", it.getString(3))
            assertEquals(1_760_580_000_000L + 2 * 60_000L, it.getLong(4))
            assertEquals(42L, it.getLong(5))
            assertEquals("android_notif", it.getString(6))
        }
    }

    @Test
    fun importsLegacyLogThenDeletesIt() {
        val file = File(context.filesDir, "capture_log.json")
        file.writeText(
            """{"counts":{"com.VCB":3},"vcb":[
              {"packageName":"com.VCB","title":"t1","text":"a","bigText":null,"postedAt":1},
              {"packageName":"com.VCB","title":"t2","text":"b","bigText":"bb","postedAt":2},
              {"packageName":"com.VCB","title":null,"text":"c","bigText":null,"postedAt":3}]}""",
        )
        assertEquals(3, db.importLegacyLog(file))
        assertFalse(file.exists())
        assertEquals(0, db.importLegacyLog(file))
        assertEquals(3, count())
    }

    @Test
    fun corruptLegacyLogIsDropped() {
        val file = File(context.filesDir, "capture_log.json")
        file.writeText("{")
        assertEquals(0, db.importLegacyLog(file))
        assertFalse(file.exists())
    }

    @Test
    fun setStateUpserts() {
        db.setState("connected_at", 5L)
        db.setState("connected_at", 7L)
        db.readableDatabase.rawQuery("SELECT value FROM listener_state WHERE key = 'connected_at'", null).use {
            assertEquals(1, it.count)
            it.moveToFirst()
            assertEquals(7L, it.getLong(0))
        }
    }

    @Test
    fun burstOfInsertsFromThreadsKeepsAll() {
        val start = CountDownLatch(1)
        val threads = (1..20).map { i -> thread { start.await(); db.insert(n(i), receivedAt = i.toLong()) } }
        start.countDown()
        threads.forEach { it.join() }
        assertEquals(20, count())
    }
}
