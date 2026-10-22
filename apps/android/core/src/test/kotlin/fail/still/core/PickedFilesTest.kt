package fail.still.core

import java.io.ByteArrayInputStream
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class PickedFilesTest {
    private val bytes = ByteArray(10) { it.toByte() }

    @Test fun parts_come_in_order_from_one_stream_and_again_from_the_start() {
        var opened = 0
        val file = PickedFiles.hold(bytes.size.toLong()) { opened++; ByteArrayInputStream(bytes) }
        assertArrayEquals(bytes.copyOfRange(0, 4), PickedFiles.answer("picked.read", """{"file":$file,"start":0,"end":4}""").second)
        assertArrayEquals(bytes.copyOfRange(4, 10), PickedFiles.answer("picked.read", """{"file":$file,"start":4,"end":99}""").second)
        assertEquals(1, opened)
        // Sent again (a retry): from its start, opened anew.
        assertArrayEquals(bytes.copyOfRange(0, 3), PickedFiles.answer("picked.read", """{"file":$file,"start":0,"end":3}""").second)
        // Asked from elsewhere (the station has more than was read here): skipped to there.
        assertArrayEquals(bytes.copyOfRange(7, 10), PickedFiles.answer("picked.read", """{"file":$file,"start":7,"end":10}""").second)
        assertEquals(3, opened)
        // Named by its content, as a station names what it keeps.
        assertEquals("""{"sha256":"1f825aa2f0020ef7cf91dfa30da4668d791c5d4824fc8e41354b89ec05795ab3"}""", PickedFiles.answer("picked.hash", """{"file":$file}""").first)
        assertNull(PickedFiles.answer("picked.release", """{"file":$file}""").second)
        try {
            PickedFiles.answer("picked.read", """{"file":$file,"start":0,"end":4}""")
            fail("a file let go is read no more")
        } catch (_: IllegalStateException) {}
    }
}
