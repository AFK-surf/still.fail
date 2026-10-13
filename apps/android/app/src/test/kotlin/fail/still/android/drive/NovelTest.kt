package fail.still.android.drive

import java.nio.charset.Charset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NovelTest {
    /** A novel as such files come: GBK, hard-wrapped at a fixed width, 第X章 headings. */
    private fun novel(): String {
        val para = "他站在山顶上看着远处的城市，灯火一盏一盏地亮起来，风从谷底吹上来，带着潮湿的草木气味和一点点烟火的味道，让人想起很久以前的某个夏天。"
        fun wrapped(p: String) = p.chunked(30).joinToString("\n")
        return (1..5).joinToString("\n") { n -> "第${n}章 山顶\n" + (1..4).joinToString("\n") { "　　" + wrapped(para) } }
    }

    @Test
    fun gbkIsDecodedReflowedAndItsChaptersFound() {
        val bytes = novel().toByteArray(Charset.forName("GBK"))
        val n = buildNovel("山顶.txt", bytes, bytes.size.toLong(), truncated = false)
        assertEquals("GB18030", n.encoding)
        assertEquals((1..5).map { "第${it}章 山顶" }, n.chapters.map { it.title })
        val text = n.chunks.joinToString("")
        // The lines broken at 30 are one paragraph again.
        assertTrue(text.contains("灯火一盏一盏地亮起来，风从谷底吹上来"))
        assertEquals(text.length, n.length)
    }

    @Test
    fun utf8StaysUtf8() {
        val bytes = novel().toByteArray(Charsets.UTF_8)
        val n = buildNovel("山顶.txt", bytes, bytes.size.toLong(), truncated = false)
        assertEquals("UTF-8", n.encoding)
        assertEquals(5, n.chapters.size)
    }

    @Test
    fun aPlaceIsAnOffsetOfTheTextShown() {
        val bytes = novel().toByteArray(Charsets.UTF_8)
        val n = buildNovel("山顶.txt", bytes, bytes.size.toLong(), truncated = false)
        val at = n.length * 2 / 3
        val (chunk, offset) = n.at(at)
        assertEquals(at, n.starts[chunk] + offset)
        assertEquals(n.starts[chunk], n.offsetOf(chunk, 0f))
    }

    @Test
    fun markdownHeadingsAreItsChapters() {
        val md = "# 一\n\n正文\n\n## 二\n\n- 列表\n\n# 三\n".toByteArray()
        val n = buildNovel("notes.md", md, md.size.toLong(), truncated = false)
        assertTrue(n.markdown)
        assertEquals(listOf("一", "二", "三"), n.chapters.map { it.title })
    }

    @Test
    fun aTakenNameGetsANumber() {
        assertEquals("a.txt", freeName("a.txt", setOf("b.txt")))
        assertEquals("a (1).txt", freeName("a.txt", setOf("a.txt")))
        assertEquals("a (2).txt", freeName("a.txt", setOf("a.txt", "a (1).txt")))
        assertEquals("Makefile (1)", freeName("Makefile", setOf("Makefile")))
    }
}
