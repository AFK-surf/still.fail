// A chat's info sheet (split from Chat.kt).
package fail.still.android.screens

import fail.still.android.ui.t
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
import fail.still.android.ui.QuotaRings
/**
 * The chat itself: where it came from, who started it and takes part,
 * and its agents (each leads to its history).
 */
fun openChatInfo(app: AppState, station: String, of: ChatOf, thread: ChatThread) {
    app.sheet = SheetSpec(0.72f, draggable = true) {
        val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
        val view = chat.value
        SheetGrab()
        SheetHead(t("android-chat.info.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
            // Archived or offline, it is only read: no name to change, nothing to archive.
            val open = view != null && view.archived != true && !view.offline
            if (open) InfoList {
                InfoRow(onClick = { askTitle(app, station, view!!.thread?.id, (of as? ChatOf.Session)?.key ?: view.agents.firstOrNull()?.session?.key ?: "", view.title) }) {
                    Text(t("android-chat.info.name"), fontSize = 14.sp, color = C.muted, modifier = Modifier.width(72.dp))
                    Text(view!!.title, fontSize = 14.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                // A station from before pins says nothing of them: its chats are not pinned from here.
                view!!.pinned?.let { pinned ->
                    val session = (of as? ChatOf.Session)?.key ?: view.agents.firstOrNull()?.session?.key ?: ""
                    // Under way: a spinner on the row, not tapped again.
                    val pinning = app.isDoing("chat.pin", "station" to station, "session" to session)
                    InfoRow(onClick = if (pinning) null else ({
                        app.act(if (pinned) t("android-chat.unpin.verb") else t("android-chat.pin.verb")) { app.api(station).setPinned(session, !pinned) }
                    })) {
                        IconIn(Icons.Pin, 16.dp, C.ink)
                        Text(if (pinned) t("android-chat.unpin") else t("android-chat.info.pinTop"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                        if (pinning) Spinner(14.dp)
                    }
                }
            }
            if (open) Spacer(Modifier.height(10.dp))
            InfoList {
                Detail(t("android-chat.info.from"), view?.place?.let { t("android-chat.info.from.slack", "place" to it) } ?: t("android-chat.info.from.app", "app" to BuildConfig.APP_NAME))
                Detail(t("android-chat.info.creator"), (view?.thread ?: thread).creator?.shown?.display ?: t("android-chat.info.creator.none"))
                Detail(t("android-chat.info.people"), t("android-chat.info.people.count", "n" to (view?.people?.size ?: 0))) { view?.people?.let { if (it.isNotEmpty()) PeopleStack(it.take(8), 16.dp, C.surface2) } }
                Detail(t("android-chat.info.created"), (view?.thread ?: thread).time?.get("createdAt")?.ago ?: "")
                (view?.thread ?: thread).lastMessage?.let { Detail(t("android-chat.info.latest"), it.time?.get("createdAt")?.ago ?: "") }
            }
            view?.slackUrl?.let { url ->
                GroupLabel(t("android-chat.info.slack"))
                val context = LocalContext.current
                InfoList {
                    InfoRow(onClick = { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))) }) {
                        SlackMark(16.dp)
                        Text(t("android-chat.info.slack.open"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                }
            }
            if (view != null && view.agents.isNotEmpty()) {
                GroupLabel(t("android-chat.info.agents"))
                InfoList {
                    view.agents.forEach { a ->
                        val s = a.session
                        // The account it runs on now, with what is left of it (so a glance here saves the trip to settings).
                        val account = a.account?.let { it.name to it.quota } ?: a.profile?.let { it.name to it.quota }
                        InfoRow(onClick = { openHistory(app, station, of, s.key) }) {
                            ModelMark(s.maker, s.runtime, 36.dp, a.state, around = C.surface2)
                            Column(Modifier.weight(1f)) {
                                Text(s.agentText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                // One line: it gives way with an ellipsis rather than wrapping.
                                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    if (a.connect != null) SlackMark(11.dp)
                                    Text(
                                        listOfNotNull(a.connect?.name, account?.first, s.processText, s.time?.get("lastActiveAt")?.ago).joinToString(" · "),
                                        fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    )
                                }
                            }
                            QuotaRings(account?.second)
                            IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                        }
                    }
                }
            }
            // Into the archive (its first agent's session with it when it is that session's own), back to the list at once.
            if (open) {
                GroupLabel(t("android-chat.archive"))
                InfoList {
                    InfoRow(onClick = {
                        val session = view!!.agents.firstOrNull()?.session?.key ?: (of as? ChatOf.Session)?.key ?: ""
                        val archive: suspend () -> Unit = { app.api(station).setArchived(thread.id, session, true); app.toast = t("android-chat.archived") }
                        // A chat keeping watch is archived only once asked: its watch runs on in the archive (the core's words).
                        // Either way the sheet closes and the page goes at once; a toast says if it could not.
                        val watch = view.watch
                        if (watch != null) confirm(app, t("android-chat.archive.ask", "title" to view.title), watch.ask, t("android-chat.archive"), what = t("android-chat.archive.verb"), then = app::pop, run = archive)
                        else { app.sheet = null; app.pop(); app.act(t("android-chat.archive.verb"), run = archive) }
                    }) {
                        IconIn(Icons.Archive, 16.dp, C.ink)
                        Text(t("android-chat.info.archive"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                    }
                }
            }
        }
    }
}

/**
 * Renames the chat (web mobile/sheets.tsx → ask, with `empty`): an empty name gives it back its first message. The core
 * shows the new name at once (views/changing.rs), so the sheet goes as it is given, not waiting on the station; a
 * failure is said by a toast, the name as it was again.
 */
internal fun askTitle(app: AppState, station: String, thread: Long?, session: String, first: String) {
    app.sheet = SheetSpec(0.42f) {
        var text by remember { mutableStateOf(first) }
        SheetGrab()
        SheetHead(t("android-chat.rename.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Field(text, { text = it }, t("android-chat.rename.field"))
            Text(t("android-chat.rename.note"), fontSize = 12.sp, color = C.muted)
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(t("common.save"), primary = true, enabled = text.trim() != first) {
                    val title = text.trim()
                    app.sheet = null
                    app.act(t("android-chat.rename.verb")) { app.api(station).rename(thread, session, title) }
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
