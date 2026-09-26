// The `chats` view (docs/client-core.md → Views): the home inbox. Shapes follow
// web/src/api.ts (ChatsView) and src/admin/types.ts (SessionSummary).
package dev.ember.android.data

import kotlinx.serialization.Serializable

@Serializable data class Me(val id: String, val email: String? = null)

@Serializable data class Creator(val id: String, val name: String, val email: String? = null, val via: String = "cloud")

@Serializable data class TurnSummary(
    val kind: String = "", val outcome: String? = null, val declared: String? = null, val detail: String? = null,
    val startedAt: Long = 0, val endedAt: Long? = null,
)

@Serializable data class SessionSummary(
    val key: String,
    val connect: String = "",
    val title: String? = null,
    val createdBy: String? = null,
    val creator: Creator? = null,
    val participants: List<Creator> = emptyList(),
    val channel: String = "",
    val threadTs: String = "",
    val runtime: String = "claude",
    val profile: String = "",
    val model: String? = null,
    val effort: String? = null,
    val running: Boolean = false,
    val createdAt: Long = 0,
    val lastActiveAt: Long = 0,
    val process: String = "cold",
    val pending: Int = 0,
    val firstText: String? = null,
    val lastTurn: TurnSummary? = null,
)

/** An agent of a chat's thread (docs/station-storage.md: a thread has any number of sessions). */
@Serializable data class AgentRef(val key: String, val model: String? = null, val runtime: String = "claude")

@Serializable data class ChatItem(
    val station: String,
    val stationName: String,
    val session: SessionSummary,
    val connect: ConnectView? = null,
    /** Messages after the viewer's read position, not their own. */
    val unread: Int = 0,
    // Not in the view yet (docs/station-storage.md has both on threads): the thread's agents, and its
    // last message, whose text is the question when an agent blocked. Without them a chat is its one session.
    val agents: List<AgentRef> = emptyList(),
    val last: MessageView? = null,
) {
    val models: List<String?> get() = agents.map { it.model }.ifEmpty { listOf(session.model) }
}

@Serializable data class ChatDay(val daysAgo: Int, val at: Long, val items: List<ChatItem> = emptyList())

@Serializable data class StationState(val station: String, val id: String, val name: String, val state: String, val message: String? = null)

@Serializable data class ChatsView(
    val me: Me,
    val stations: List<StationState> = emptyList(),
    val loading: Boolean = false,
    val days: List<ChatDay> = emptyList(),
)

/** Where a chat stands, as its badge shows it. */
enum class ChatState { Block, Running, Done, Failed }

fun SessionSummary.state(): ChatState = when (status(this)) {
    Status.Running, Status.Queued -> ChatState.Running
    Status.Block -> ChatState.Block
    Status.Failed, Status.Unexpected -> ChatState.Failed
    else -> ChatState.Done
}

fun Me.isMe(c: Creator?): Boolean = c != null && (c.id == id || (email != null && c.email.equals(email, ignoreCase = true)))

/**
 * The phone's inbox: chats where an agent is blocked first, then running
 * ones, then the rest by day. The view is already sorted newest first.
 */
data class Inbox(val needs: List<ChatItem>, val running: List<ChatItem>, val rest: List<Pair<ChatDay, List<ChatItem>>>)

fun ChatsView.inbox(): Inbox {
    val all = days.flatMap { it.items }
    val rest = days.map { day -> day to day.items.filter { it.session.state() == ChatState.Done || it.session.state() == ChatState.Failed } }.filter { it.second.isNotEmpty() }
    return Inbox(all.filter { it.session.state() == ChatState.Block }, all.filter { it.session.state() == ChatState.Running }, rest)
}
