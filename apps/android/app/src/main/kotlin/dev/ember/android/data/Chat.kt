// The `chat` and `live` views (docs/client-core.md): an item's page — its
// internal chat (with the viewer's read position), its title, people and
// agents, the messages loaded so far and what this device is still sending —
// and an agent's running turn (transcript, steps in flight, phase). Messages
// are the station's thread messages (src/admin/types.ts → MessageView,
// docs/station-storage.md).
package dev.ember.android.data

import kotlinx.serialization.Serializable

@Serializable data class Attachment(val name: String, val path: String, val size: Long = 0, val width: Int? = null, val height: Int? = null)

@Serializable data class Quote(val author: String, val text: String, val comment: String = "", val ts: String? = null, val role: String? = null)

/** Something said in a thread. */
@Serializable data class MessageView(
    /** Orders the thread; older pages go back by it. */
    val seq: Long,
    val ts: String,
    /** person | agent | ember */
    val authorKind: String,
    /** person: Slack user id, email or "local"; agent: its session key; ember: "ember". */
    val author: String,
    /** Who that is in words, where known. */
    val authorName: String? = null,
    val text: String = "",
    val attachments: List<Attachment> = emptyList(),
    val quotes: List<Quote> = emptyList(),
    /** final or block, when an agent's post ended its work with it. */
    val declared: String? = null,
    val createdAt: Long = 0,
    /** When its latest edit came; null if never edited. */
    val editedAt: Long? = null,
)

@Serializable data class Membership(val session: String, val connect: String = "")

/** A thread: a Slack thread or a chat on ember's page (the page's chat is always the latter). */
@Serializable data class ThreadView(
    val id: Long,
    /** "slack:<team id>" or "ember". */
    val surface: String = "ember",
    val channel: String = "",
    val channelName: String? = null,
    val threadTs: String = "",
    val title: String? = null,
    val creator: Creator? = null,
    val createdAt: Long = 0,
    val sessions: List<Membership> = emptyList(),
    /** Its last entry number, 0 before anything is said. */
    val last: Long = 0,
    val lastMessage: MessageView? = null,
    /** The viewer's read position (an entry number), 0 if never read. */
    val read: Long = 0,
    /** Messages after it, not deleted and not the viewer's own. */
    val unread: Int = 0,
    val people: List<Creator> = emptyList(),
    val firstText: String? = null,
)

@Serializable data class TurnRecord(val id: String, val startedAt: Long = 0, val endedAt: Long? = null, val outcome: String? = null, val declared: String? = null)

/** A message sent from this device that the chat does not show yet; `seq` once the station has it. */
@Serializable data class OutboxItem(
    val id: String,
    val text: String = "",
    val attachments: List<Attachment> = emptyList(),
    val quotes: List<Quote> = emptyList(),
    val createdAt: Long = 0,
    /** sending | failed */
    val state: String = "sending",
    val error: String? = null,
    val seq: Long? = null,
)

/** An agent taking part in a chat: its session, the connect that started it, its profile, its turns and every thread it is in. */
@Serializable data class ChatAgentView(
    val session: SessionSummary,
    val connect: ConnectView? = null,
    val profile: ProfileView? = null,
    val turns: List<TurnRecord> = emptyList(),
    val threads: List<ThreadView> = emptyList(),
)

/** An item's page. Before its agent has a chat, `thread` is null and there is only the agent. */
@Serializable data class ChatView(
    val me: Me,
    val thread: ThreadView? = null,
    val title: String = "",
    val people: List<Creator> = emptyList(),
    val agents: List<ChatAgentView> = emptyList(),
    /** Merged from the entries loaded so far, oldest first; `chat.older` brings earlier ones. */
    val messages: List<MessageView> = emptyList(),
    val more: Boolean = false,
    val outbox: List<OutboxItem> = emptyList(),
    val link: LinkView = LinkView(),
)

@Serializable data class TimelineEntry(
    val at: String? = null,
    /** user | assistant | thinking | tool_call | tool_result */
    val kind: String,
    val text: String = "",
    val tool: String? = null,
    val ok: Boolean? = null,
    val callId: String? = null,
    val subagent: Boolean = false,
)

@Serializable data class TranscriptUsage(val modelCalls: Int = 0, val inputTokens: Long = 0, val cachedTokens: Long = 0, val outputTokens: Long = 0, val model: String? = null)

@Serializable data class LiveStep(
    val id: String,
    /** tool | thinking | text */
    val step: String,
    val tool: String? = null,
    val subagent: Boolean = false,
    /** A tool's input as it started (a command), cut short; what a step writes comes with its entry. */
    val input: String = "",
    val startedAt: Long = 0,
    val ended: Boolean = false,
)

@Serializable data class ShownPhase(val phase: String, val since: Long)

/** The session's transcript as it grows, the steps in flight and where the turn stands with the model. */
@Serializable data class LiveView(
    /** Whether the transcript has been read yet. */
    val loaded: Boolean = true,
    val timeline: List<TimelineEntry> = emptyList(),
    val steps: List<LiveStep> = emptyList(),
    val phase: ShownPhase? = null,
    val usage: TranscriptUsage? = null,
)
