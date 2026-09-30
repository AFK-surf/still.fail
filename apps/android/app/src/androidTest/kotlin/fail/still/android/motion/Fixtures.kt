// Made-up data in the core's shapes (data/Shapes.kt), enough for the pages the motion tests drive: a signed-in account,
// a workspace with one station online and one model, and chats built message by message.
package fail.still.android.motion

import fail.still.android.data.Account
import fail.still.android.data.AccountWorkspaces
import fail.still.android.data.ChatMessage
import fail.still.android.data.ChatThread
import fail.still.android.data.ChatView
import fail.still.android.data.Link
import fail.still.android.data.Maker
import fail.still.android.data.Me
import fail.still.android.data.MessageBy
import fail.still.android.data.ModelOption
import fail.still.android.data.Outgoing
import fail.still.android.data.Stamp
import fail.still.android.data.StationView
import fail.still.android.data.WorkspaceSummary

object Fixtures {
    const val WS = "ws-motion"
    const val STATION = "$WS/st"
    const val THREAD = 7L
    /** When the test's chats happened (fixed, so each run draws the same). */
    const val NOW = 1_790_000_000_000L

    val account = Account(sub = "alice", email = "alice@example.com", name = "Alice")
    val workspaces = listOf(AccountWorkspaces(account, listOf(WorkspaceSummary(WS, "Dev", "owner", 1, 1)), loaded = true))

    val anthropic = Maker("anthropic", "Anthropic")
    val station = StationView(
        station = STATION, id = "st", name = "studio", summary = "在线", online = true, link = Link("online"),
        runtimes = emptyList(),
        models = listOf(ModelOption(model = "opus", name = "Opus 5.5", ids = listOf("opus"), maker = anthropic, runtimes = listOf("claude"), efforts = mapOf("claude" to listOf("high")), accounts = emptyMap())),
    )

    fun stamp(at: Long) = mapOf("createdAt" to Stamp(at.toDouble(), "刚刚", "9月30日 10:00", "", true))

    fun thread(last: Long, read: Long = last) = ChatThread(
        id = THREAD, surface = "ember", channel = "c", threadTs = "1", title = "修一下登录", createdAt = NOW - 60_000,
        sessions = emptyList(), last = last, read = read, unread = 0, people = emptyList(),
    )

    /** `said`: said while the chat shows, as the core marks it (attend.rs): it comes in. */
    fun mine(seq: Long, text: String, at: Long = NOW, said: Boolean? = null) = ChatMessage(
        seq = seq, thread = THREAD, ts = "t$seq", authorKind = "person", author = account.email, authorName = "Alice", text = text,
        attachments = emptyList(), quotes = emptyList(), createdAt = at, mine = true, system = false, by = MessageBy("Alice"), waiting = false, said = said, time = stamp(at),
    )

    fun agent(seq: Long, text: String, at: Long = NOW, said: Boolean? = null) = ChatMessage(
        seq = seq, thread = THREAD, ts = "t$seq", authorKind = "agent", author = "ember:c-1", authorName = "Claude", text = text,
        attachments = emptyList(), quotes = emptyList(), createdAt = at, mine = false, system = false,
        by = MessageBy("Claude", agent = "ember:c-1", maker = anthropic, runtime = "claude"), waiting = false, said = said, time = stamp(at),
    )

    fun outgoing(id: String, text: String, seq: Long? = null, at: Long = NOW) =
        Outgoing(id = id, text = text, attachments = emptyList(), quotes = emptyList(), createdAt = at, state = "sending", seq = seq, time = stamp(at))

    /** A chat's page: `thread` null is a chat asked for here that its station has not made yet. */
    fun chat(messages: List<ChatMessage>, outbox: List<Outgoing> = emptyList(), thread: ChatThread? = thread(messages.lastOrNull()?.seq ?: 0), title: String = "修一下登录") = ChatView(
        me = Me(id = account.email, email = account.email), thread = thread, title = title, people = emptyList(), agents = emptyList(),
        messages = messages, more = false, outbox = outbox, link = Link("online"), offline = false, pending = if (thread == null) true else null,
    )

    /** A few things said, to have a chat to send in. */
    val talk = listOf(
        mine(1, "登录页在 Safari 上点了没反应，帮我看一下"),
        agent(2, "看了一下：按钮的 `onClick` 在表单提交之前被 `preventDefault` 吞掉了。我把它改成在 `onSubmit` 里处理，Safari 和 Chrome 都试过了。"),
        mine(3, "好，顺便把错误提示也改成中文"),
        agent(4, "改好了：密码错误、账号不存在、网络断开三种情况都有中文提示。"),
    )
}
