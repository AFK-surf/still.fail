package fail.still.android.screens

import org.junit.Assert.*
import org.junit.Test

class PastedTextTest {
    @Test fun itsPreviewIsItsFirstLineAsWebHasIt() {
        assertEquals("first line", PastedText("\n  first line\r\nsecond").preview)
        assertEquals(200, PastedText("x".repeat(6000)).preview.length)
    }

    @Test fun putBackOnlyWhenNotTooLong() {
        assertTrue(PastedText("x".repeat(PASTE_RESTORE_LIMIT)).restorable)
        assertFalse(PastedText("x".repeat(PASTE_RESTORE_LIMIT + 1)).restorable)
    }

    @Test fun itGoesAsAUtf8TextFile() {
        val picked = pastedPicked(PastedText("会".repeat(3)))
        assertTrue(Regex("pasted-text-[0-9a-f-]{36}\.txt").matches(picked.name))
        assertEquals(9L, picked.size)
        assertNull(picked.preview)
    }
}
