package fail.still.android.drive

import org.junit.Assert.assertEquals
import org.junit.Test

class RenderIndentTest {
    private val chunk = "　　第一段。\n  第二段\t。\n\n　\n第四段"

    @Test
    fun existingSpacingIsReplacedNotDoubled() {
        assertEquals(
            "${INDENT}第一段。\n${INDENT}第二段\t。\n\n\n${INDENT}第四段",
            renderChunk(chunk, indent = true),
        )
    }

    @Test
    fun headingsAreNotIndented() {
        val text = "\u3000\u3000第12章 红岸\n\u3000\u3000正文。"
        val rendered = renderChunk(text, indent = true)
        assertEquals("第12章 红岸\n${INDENT}正文。", rendered)
        text.forEachIndexed { raw, c ->
            if (c == '\u3000' || c == '\n' || c == ' ') return@forEachIndexed
            assertEquals("raw $raw", c, rendered[renderOffset(text, raw, indent = true)])
        }
    }

    @Test
    fun withoutIndentTheTextIsUntouched() {
        assertEquals(chunk, renderChunk(chunk, indent = false))
    }

    /** Search hits are raw offsets: every visible character must map onto itself. */
    @Test
    fun offsetsLandOnTheSameCharacter() {
        val rendered = renderChunk(chunk, indent = true)
        chunk.forEachIndexed { raw, c ->
            if (c == ' ' || c == '　' || c == '\n') return@forEachIndexed
            // A tab inside a paragraph is text, not leading spacing.
            assertEquals("raw $raw", c, rendered[renderOffset(chunk, raw, indent = true)])
        }
        assertEquals(rendered.length, renderOffset(chunk, chunk.length, indent = true))
    }

    @Test
    fun anOffsetInsideLeadingSpacingLandsOnTheParagraphText() {
        val rendered = renderChunk(chunk, indent = true)
        assertEquals('第', rendered[renderOffset(chunk, 1, indent = true)])
    }
}
