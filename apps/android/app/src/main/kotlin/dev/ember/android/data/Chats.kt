// The `chats` view (docs/client-core.md → Views): the home list, every
// station's rows side by side, grouped by day. Shapes follow web/src/api.ts
// (ChatsView) and src/admin/types.ts (ChatRow, SessionSummary).
package dev.ember.android.data

import kotlinx.serialization.Serializable

@Serializable data class Me(val id: String, val email: String? = null)

// ── what the core puts in for the clients to show (client/core/src/present.rs, format.rs) ──

/** A moment in words, fresh each minute: 3 分钟前 (`ago`), 9/20 14:05:09 (`full`), 3 小时后 (`until`), whether it has come. */
@Serializable data class Stamp(val at: Double = 0.0, val ago: String = "", val full: String = "", val until: String = "", val past: Boolean = false)

/** Who made a model, for its mark; null when the marks do not know it (the runtime's stands in). */
@Serializable data class Maker(val id: String, val name: String)

/** A person as the core names them: `display` is 你 for the viewer. */
@Serializable data class PersonShown(val name: String = "", val display: String = "", val picture: String? = null, val mine: Boolean = false)

@Serializable data class Creator(val id: String, val name: String, val email: String? = null, val via: String = "cloud", val shown: PersonShown? = null)

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
    /** Kept to its profile by hand; else the station picks it. */
    val profilePinned: Boolean = false,
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
    // What the core says of it.
    val statusText: String = "",
    /** accent | green | blue | red | neutral */
    val tone: String = "neutral",
    /** Its mark (run | block | failed), and in words. */
    val mark: String? = null,
    val badgeText: String? = null,
    val titleText: String = "",
    val agentText: String = "",
    val maker: Maker? = null,
    val runtimeText: String = "",
    val processText: String? = null,
    /** How hard its runtime can think, lowest first. */
    val efforts: List<String> = emptyList(),
    val time: Map<String, Stamp> = emptyMap(),
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
    val agentText: String = "",
    val maker: Maker? = null,
    val mark: String? = null,
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
    /** Who said it, as the core puts it (client/core/src/present.rs). */
    val by: LastBy? = null,
    /** Its line: without mentions, （文件） for a file alone. */
    val preview: String = "",
)

/** A row's last speaker: kind (agent | person | ember), name, picture; an agent's state (block | run | failed) rides on it. */
@Serializable data class LastBy(
    val kind: String = "person",
    val name: String = "",
    val mine: Boolean = false,
    val model: String? = null,
    val runtime: String = "claude",
    val state: String? = null,
    val id: String? = null,
    val picture: String? = null,
    /** What its picture says when pointed at: who, and an agent's state. */
    val label: String = "",
    val maker: Maker? = null,
)

/** A badge the core names (block | run | failed) as the app's state. */
fun badgeState(badge: String?): ChatState? = when (badge) {
    "block" -> ChatState.Block; "run" -> ChatState.Running; "failed" -> ChatState.Failed; else -> null
}

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
    /** Its state, as the core puts it from its agents: block | run | failed, or none. */
    val state: String? = null,
    /** Where it came from (Slack · workspace · #channel), for a Slack chat. */
    val originText: String? = null,
    val time: Map<String, Stamp> = emptyMap(),
)

/** A day of the list, with its heading (今天, 昨天, 星期三, 9月20日). */
@Serializable data class ChatDay(val daysAgo: Int, val at: Long, val label: String = "", val items: List<ChatItem> = emptyList())

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

fun SessionSummary.state(): ChatState = badgeState(mark) ?: ChatState.Done
fun RowAgent.state(): ChatState = badgeState(mark) ?: ChatState.Done
