package fail.still.android.screens

import org.junit.Assert.*
import org.junit.Test

class ChatLinkTest {
    @Test fun aWorkspaceChatLinksToItsSessionAsWebDoes() {
        assertEquals("https://app.still.fail/o/ws-1/mac/ember%3Ac-e4ea3b1439", chatLink("https://app.still.fail/", "ws-1/mac", "ember:c-e4ea3b1439"))
    }

    @Test fun noLinkWithoutAWorkspaceOrASession() {
        assertNull(chatLink("https://app.still.fail", "mac", "ember:c-1"))
        assertNull(chatLink("https://app.still.fail", "ws-1/", "ember:c-1"))
        assertNull(chatLink("https://app.still.fail", "ws-1/mac", ""))
    }

    @Test fun encodedAsEncodeURIComponent() {
        assertEquals("a%20b!'()*~-_.%2F%3F%26%E4%BC%9A", encodeComponent("a b!'()*~-_./?&会"))
    }

    @Test fun theTextIsAReferenceWithItsTitleOnALine() {
        assertEquals("登录页  bug" to "[登录页  bug](L)", chatLinkText("登录页 [bug]\n", "L"))
        assertEquals("[L](L)", chatLinkText(" ", "L").second)
        assertEquals(120, chatLinkText("长".repeat(200), "L").first.length)
    }

    @Test fun aLinkNamesItsChatAsWebReadsIt() {
        assertEquals(LinkedChat("ws/st", "ember:c-798ee48925", ""), chatOfLink("https://app.still.fail/o/ws/st/ember%3Ac-798ee48925"))
        assertEquals(LinkedChat("ws/st", "a b", "?history=k&entry=3"), chatOfLink("https://x/w/ws/s/st/chats/a%20b?history=k&entry=3"))
        assertNull(chatOfLink("https://github.com/o/r"))
        assertNull(chatOfLink("https://x/o/ws/st/%E4%"))
    }

    @Test fun aPastedLinkIsAReferenceOnlyInItsWorkspace() {
        val text = "看 [ScreenCam Win UI 粗糙点排查](https://app.still.fail/o/ws/st/ember%3Ac-1) 和 [别处](https://app.still.fail/o/other/st/ember%3Ac-2) [gh](https://github.com/a/b)"
        val refs = linkedRefs(text, "ws/here")
        assertEquals(listOf("ScreenCam Win UI 粗糙点排查"), refs.map { it.first.groupValues[1] })
        assertEquals(LinkedChat("ws/st", "ember:c-1", ""), refs[0].second)
        assertTrue(linkedRefs(text, "here").isEmpty())
    }

    @Test fun whatAChangePutIn() {
        assertEquals(2..4, insertedRange("abcd", "abXYZcd"))
        assertEquals(0..2, insertedRange("", "abc"))
        assertEquals(1..2, insertedRange("aXb", "aYZb"))
        assertNull(insertedRange("abc", "ac"))
        assertNull(insertedRange("abc", "abc"))
    }
}
