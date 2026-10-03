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

/**
 * One chat list subscription's typed rows: a row whose JSON is the instance it was (a keyed delta touches only the
 * rows that changed, and the bridge keeps the rest) is the `ChatItem` decoded before, so the list redraws only the
 * rows that changed. Only the rows of the current value are retained.
 */
internal class ChatsDecoder {
    private var decoded = IdentityHashMap<JsonElement, ChatItem>()

    fun read(value: JsonElement): ChatsView {
        val body = value as? JsonObject ?: return decode(ChatsView.serializer(), value)
        val days = body["days"] as? JsonArray ?: return decode(ChatsView.serializer(), value)
        // Everything but the rows through the generated serializer (it checks every field); the rows each with theirs.
        val bare = JsonArray(days.map { day -> (day as? JsonObject)?.let { JsonObject(it + ("items" to JsonArray(emptyList()))) } ?: day })
        val view = decode(ChatsView.serializer(), JsonObject(body + ("days" to bare)))
        val next = IdentityHashMap<JsonElement, ChatItem>()
        val filled = view.days.mapIndexed { i, day ->
            val items = ((days[i] as? JsonObject)?.get("items") as? JsonArray).orEmpty()
            day.copy(items = items.map { item -> (decoded[item] ?: decode(ChatItem.serializer(), item)).also { next[item] = it } })
        }
        // Kept only once the whole value decoded: a malformed one must not poison it.
        decoded = next
        return view.copy(days = filled)
    }
}
