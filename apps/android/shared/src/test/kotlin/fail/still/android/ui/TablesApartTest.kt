package fail.still.android.ui

import org.commonmark.ext.gfm.tables.TableBlock
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TablesApartTest {
    @Test fun aTableRightAfterAParagraphLineGetsABlankLineBefore() {
        assertEquals("**这些**\n\n| a | b |\n|---|---|\n| 1 | 2 |", tablesApart("**这些**\n| a | b |\n|---|---|\n| 1 | 2 |"))
    }

    @Test fun aTableAlreadyApartIsLeftAlone() {
        val text = "这些\n\n| a | b |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |"
        assertEquals(text, tablesApart(text))
    }

    @Test fun nothingChangesInFencedCode() {
        val text = "```\nx\n| a | b |\n|---|---|\n```"
        assertEquals(text, tablesApart(text))
    }

    @Test fun aLineWithPipesThatIsNoTableIsLeftAlone() {
        val text = "用 a | b 管道\n| 不是表 |\n下一行"
        assertEquals(text, tablesApart(text))
    }

    @Test fun aParsedMessageHasTheTableRightAfterAParagraphLine() {
        val doc = parseMarkdown("**录制 60 秒**：\n| | 改前 | 改后 |\n|---|---|---|\n| 帧率 | 58.5 | 58.8 |")
        assertTrue(generateSequence(doc.firstChild) { it.next }.any { it is TableBlock })
    }
}
