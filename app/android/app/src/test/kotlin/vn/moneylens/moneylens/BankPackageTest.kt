package vn.moneylens.moneylens

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BankPackageTest {
    @Test
    fun readsVcbAndShbApps() {
        for (p in listOf("com.VCB", "com.vietcombank.digibank", "vn.shb.saha.mbanking", "vn.shb.mbanking", "shb.app")) {
            assertTrue(p, isBankPackage(p))
        }
    }

    @Test
    fun skipsOtherApps() {
        for (p in listOf("com.zing.zalo", "com.cashbook.app", "vn.fshbox.app")) {
            assertFalse(p, isBankPackage(p))
        }
    }
}
