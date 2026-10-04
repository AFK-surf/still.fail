package fail.still.android.ui

import org.junit.Assert.assertEquals
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
}
