package fail.still.android.data

import java.util.IdentityHashMap
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * One chat subscription's typed messages. The bridge preserves unchanged JSON subtrees when applying deltas;
 * keep that sharing when decoding, too. Only the current window is retained, never every chat visited.
 */
internal class ChatDecoder {
    private var source: JsonArray? = null
    private var messages = emptyList<ChatMessage>()
    private var decoded = IdentityHashMap<JsonElement, ChatMessage>()

    fun read(value: JsonElement): ChatView {
        val body = value as? JsonObject ?: return decode(ChatView.serializer(), value)
        val incoming = body["messages"] as? JsonArray ?: return decode(ChatView.serializer(), value)
        // The generated serializer still validates every field, including all newly added fields. Messages are
        // validated below with their own generated serializer rather than being traversed twice per update.
        val view = decode(ChatView.serializer(), JsonObject(body + ("messages" to JsonArray(emptyList()))))
        if (incoming !== source) {
            val next = IdentityHashMap<JsonElement, ChatMessage>(incoming.size)
            val list = incoming.map { item ->
                (decoded[item] ?: decode(ChatMessage.serializer(), item)).also { next[item] = it }
            }
            // Commit only after the entire value decoded: a malformed update must not poison the cache.
            source = incoming
            decoded = next
            messages = list
        }
        return view.copy(messages = messages)
    }
}
