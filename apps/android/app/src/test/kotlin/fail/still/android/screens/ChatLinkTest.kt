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
}
