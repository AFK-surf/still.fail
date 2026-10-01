// A chat's info sheet (split from Chat.kt).
package fail.still.android.screens

import fail.still.android.BuildConfig
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.data.ChatJobsView
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatView
import fail.still.android.data.ChatThread
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.state
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ModelMark
import fail.still.android.ui.PeopleStack
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import fail.still.core.CoreException
import kotlinx.coroutines.launch
/**
 * The chat itself: where it came from, who started it and takes part, its agents' web services (each opens its page)
 * and background jobs (each opens its sheet), its agents (each leads to its history).
 */
fun openChatInfo(app: AppState, station: String, of: ChatOf, thread: ChatThread) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
        val view = chat.value
        val jobs by rememberTopic<ChatJobsView>(app.core, Topics.chatJobs(station, of))
        SheetGrab()
        SheetHead("对话信息")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
            // Archived or offline, it is only read: no name to change, nothing to archive.
            val open = view != null && view.archived != true && !view.offline
            if (open) InfoList {
                InfoRow(onClick = { askTitle(app, station, view!!.thread?.id, (of as? ChatOf.Session)?.key ?: view.agents.firstOrNull()?.session?.key ?: "", view.title) }) {
                    Text("名称", fontSize = 14.sp, color = C.muted, modifier = Modifier.width(72.dp))
                    Text(view!!.title, fontSize = 14.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                // A station from before pins says nothing of them: its chats are not pinned from here.
                view!!.pinned?.let { pinned ->
                    val session = (of as? ChatOf.Session)?.key ?: view.agents.firstOrNull()?.session?.key ?: ""
                    // Under way: a spinner on the row, not tapped again.
                    val pinning = app.isDoing("chat.pin", "station" to station, "session" to session)
                    InfoRow(onClick = if (pinning) null else ({
                        app.act(if (pinned) "取消固定" else "固定") { app.api(station).setPinned(session, !pinned) }
                    })) {
                        IconIn(Icons.Pin, 16.dp, C.ink)
                        Text(if (pinned) "取消固定" else "固定到列表顶部", fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                        if (pinning) Spinner(14.dp)
                    }
                }
            }
            if (open) Spacer(Modifier.height(10.dp))
            InfoList {
                Detail("来自", view?.place?.let { "Slack · $it" } ?: "${BuildConfig.APP_NAME} 对话")
                Detail("发起", (view?.thread ?: thread).creator?.shown?.display ?: "未记录")
                Detail("参与", "${view?.people?.size ?: 0} 人") { view?.people?.let { if (it.isNotEmpty()) PeopleStack(it.take(8), 16.dp, C.surface2) } }
                Detail("创建", (view?.thread ?: thread).time?.get("createdAt")?.ago ?: "")
                (view?.thread ?: thread).lastMessage?.let { Detail("最近消息", it.time?.get("createdAt")?.ago ?: "") }
            }
            jobs.value?.let { JobGroups(app, station, of, it) }
            view?.slackUrl?.let { url ->
                GroupLabel("在 Slack 里")
                val context = LocalContext.current
                InfoList {
                    InfoRow(onClick = { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))) }) {
                        SlackMark(16.dp)
                        Text("在 Slack 中打开", fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                }
            }
            if (view != null && view.agents.isNotEmpty()) {
                GroupLabel("参与的 agent · 点开看它的执行历史")
                InfoList {
                    view.agents.forEach { a ->
                        val s = a.session
                        InfoRow(onClick = { openHistory(app, station, of, s.key) }) {
                            ModelMark(s.maker, s.runtime, 36.dp, a.state, around = C.surface2)
                            Column(Modifier.weight(1f)) {
                                Text(s.agentText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                // One line: it gives way with an ellipsis rather than wrapping.
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    if (a.connect != null) SlackMark(11.dp)
                                    Text(
                                        listOfNotNull(a.connect?.name, s.processText, s.time?.get("lastActiveAt")?.ago).joinToString(" · "),
                                        fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                            IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                        }
                    }
                }
            }
            // Into the archive (its first agent's session with it when it is that session's own), back to the list at once.
            if (open) {
                GroupLabel("归档")
                InfoList {
                    InfoRow(onClick = {
                        val session = view!!.agents.firstOrNull()?.session?.key ?: (of as? ChatOf.Session)?.key ?: ""
                        val archive = {
                            app.sheet = null
                            app.pop()
                            app.scope.launch {
                                try { app.api(station).setArchived(thread.id, session, true); app.toast = "已归档" }
                                catch (e: CoreException) { app.toast = "没能归档：${e.message}" }
                            }
                        }
                        // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
                        val watch = view.watch
                        if (watch != null) confirm(app, "归档「${view.title}」？", watch.ask, "归档") { archive() } else archive()
                    }) {
                        IconIn(Icons.Archive, 16.dp, C.ink)
                        Text("归档对话", fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/** Renames the chat (web mobile/sheets.tsx → ask, with `empty`): an empty name gives it back its first message. */
internal fun askTitle(app: AppState, station: String, thread: Long?, session: String, first: String) {
    app.sheet = SheetSpec(0.42f) {
        val scope = rememberCoroutineScope()
        var text by remember { mutableStateOf(first) }
        val busy = app.isDoing("chat.rename", "station" to station, "session" to session)
        var error by remember { mutableStateOf<String?>(null) }
        SheetGrab()
        SheetHead("重命名对话")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Field(text, { text = it }, "对话名称")
            Text("留空则自动起名", fontSize = 12.sp, color = C.muted)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button("取消", primary = false) { app.sheet = null }
                Button("保存", primary = true, busy = busy, enabled = text.trim() != first) {
                    error = null
                    scope.launch {
                        try { app.api(station).rename(thread, session, text.trim()); app.sheet = null }
                        catch (e: CoreException) { error = e.message }
                    }
                }
            }
        }
    }
}

@Composable
private fun Detail(label: String, value: String, extra: (@Composable () -> Unit)? = null) {
    InfoRow {
        Text(label, fontSize = 14.sp, color = C.muted, modifier = Modifier.width(72.dp))
        extra?.invoke()
        Text(value, fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
    }
}

@Composable
fun GroupLabel(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 14.dp, bottom = 4.dp))

@Composable
fun InfoList(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.ink.copy(alpha = 0.05f))) { content() }
}

@Composable
fun InfoRow(onClick: (() -> Unit)? = null, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}
