package fail.still.android.motion

import fail.still.android.data.*
import fail.still.core.applyDelta
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class ChatDecoderTest {
    private val original = StillFailJson.encodeToJsonElement(ChatView.serializer(), Fixtures.chat(Fixtures.talk))
    private fun change(value: JsonElement, operations: String) = applyDelta(value, Json.parseToJsonElement(operations).jsonArray)

    @Test fun metadataKeepsAllMessagesAndAnEditOnlyReplacesItsMessage() {
        val decoder = ChatDecoder()
        val first = decoder.read(original)
        val title = change(original, """[{"path":["title"],"set":"new title"}]""")
        val renamed = decoder.read(title)
        assertEquals("new title", renamed.title)
        assertSame(first.messages, renamed.messages)
        val edited = decoder.read(change(title, """[{"path":["messages",1,"text"],"set":"edited"}]"""))
        assertSame(first.messages[0], edited.messages[0])
        assertNotSame(first.messages[1], edited.messages[1])
        assertEquals("edited", edited.messages[1].text)
        assertSame(first.messages[2], edited.messages[2])
    }

    @Test fun appendAndWindowReplacementMatchFullDecoder() {
        val decoder = ChatDecoder()
        val before = decoder.read(original)
        val message = StillFailJson.encodeToJsonElement(ChatMessage.serializer(), Fixtures.agent(5, "added"))
        val appended = change(original, """[{"path":["messages"],"append":[$message]}]""")
        val after = decoder.read(appended)
        assertEquals(decode(ChatView.serializer(), appended), after)
        assertSame(before.messages[0], after.messages[0])
        val window = JsonObject(appended.jsonObject + ("messages" to JsonArray(appended.jsonObject.getValue("messages").jsonArray.drop(3))))
        val short = decoder.read(window)
        assertEquals(decode(ChatView.serializer(), window), short)
        assertSame(after.messages[3], short.messages[0])
    }

    @Test fun malformedUpdateDoesNotDamageLastGoodValue() {
        val decoder = ChatDecoder()
        val before = decoder.read(original)
        try {
            decoder.read(change(original, """[{"path":["messages",1,"seq"],"set":"wrong"}]"""))
            fail("invalid message accepted")
        } catch (_: fail.still.core.CoreException) { }
        assertSame(before.messages, decoder.read(original).messages)
    }
}
