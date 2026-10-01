package fail.still.android.data

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class OperationsTest {
    @Test fun omittedFieldsAndExplicitNullHaveDifferentMeanings() = runBlocking {
        val sent = mutableListOf<Pair<String, JsonObject>>()
        val ops = StationOperations { name, params -> sent += name to params; JsonNull }
        val model = "gpt-6-astra"
        ops.sessionSettings("chat") { this.model = model; profile = null }
        assertEquals("session.settings", sent[0].first)
        assertEquals(JsonPrimitive(model), sent[0].second["model"])
        assertEquals(JsonNull, sent[0].second["profile"])
        assertFalse(sent[0].second.containsKey("effort"))
        ops.connectBindSession("c") { session = null }
        assertEquals(JsonNull, sent[1].second["session"])
        assertFalse(sent[1].second.containsKey("title"))
        val state = "oauth-state"
        ops.slackInstalled { code = "code"; this.state = state }
        assertEquals(JsonPrimitive(state), sent[2].second["state"])
    }
    @Test fun cloudBindingsKeepTargetIdentitiesAndLists() = runBlocking {
        var sent = JsonObject(emptyMap())
        val ops = CloudOperations { name, params -> assertEquals("workspace.addMembers", name); sent = params; JsonNull }
        val emails = listOf("one@x.test", "two@x.test")
        ops.workspaceAddMembers("w") { role = "member"; this.emails = emails }
        assertEquals(JsonPrimitive("w"), sent["workspace"])
        assertEquals(JsonArray(emails.map(::JsonPrimitive)), sent["emails"])
    }
}
