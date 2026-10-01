// Screens read the core's topics as typed values: a topic's JSON is decoded
// here, with the shapes of the area files (Chats.kt, Stations.kt, Chat.kt,
// Accounts.kt), so a changed shape is fixed in one place.
package fail.still.android.data

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import fail.still.core.TopicState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.conflate
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.serializer

// What the core sends has its shape (Shapes.kt, generated from client/shapes): a value that does not fit is an error,
// never a default put in its place. still.fail cloud's topics are not shaped yet: what they add is passed over.
val StillFailJson = Json { ignoreUnknownKeys = true; explicitNulls = false }

/** A topic's value as a screen sees it: the value (kept through a later error), why it failed, whether it is still coming. */
data class Topic<T>(val value: T?, val error: CoreException?, val loading: Boolean)

/** The core sends every number as a float (1790000000000.0); whole ones become integers, so they decode into Int and Long. */
private fun whole(json: JsonElement): JsonElement = when (json) {
    is JsonObject -> JsonObject(json.mapValues { whole(it.value) })
    is JsonArray -> JsonArray(json.map(::whole))
    is JsonPrimitive -> {
        val d = if (json.isString) null else json.content.toDoubleOrNull()
        if (d != null && d == Math.floor(d) && !d.isInfinite() && Math.abs(d) < 9.0e15 && (json.content.contains('.') || json.content.contains('e', ignoreCase = true))) JsonPrimitive(d.toLong()) else json
    }
}

fun <T> decode(serializer: KSerializer<T>, json: JsonElement): T = try {
    StillFailJson.decodeFromJsonElement(serializer, whole(json))
} catch (e: IllegalArgumentException) {
    throw CoreException("decode", "读不懂 core 给的数据：${e.message?.take(200)}", null)
}

/** A topic's states, decoded: what both ways of following one below read. */
private fun <T> follow(core: StillFailCore, topic: JsonObject, serializer: KSerializer<T>): Flow<Topic<T>> {
    val chat = if (serializer.descriptor == ChatView.serializer().descriptor) ChatDecoder() else null
    return core.topic(topic).conflate().map<TopicState, Topic<T>> { state ->
        try {
            @Suppress("UNCHECKED_CAST")
            Topic(state.value?.takeIf { it !is JsonNull }?.let { if (chat != null) chat.read(it) as T else decode(serializer, it) }, state.error, state.loading)
        } catch (e: CoreException) {
            // What this app cannot read is its bug or the core's: recorded with the rest of the trace, not only shown.
            core.reportError("android.decode", "${topic["topic"]}: ${e.message}")
            Topic(null, e, false)
        }
    }
        // Decoding a whole value (a chat is all its messages) is work: off the main thread, and only the latest
        // when several come at once (a chat being fetched arrives in batches).
        .flowOn(Dispatchers.Default)
        .conflate()
}

/** The next state as shown: a value is kept through a later error. */
private fun <T> Topic<T>.after(next: Topic<T>): Topic<T> = if (next.value == null && next.error != null) next.copy(value = value) else next

/**
 * The topics a page of the stack follows, kept while the page is in the stack rather than only while it is drawn
 * (App.kt): coming back to it, what it shows is there at once, not gone and coming in again (its list's rows, so it
 * keeps its place; what grows in above them). Following one in the core costs next to nothing. One the page stops
 * reading while drawn (a search's query typed on) is let go.
 */
class PageTopics {
    private companion object { const val UNREAD_MS = 10_000L }

    private class Followed(val state: State<Topic<*>>, val job: Job) { var readers = 0 }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val followed = HashMap<Pair<JsonObject, SerialDescriptor>, Followed>()
    /** Whether the page is drawn now (App.kt). */
    var drawn = false

    @Suppress("UNCHECKED_CAST")
    fun <T> of(core: StillFailCore, topic: JsonObject, serializer: KSerializer<T>): State<Topic<T>> =
        followed.getOrPut(topic to serializer.descriptor) {
            val state = mutableStateOf(Topic<T>(null, null, true))
            val job = scope.launch { follow(core, topic, serializer).collect { state.value = state.value.after(it) } }
            Followed(state as State<Topic<*>>, job)
        }.state as State<Topic<T>>

    fun read(topic: JsonObject, serializer: KSerializer<*>) { followed[topic to serializer.descriptor]?.let { it.readers++ } }

    /**
     * No longer read: let go a while later if still not read and the page still drawn, so not when what stopped reading
     * it is the page itself going, nor a row of its list scrolled out and back.
     */
    fun unread(topic: JsonObject, serializer: KSerializer<*>) {
        val key = topic to serializer.descriptor
        val it = followed[key] ?: return
        if (--it.readers > 0) return
        scope.launch {
            delay(UNREAD_MS)
            if (drawn && it.readers == 0 && followed[key] === it) followed.remove(key)?.job?.cancel()
        }
    }

    /** The page left the stack: its topics are let go. */
    fun close() = scope.cancel()
}

/** The page being drawn's topics (App.kt), or none outside the stack's pages. */
val LocalPageTopics = staticCompositionLocalOf<PageTopics?> { null }

/** Follows `topic` (null: nothing): on a page of the stack while the page is in it (PageTopics), else while in composition. */
@Composable
fun <T> rememberTopic(core: StillFailCore, topic: JsonObject?, serializer: KSerializer<T>): State<Topic<T>> {
    val page = LocalPageTopics.current
    if (page != null && topic != null) {
        val state = remember(page, core, topic) { page.of(core, topic, serializer) }
        DisposableEffect(page, topic) {
            page.read(topic, serializer)
            onDispose { page.unread(topic, serializer) }
        }
        return state
    }
    return produceState(Topic<T>(null, null, topic != null), core, topic) {
        if (topic == null) return@produceState
        follow(core, topic, serializer).collect { value = value.after(it) }
    }
}

@Composable
inline fun <reified T> rememberTopic(core: StillFailCore, topic: JsonObject?): State<Topic<T>> = rememberTopic(core, topic, serializer<T>())

object Topics {
    val accounts = buildJsonObject { put("topic", "accounts") }
    val workspaces = buildJsonObject { put("topic", "workspaces") }
    /** A scope's chat list: all, the viewer's (`mine`), or the watching ones (`watching`). */
    fun chats(scope: String, mine: Boolean, watching: Boolean = false) = buildJsonObject {
        put("topic", "chats"); put("scope", scope); put("mine", mine); if (watching) put("watching", true)
    }
    fun stations(scope: String) = buildJsonObject { put("topic", "stations"); put("scope", scope) }
    /** The archived chats of a scope's stations online, newest first by the day archived (client/core/src/views/archive.rs). */
    fun archive(scope: String) = buildJsonObject { put("topic", "archive"); put("scope", scope) }
    fun connects(scope: String, mine: Boolean) = buildJsonObject { put("topic", "connects"); put("scope", scope); put("mine", mine) }
    fun workspace(id: String) = buildJsonObject { put("topic", "workspace"); put("workspace", id) }
    fun loginSessions(account: String) = buildJsonObject { put("topic", "loginSessions"); put("account", account) }
    fun overview(station: String) = buildJsonObject { put("topic", "overview"); put("station", station) }
    fun host(station: String) = buildJsonObject { put("topic", "host"); put("station", station) }
    /** An item's page: its chat, or its agent before it has one. */
    fun chat(station: String, of: ChatOf) = buildJsonObject {
        put("topic", "chat"); put("station", station)
        when (of) { is ChatOf.Thread -> put("thread", of.id); is ChatOf.Session -> put("session", of.key) }
    }
    fun live(station: String, key: String) = buildJsonObject { put("topic", "live"); put("station", station); put("key", key) }
    /** An agent's execution history, read for people (the core's). */
    fun history(station: String, key: String) = buildJsonObject { put("topic", "history"); put("station", station); put("key", key) }
    /** A chat's services and background jobs as its pages show them (the same `of` as its `chat`; Jobs.kt). */
    fun chatJobs(station: String, of: ChatOf) = buildJsonObject {
        put("topic", "chatJobs"); put("station", station)
        when (of) { is ChatOf.Thread -> put("thread", of.id); is ChatOf.Session -> put("session", of.key) }
    }
    /** The services and jobs left up a long while on the scope's stations that are up (OpenJobs.kt). */
    fun longJobs(scope: String) = buildJsonObject { put("topic", "longJobs"); put("scope", scope) }
    /** What the agents of a scope's stations spent over its last `days` (7 or 30): client/core/src/views/usage.rs. */
    fun usage(scope: String, days: Int) = buildJsonObject { put("topic", "usage"); put("scope", scope); put("days", days) }
    /** A job as it is now (kept current by the core). */
    fun job(station: String, id: String) = buildJsonObject { put("topic", "job"); put("station", station); put("id", id) }
    /** A job's last `lines` lines of output and when it last grew, current as it grows. */
    fun jobLog(station: String, job: String, lines: Int) = buildJsonObject { put("topic", "jobLog"); put("station", station); put("job", job); put("lines", lines) }
    /**
     * What the core has been waiting on for a while (a slow request, a link down), said under a page's "loading…": a
     * workspace's (its stations, its account's socket, the relay), nothing of another; with none, all of it.
     */
    fun status(workspace: String? = null) = buildJsonObject { put("topic", "status"); workspace?.let { put("workspace", it) } }
    /** What wants the viewer in the chats they take part in, the last 20 (docs/notifications.md; Notices.kt). */
    val notices = buildJsonObject { put("topic", "notices") }
    /**
     * Notifications on this device: on or off, asked, whether to hold pushes, what to show now (attend.rs; Notices.kt),
     * only `workspace`'s if given.
     */
    fun notify(workspace: String? = null) = buildJsonObject { put("topic", "notify"); workspace?.let { put("workspace", it) } }
    /** How its person likes it on this device, and what the device is (Prefs.kt). */
    val prefs = buildJsonObject { put("topic", "prefs") }
    /** What people set going here and the core has not finished, until it answers (client/core/src/doing.rs; AppState.isDoing). */
    val doing = buildJsonObject { put("topic", "doing") }
    /** The decisions waiting for the viewer in a workspace's chats, one at a time on its page (client/core/src/decisions.rs; Decisions.kt). */
    fun decisions(workspace: String) = buildJsonObject { put("topic", "decisions"); put("workspace", workspace) }
    /** What changed in still.fail, as this app shows it, and what an update brought until `changelog.seen` (Changelog.kt). */
    val changelog = buildJsonObject { put("topic", "changelog") }
    /**
     * What each workspace has waiting (how many chats want their person, how many are unread) and the chat last open in
     * it; of those other than `workspace` (the one in view), the most urgent (client/core/src/views/marks.rs).
     */
    fun workspaceMarks(workspace: String) = buildJsonObject { put("topic", "workspaceMarks"); put("workspace", workspace) }
    /** What is written to a chat on this device until sent (`chat`: its key, `thread:<id>`, or `new`; Drafts). */
    fun draft(station: String, chat: String) = buildJsonObject { put("topic", "draft"); put("station", station); put("chat", chat) }
    /** The chats of a scope a few words find, titles first: only `station`'s, not `exclude` (a chat's id or agent), `limit` at most (ChatRefMenu). */
    fun chatSearch(scope: String, query: String, station: String? = null, exclude: String? = null, limit: Int? = null) = buildJsonObject {
        put("topic", "chatSearch"); put("scope", scope); put("query", query)
        station?.let { put("station", it) }; exclude?.let { put("exclude", it) }; limit?.let { put("limit", it) }
    }
    /** A new chat's page in a scope: its stations, the one it starts on and what it runs there, as last picked here (web/src/pick.ts). */
    fun newChat(scope: String) = buildJsonObject { put("topic", "newChat"); put("scope", scope) }
    /** A model control: what it runs on now and what its panel picked (`of`: new, session:<key>, connect:<id>, connect-new). */
    fun pick(station: String, of: String) = buildJsonObject { put("topic", "pick"); put("station", station); put("of", of) }

    /** A connect's Slack app as Slack has it (read through the station; again after a write to the connect). */
    fun slackApp(station: String, connect: String) = buildJsonObject { put("topic", "slackApp"); put("station", station); put("connect", connect) }
}

/** What an item's page is of: its chat's thread, or its agent's session while it has no chat. */
sealed interface ChatOf {
    data class Thread(val id: Long) : ChatOf
    data class Session(val key: String) : ChatOf
}

/** A row's page. */
/** A row's page: its agent's, chat or no chat (the core shows the chat once there is one). */
val ChatItem.page: ChatOf get() = ChatOf.Session(session)
