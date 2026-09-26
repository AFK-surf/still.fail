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
    /** Whether it is the viewer's (their bubble), as the core decides. */
    val mine: Boolean = false,
    /** Said by ember itself (a limit hit, a failure): a notice across the chat, as the core decides. */
    val system: Boolean = false,
    val createdAt: Long = 0,
    /** When its latest edit came; null if never edited. */
    val editedAt: Long? = null,
    /** Who said it, as its line shows them (an agent by its label and mark), as the core puts it. */
    val by: MessageBy = MessageBy(),
    /** Its agents have not taken it yet. */
    val waiting: Boolean = false,
    val time: Map<String, Stamp> = emptyMap(),
)

@Serializable data class MessageBy(val name: String = "", val agent: String? = null, val maker: Maker? = null, val runtime: String? = null, val picture: String? = null)

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
    val time: Map<String, Stamp> = emptyMap(),
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
    /** Where it stands (running, queued, final, block, failed, aborted, unexpected, idle) and its mark, as the core decides. */
    val status: String = "idle",
    val badge: String? = null,
    val connect: ConnectView? = null,
    val profile: ProfileView? = null,
    val turns: List<TurnRecord> = emptyList(),
    val threads: List<ThreadView> = emptyList(),
    /** Who can run it now: the profiles of its runtime with its model enabled. */
    val profiles: List<RunnableProfile> = emptyList(),
    /** What it can move to, a model at a time, each with who runs it. */
    val choices: List<ModelChoice> = emptyList(),
    /** What is worth a look about it now (an account signed out, a quota running out, the disk filling up). */
    val attention: List<Attention> = emptyList(),
    /** When its running turn began; null when none runs. */
    val since: Long? = null,
)

/** A profile a session can run on: `current` it runs on it now; `kind` whose account it is (subscription, opencode-go, …). */
@Serializable data class RunnableProfile(
    val id: String,
    val name: String,
    val current: Boolean = false,
    val kind: String? = null,
    val runtime: String? = null,
    val quota: ProfileQuota? = null,
    val spent: Spent? = null,
)

@Serializable data class ModelChoice(val model: String, val maker: Maker? = null, val profiles: List<RunnableProfile> = emptyList())

/** account (`state` login | failed, `name`), quota (`label`, `left` percent, `until`), or disk (`freeBytes`, `totalBytes`). */
@Serializable data class Attention(
    val kind: String,
    val state: String? = null,
    val name: String? = null,
    val label: String = "",
    val left: Double = 100.0,
    val until: Double? = null,
    val freeBytes: Double = 0.0,
    val totalBytes: Double = 0.0,
    /** account, disk: what it says. */
    val text: String = "",
    /** quota: its window's mark, its tip's lines, how bad (amber | red). */
    val mark: String = "",
    val tip: List<String?> = emptyList(),
    val level: String = "amber",
)

/** An item's page. Before its agent has a chat, `thread` is null and there is only the agent. */
@Serializable data class ChatView(
    val me: Me,
    val thread: ThreadView? = null,
    val title: String = "",
    /** Where a Slack chat is (#channel, 私信), and its link in Slack while its connect is signed in. */
    val place: String? = null,
    val slackUrl: String? = null,
    val people: List<Creator> = emptyList(),
    val agents: List<ChatAgentView> = emptyList(),
    /** Merged from the entries loaded so far, oldest first; `chat.older` brings earlier ones. */
    val messages: List<MessageView> = emptyList(),
    val more: Boolean = false,
    val outbox: List<OutboxItem> = emptyList(),
    val link: LinkView = LinkView(),
    /** Its station is offline (the core says): what was kept shows, nothing can be sent. */
    val offline: Boolean = false,
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
    /** What the agent is doing, as the core puts it (client/core/src/activity.rs). */
    val activity: ActivityView? = null,
)

@Serializable data class ActivityView(val status: String = "", val rows: List<ActivityRowView> = emptyList())

/** One row: what kind of thing (its icon), in words, whether it runs now, and its transcript entry (for its history). */
@Serializable data class ActivityRowView(val key: String, val kind: String = "other", val icon: String = "other", val text: String = "", val live: Boolean = false, val entry: Int? = null)

/** A place a message came from or went to: a chat on ember's page (`session`: the agent it opens), or a Slack thread. */
@Serializable data class Place(val name: String, val surface: String = "slack", val session: String? = null)

@Serializable data class HistoryFrom(val name: String = "", val slackUser: String? = null, val bound: Boolean = false)
@Serializable data class HistoryMessage(val key: String = "", val from: HistoryFrom = HistoryFrom(), val text: String = "", val place: Place? = null)
@Serializable data class HistoryThought(val text: String = "", val first: String = "")
@Serializable data class HistoryStep(val said: String? = null, val name: String = "", val hint: String = "", val meta: String = "", val failed: Boolean = false, val call: String = "", val result: String? = null)

/** One item of an execution history, as the core puts it (client/core/src/history.rs); `entries`: the transcript entries it draws. */
@Serializable data class HistoryItem(
    val key: String,
    /** received | text | post | mark | group */
    val kind: String,
    val entries: List<Int> = emptyList(),
    val note: String? = null,
    val messages: List<HistoryMessage> = emptyList(),
    val text: String = "",
    val subagent: Boolean = false,
    val place: Place? = null,
    val block: Boolean = false,
    /** A post that failed. */
    val failed: Boolean = false,
    val summary: String = "",
    val title: String = "",
    /** A group's failed calls, and those still running. */
    val failures: Int = 0,
    val pending: Int = 0,
    val thinking: List<HistoryThought> = emptyList(),
    val steps: List<HistoryStep> = emptyList(),
)

@Serializable data class HistoryLive(val id: String, val text: String)
@Serializable data class HistoryPhase(val phase: String, val text: String = "", val since: Long = 0)
@Serializable data class UsageLine(val label: String, val value: String)

/** An agent's execution history, read for people: items, what streams now, where the turn stands. */
@Serializable data class HistoryView(
    val items: List<HistoryItem> = emptyList(),
    val live: List<HistoryLive> = emptyList(),
    val phase: HistoryPhase? = null,
    val usage: List<UsageLine>? = null,
    val usageLine: String? = null,
    /** What shows at its top: where the session begins, or why there is nothing (yet). */
    val edge: String = "",
    val empty: Boolean = true,
    val loaded: Boolean = false,
)

/** An agent's mark as the app draws it: the core's badge, in the app's terms (nothing decided here). */
val ChatAgentView.state: ChatState get() = badgeState(badge) ?: ChatState.Done
