package fail.still.android.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The same cases as the web's test/bare-links.test.ts: both find the same addresses. */
class LinksTest {
    private fun found(text: String) = bareLinks(text).map { text.substring(it) }

    @Test fun aBareAddressEndsWhereChineseWordsOrFullWidthMarksBegin() {
        assertEquals(listOf(1 until 42), bareLinks("（https://github.com/AFK-surf/Cue/pull/2854）已改到"))
        assertEquals(listOf("https://github.com/AFK-surf/Cue/pull/2854"), found("（https://github.com/AFK-surf/Cue/pull/2854）已改到"))
        assertEquals(listOf("https://github.com/AFK-surf/still.fail/pull/134"), found("PR：https://github.com/AFK-surf/still.fail/pull/134"))
        assertEquals(listOf("https://example.com/a"), found("看下https://example.com/a，再说"))
        assertEquals(listOf("https://x-1.trycloudflare.com"), found("部署好了：https://x-1.trycloudflare.com。"))
        assertEquals(listOf("https://zh.wikipedia.org/wiki/"), found("https://zh.wikipedia.org/wiki/中文"))
    }

    @Test fun theMarksClosingASentenceOrABracketStayOutside() {
        assertEquals(listOf("https://example.com/a"), found("see https://example.com/a."))
        assertEquals(listOf("https://example.com/a"), found("(see https://example.com/a)"))
        assertEquals(listOf("https://en.wikipedia.org/wiki/Foo_(bar)"), found("https://en.wikipedia.org/wiki/Foo_(bar)"))
        assertEquals(listOf("https://en.wikipedia.org/wiki/Foo_(bar)"), found("(https://en.wikipedia.org/wiki/Foo_(bar))"))
        assertEquals(listOf("https://example.com/a"), found("<https://example.com/a>"))
        assertEquals(listOf("https://example.com/a", "https://example.com/b"), found("'https://example.com/a', https://example.com/b!"))
        assertEquals(listOf("https://example.com/docs/deploy?ref=still.fail&tab=android#step-3"), found("https://example.com/docs/deploy?ref=still.fail&tab=android#step-3，打开"))
    }

    @Test fun whatIsNoAddressToOpenStaysWords() {
        for (text in listOf("https://", "https://。", "xhttps://example.com", "https://github.com/…", "www.example.com", "a@b.co", "ftp://example.com", "")) {
            assertEquals(text, emptyList<IntRange>(), bareLinks(text))
        }
        assertEquals(listOf("http://a.io/x", "https://b.io/y"), found("two: http://a.io/x https://b.io/y"))
    }

    @Test fun anAddressAloneInCodeIsOne() {
        assertTrue(isWebAddress("https://example.com/code"))
        assertTrue(isWebAddress("http://localhost:5173/w"))
        assertFalse(isWebAddress("https://github.com/…"))
        assertFalse(isWebAddress("pnpm test https://x.y"))
        assertFalse(isWebAddress("example.com"))
    }
}
