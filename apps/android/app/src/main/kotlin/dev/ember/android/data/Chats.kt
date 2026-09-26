// The `chats` view (docs/client-core.md → Views): the home list, every
// station's rows side by side, grouped by day. Shapes follow web/src/api.ts
// (ChatsView) and src/admin/types.ts (ChatRow, SessionSummary).
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
    val runtime: String = "claude",
    val profile: String = "",
    val model: String? = null,
    val effort: String? = null,
    val runtimeSessionId: String? = null,
    /** Where its files are kept on the station. */
    val workspace: String = "",
    val running: Boolean = false,
    val createdAt: Long = 0,
    val lastActiveAt: Long = 0,
    val process: String = "cold",
    val pending: Int = 0,
    val firstText: String? = null,
    val lastTurn: TurnSummary? = null,
)

/** An agent of a row: what it runs on and where its work stands. */
@Serializable data class RowAgent(
    val key: String,
    val runtime: String = "claude",
    val model: String? = null,
    val effort: String? = null,
    val process: String = "cold",
    val pending: Int = 0,
    val lastTurn: TurnSummary? = null,
)

/** A row's last message, its text cut to 200 characters. */
@Serializable data class RowMessage(
    val seq: Long = 0,
    /** person | agent | ember */
    val authorKind: String,
    val author: String,
    val authorName: String? = null,
    val text: String = "",
    val createdAt: Long = 0,
)

/** The Slack thread a row's agent came from. */
@Serializable data class Origin(val teamName: String? = null, val channel: String = "", val channelName: String? = null, val threadTs: String = "")

/**
 * An item of the home list, as its station puts it together for the viewer:
 * an agent merged with its internal chat, or an agent that has no chat yet.
 */
@Serializable data class ChatItem(
    val station: String,
    val stationName: String,
    /** Where its page is: its chat's thread id, or its session's key while it has no chat. */
    val id: String,
    /** Its agent (the first of its chat's). */
    val session: String,
    /** Its internal chat; null until the first message makes it. */
    val thread: Long? = null,
    val title: String,
    val agents: List<RowAgent> = emptyList(),
    val last: RowMessage? = null,
    val unread: Boolean = false,
    val mine: Boolean = false,
    val lastActiveAt: Long = 0,
    /** The connect its agent came from; null for one made on ember. */
    val connect: String? = null,
    val origin: Origin? = null,
)

@Serializable data class ChatDay(val daysAgo: Int, val at: Long, val items: List<ChatItem> = emptyList())

@Serializable data class StationState(val station: String, val id: String, val name: String, val state: String, val message: String? = null)

@Serializable data class ChatsView(
    val me: Me,
    val stations: List<StationState> = emptyList(),
    /** An online station has not answered its rows yet. */
    val loading: Boolean = false,
    val days: List<ChatDay> = emptyList(),
)

/** Where an agent stands, as its badge shows it: solid orange block, hollow ring at work, red failed; done has none. */
enum class ChatState { Block, Running, Done, Failed }

fun agentState(process: String, pending: Int, lastTurn: TurnSummary?): ChatState = when (status(process, pending, lastTurn)) {
    Status.Running, Status.Queued -> ChatState.Running
    Status.Block -> ChatState.Block
    Status.Failed, Status.Unexpected -> ChatState.Failed
    else -> ChatState.Done
}

fun SessionSummary.state(): ChatState = agentState(process, pending, lastTurn)
fun RowAgent.state(): ChatState = agentState(process, pending, lastTurn)

/** A row's badge, from its agents': one that is blocked comes first, then one at work, then one that failed. */
fun ChatItem.state(): ChatState {
    val states = agents.map { it.state() }.toSet()
    return listOf(ChatState.Block, ChatState.Running, ChatState.Failed).firstOrNull { it in states } ?: ChatState.Done
}

fun Me.isMe(c: Creator?): Boolean = c != null && (c.id == id || (email != null && c.email.equals(email, ignoreCase = true)))

/** Whether a person's id (an email, "local", a Slack user) is the viewer. */
fun Me.isMe(person: String): Boolean = person == id || (email != null && person.equals(email, ignoreCase = true))

/** Where a row's agent came from, for its connect icon: the Slack workspace, then the thread's channel. */
fun ChatItem.originLabel(): String {
    val where = origin?.let { o -> o.channelName?.let { "#$it" } ?: if (o.channel.startsWith("D")) "私信" else null }
    return listOfNotNull("Slack", origin?.teamName, where).joinToString(" · ")
}
