package fail.still.android.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Which links name a station's screen (as the web's), and when one is written bare. */
class ScreenLinkTest {
    private val ws = "01M3DB2N6P5SY7PJ7RG1F62TRX"
    private val st = "0c5fa455d2b8783c01fc7d16bf09a7f758155429cf393879a32a7bfe0c77d372"

    @Test fun aScreensPageNamesItsStationAndTheScreenDecoded() {
        assertEquals("$ws/$st" to "browser:D4AD129260A6A360D131CA36CF35F544", screenOfLink("https://app.still.fail/w/$ws/s/$st/screen/browser%3AD4AD129260A6A360D131CA36CF35F544"))
        assertEquals("$ws/$st" to "desktop", screenOfLink("/w/$ws/s/$st/screen/desktop/"))
        assertEquals("$ws/$st" to "a+b", screenOfLink("http://127.0.0.1:8877/w/$ws/s/$st/screen/a+b"))
    }

    @Test fun anyOtherLinkNamesNone() {
        assertNull(screenOfLink("https://app.still.fail/w/$ws/s/$st"))
        assertNull(screenOfLink("https://app.still.fail/w/$ws/s/$st/screen/desktop?x=1"))
        assertNull(screenOfLink("https://app.still.fail/w/$ws/s/$st/screen/desktop/more"))
        assertNull(screenOfLink("https://example.com/docs/w/$ws/s/$st/screen/desktop"))
        assertNull(screenOfLink("https://app.still.fail/w/$ws/s/$st/screen/%E0%A4"))
    }

    @Test fun aStationsDebugSharingPageNamesItsStation() {
        assertEquals("$ws/$st", adbOfLink("https://app.still.fail/w/$ws/s/$st/adb"))
        assertEquals("$ws/$st", adbOfLink("/w/$ws/s/$st/adb/"))
        assertNull(adbOfLink("https://app.still.fail/w/$ws/s/$st/adb/more"))
        assertNull(adbOfLink("https://app.still.fail/w/$ws/s/$st/adb?x=1"))
        assertNull(adbOfLink("https://example.com/docs/w/$ws/s/$st/adb"))
        assertTrue(isCardLink("https://app.still.fail/w/$ws/s/$st/adb"))
        assertFalse(isCardLink("https://app.still.fail/w/$ws/s/$st"))
    }

    @Test fun aLinkIsBareWhenItsWordsAreItsAddress() {
        val href = "https://app.still.fail/w/$ws/s/$st/screen/browser%3AD4"
        assertTrue(isBareLink(href, href))
        assertTrue(isBareLink(" https://app.still.fail/w/$ws/s/$st/screen/browser:D4 ", href))
        assertFalse(isBareLink("Bob 的浏览器", href))
    }
}
