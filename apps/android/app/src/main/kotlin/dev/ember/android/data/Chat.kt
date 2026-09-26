// The `chat` and `live` views (docs/client-core.md): one chat — its session,
// threads, the latest page of messages and what this device is still sending —
// and the running turn (transcript, steps in flight, phase). Messages are the
// station's thread messages (src/admin/types.ts → MessageView,
// docs/station-storage.md). `ChatView.thread()` turns the view into what the
// screen draws.
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
    val deletedAt: Long? = null,
)

@Serializable data class Membership(val session: String, val connect: String = "")

/** A thread: a Slack thread or a chat on ember's page. */
@Serializable data class ThreadView(
    val id: Long,
    /** "slack:<team id>" or "ember". */
    val surface: String = "ember",
    val channel: String = "",
    val channelName: String? = null,
    val threadTs: String = "",
    val title: String? = null,
    val creator: Creator? = null,
    val sessions: List<Membership> = emptyList(),
    val last: MessageView? = null,
    /** The viewer's read position (a seq). */
    val read: Long = 0,
    val unread: Int = 0,
) {
    val slack: Boolean get() = surface.startsWith("slack")
}

@Serializable data class TurnRecord(val id: String, val startedAt: Long = 0, val endedAt: Long? = null, val outcome: String? = null, val declared: String? = null)

/** A message sent from this device that the chat does not show yet. */
@Serializable data class OutboxItem(
    val id: String,
    val text: String = "",
    val attachments: List<Attachment> = emptyList(),
    val quotes: List<Quote> = emptyList(),
    val createdAt: Long = 0,
    /** sending | failed */
    val state: String = "sending",
    val error: String? = null,
)

/** An agent of the chat's thread, with what it runs on. Not in the view yet: today the chat's session is its only agent with a known model. */
@Serializable data class AgentView(val key: String, val model: String? = null, val runtime: String = "claude", val effort: String? = null, val state: String? = null, val station: String? = null)

@Serializable data class ChatView(
    val me: Me,
    val session: SessionSummary,
    val threads: List<ThreadView> = emptyList(),
    val turns: List<TurnRecord> = emptyList(),
    /** The thread shown: the session's ember chat. */
    val thread: ThreadView? = null,
    /** Its latest page, oldest first; `chat.older` brings earlier ones. */
    val messages: List<MessageView> = emptyList(),
    val more: Boolean = false,
    val outbox: List<OutboxItem> = emptyList(),
    val connect: ConnectView? = null,
    val profile: ProfileView? = null,
    val link: LinkView = LinkView(),
    val agents: List<AgentView> = emptyList(),
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
    val text: String = "",
    val input: String = "",
    val output: String = "",
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

// ── the screen's shape ──────────────────────────────────────────────────

data class Agent(val key: String, val station: String, val model: String?, val runtime: String, val effort: String?, val state: ChatState)

enum class Author { Me, Person, Agent, Ember }

data class Message(
    /** The message's ts, or the outbox id while it is on its way. */
    val id: String,
    val seq: Long,
    val author: Author,
    val name: String,
    /** Who a person is, for their avatar. */
    val personId: String,
    val agent: Agent?,
    val text: String,
    val quotes: List<Quote>,
    val attachments: List<Attachment>,
    /** block or final, when the agent declared it with this message. */
    val declared: String?,
    val createdAt: Long,
    /** From the outbox: sending, or failed (with why). */
    val sending: Boolean = false,
    val failed: String? = null,
)

data class Thread(
    val key: String,
    val station: String,
    val title: String,
    val fromSlack: Boolean,
    val slackUrl: String?,
    val people: List<Creator>,
    val agents: List<Agent>,
    val messages: List<Message>,
    val more: Boolean,
    /** The newest seq shown, for the read position. */
    val lastSeq: Long,
    val state: ChatState,
    val me: Me,
) {
    fun isMe(c: Creator) = me.isMe(c)
}

fun ChatView.thread(station: String): Thread {
    val s = session
    val state = s.state()
    val main = Agent(s.key, station, s.model, s.runtime, s.effort, state)
    val others = (thread?.sessions ?: emptyList()).map { it.session }.filter { it != s.key }.distinct()
    val known = agents.associateBy { it.key }
    val all = listOf(known[s.key]?.let { Agent(it.key, it.station ?: station, it.model ?: s.model, it.runtime, it.effort ?: s.effort, state) } ?: main) +
        others.map { k -> known[k]?.let { Agent(k, it.station ?: station, it.model, it.runtime, it.effort, agentState(it.state)) } ?: Agent(k, station, null, "claude", null, ChatState.Done) }
    val byKey = all.associateBy { it.key }
    val names = (s.participants + listOfNotNull(s.creator)).associate { it.id to it.name }
    fun mine(id: String) = id == me.id || (me.email != null && id.equals(me.email, ignoreCase = true))
    val said = messages.filter { it.deletedAt == null }.map { m ->
        val agent = if (m.authorKind == "agent") byKey[m.author] ?: Agent(m.author, station, m.authorName, "claude", null, ChatState.Done) else null
        val author = when {
            agent != null -> Author.Agent
            m.authorKind == "ember" -> Author.Ember
            mine(m.author) -> Author.Me
            else -> Author.Person
        }
        Message(
            id = m.ts, seq = m.seq, author = author,
            name = when (author) {
                Author.Me -> "你"
                Author.Agent -> agent!!.model ?: m.authorName ?: "agent"
                Author.Ember -> "ember"
                Author.Person -> m.authorName ?: names[m.author] ?: m.author
            },
            personId = m.author, agent = agent, text = m.text, quotes = m.quotes, attachments = m.attachments,
            declared = m.declared, createdAt = m.createdAt,
        )
    }
    val sending = outbox.map { o ->
        Message(o.id, Long.MAX_VALUE, Author.Me, "你", me.id, null, o.text, o.quotes, o.attachments, null, o.createdAt, sending = o.state == "sending", failed = if (o.state == "failed") o.error ?: "没发出去" else null)
    }
    val slack = threads.firstOrNull { it.slack }
    return Thread(
        key = s.key, station = station, title = thread?.title?.takeIf { it.isNotBlank() } ?: sessionTitle(s),
        fromSlack = connect?.kind == "slack" || slack != null,
        slackUrl = slack?.let { t -> connect?.slackUrl?.let { slackThreadUrl(it, t.channel, t.threadTs) } },
        people = (listOfNotNull(s.creator) + s.participants).distinctBy { it.id },
        agents = all, messages = said + sending, more = more, lastSeq = messages.lastOrNull()?.seq ?: 0, state = state, me = me,
    )
}

private fun agentState(state: String?): ChatState = when (state) {
    "block" -> ChatState.Block
    "running" -> ChatState.Running
    "failed" -> ChatState.Failed
    else -> ChatState.Done
}

fun slackThreadUrl(workspaceUrl: String, channel: String, threadTs: String) = "${workspaceUrl}archives/$channel/p${threadTs.replace(".", "")}"
