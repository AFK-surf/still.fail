// A chat's own sheet, from its bar's "…" (split from Chat.kt).
package fail.still.android.screens

import fail.still.android.ui.Spinner
import fail.still.android.data.t
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.data.ChatOf
import fail.still.android.data.ChatShare
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
import fail.still.android.ui.QuotaRings
import fail.still.android.ui.Smooth
import fail.still.android.ui.concentricOut
import fail.still.android.ui.DoingMark
import fail.still.android.ui.PickRow
import fail.still.android.ui.Button
import fail.still.android.ui.Field
/**
 * The chat itself, from "…": its name (with a way to change it) over who started it, how many take part and when it was
 * last written in, in a line; its agents, each where it stands (a tap opens its card, AgentSheet.kt); then what can be
 * done with it, within reach: what its agents and other chats' wrote each other, pin it, copy its link, open it in
 * Slack (or Feishu), archive it. As tall as what it shows.
 */
fun openChatInfo(app: AppState, station: String, of: ChatOf, thread: ChatThread, first: ChatView? = null) {
    val publish = shownPublish(first?.publish)
    val rows = (first?.agents?.size ?: 1) * 56 + ((if (first?.pinned != null) 1 else 0) + (if ((first?.letters ?: 0L) > 0L) 1 else 0) + (if (first?.slackUrl != null) 1 else 0) + (if (first?.feishuUrl != null) 1 else 0) + (if (first?.xshare != null) 1 else 0) + (if (first?.agents?.isNotEmpty() == true && first.archived != true && !first.offline) 1 else 0) + 2) * 40 +
        (if (publish != null) ((if (publish.may) 1 else 0) + publish.links.size) * 40 + 10 else 0)
    app.sheet = SheetSpec(0.55f, fit = (22 + 84 + rows + 10 + 30).dp) {
        val chat by rememberTopic<ChatView>(app.core, Topics.chat(station, of))
        val view = chat.value
        // Archived or offline, it is only read: no name to change, nothing to archive.
        val open = view != null && view.archived != true && !view.offline
        val session = (of as? ChatOf.Session)?.key ?: view?.agents?.firstOrNull()?.session?.key ?: ""
        val about = view?.thread ?: thread
        // Archived or offline it is still read, and pasted elsewhere still read there: its link is there whenever it has one.
        val link = if (view != null) chatLink(app.cloudOrigin, station, session) else null
        SheetGrab()
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, bottom = 30.dp)) {
            Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(view?.title ?: "", fontSize = 18.sp, lineHeight = 24.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (open) Box(
                    Modifier.size(32.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.05f)).clickable { askTitle(app, station, view!!.thread?.id, session, view.title) }
                        .semantics { contentDescription = t("android-chat.rename") },
                    contentAlignment = Alignment.Center,
                ) { IconIn(Icons.Edit, 16.dp, C.ink) }
            }
            // Who started it and when, how many take part, when it was last written in: what there is of them, in a line.
            val creator = about.creator?.shown?.display
            val created = about.time?.get("createdAt")?.ago
            val facts = listOfNotNull(
                view?.place?.let { t("android-chat.info.from.slack", "place" to it) },
                if (creator != null && created != null) t("android-chat.info.startedAt", "name" to creator, "ago" to created) else creator ?: created,
                view?.people?.size?.takeIf { it > 1 }?.let { t("android-chat.info.people.count", "n" to it) },
                about.lastMessage?.time?.get("createdAt")?.ago?.let { t("android-chat.info.latestAt", "ago" to it) },
            ).joinToString(" · ")
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                view?.people?.takeIf { it.isNotEmpty() }?.let { people ->
                    // The stack draws each face 5dp over the one before: as wide as what it draws.
                    Box(Modifier.width((19 + (people.take(5).size - 1) * 14).dp)) { Box(Modifier.wrapContentWidth(Alignment.Start, unbounded = true)) { PeopleStack(people.take(5), 16.dp, C.surface) } }
                }
                Text(facts, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            }
            if (view != null && view.agents.isNotEmpty()) {
                InfoList {
                    view.agents.forEach { a ->
                        val s = a.session
                        // The account it runs on now, with what is left of it (so a glance here saves the trip to settings).
                        val quota = a.account?.quota ?: a.profile?.quota
                        InfoRow(onClick = { openAgent(app, station, of, a) }, tile = true) {
                            ModelMark(s.maker, s.runtime, 36.dp, a.state, around = C.surface2)
                            Column(Modifier.weight(1f)) {
                                Text(s.agentText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                // Where it stands and for how long, in a line: it gives way with an ellipsis rather than wrapping.
                                Text(listOfNotNull(s.statusText, agentSince(a)).joinToString(" · "), fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            QuotaRings(quota)
                            IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                        }
                    }
                }
                Spacer(Modifier.height(10.dp))
            }
            val letters = view?.letters ?: 0L
            if (open || link != null || letters > 0L || view?.slackUrl != null || view?.feishuUrl != null || view?.xshare != null) InfoList {
                // What its agents and other chats' wrote each other, not in the chat: their own sheet (Letters.kt).
                if (view != null && letters > 0L) InfoRow(onClick = { openLetters(app, Here(station, of, view, emptyList(), orOwner = view.agents.firstOrNull()?.session?.key), about.id) }) {
                    IconIn(Icons.Chats, 16.dp, C.ink)
                    Text(t("web-main.letters.title"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                    Text(t("web-main.letters.count", "n" to letters), fontSize = 13.sp, color = C.muted)
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                // A station from before pins says nothing of them: its chats are not pinned from here.
                if (open) view!!.pinned?.let { pinned ->
                    // Under way: a spinner on the row, not tapped again.
                    val pinning = app.isDoing("chat.pin", "station" to station, "session" to session)
                    InfoRow(onClick = if (pinning) null else ({
                        app.act(if (pinned) t("android-chat.unpin.verb") else t("android-chat.pin.verb")) { app.api(station).setPinned(session, !pinned) }
                    })) {
                        IconIn(Icons.Pin, 16.dp, C.ink)
                        Text(if (pinned) t("android-chat.unpin") else t("android-chat.info.pinTop"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                        if (pinning) Spinner(inline = true)
                    }
                }
                link?.let {
                    val context = LocalContext.current
                    InfoRow(onClick = { copyChatLink(app, context, view?.title.orEmpty(), it) }) {
                        IconIn(Icons.Copy, 16.dp, C.ink)
                        Text(t("web-main.chat.copyLink"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                    }
                }
                // Relayed to a channel (docs/relay.md, Relay.kt): a chat with an agent to go on there.
                if (open && view!!.agents.isNotEmpty()) InfoRow(onClick = { openRelay(app, station, about.id) }) {
                    IconIn(Icons.ArrowUpRight, 16.dp, C.ink)
                    Text(t("web-main.relay.action"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                    IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                }
                view?.xshare?.let { share -> ShareRow(app, station, about.id, share) }
                view?.slackUrl?.let { url ->
                    val context = LocalContext.current
                    InfoRow(onClick = { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))) }) {
                        SlackMark(16.dp)
                        Text(t("android-chat.info.slack.open"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                }
                view?.feishuUrl?.let { url ->
                    val context = LocalContext.current
                    InfoRow(onClick = {
                        try { context.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))) }
                        catch (_: android.content.ActivityNotFoundException) { app.toast = t("android-chat.link.failed") }
                    }) {
                        SlackMark(16.dp, "feishu")
                        Text(t("web-mobile.chat.openFeishu"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
                    }
                }
                // Into the archive (its first agent's session with it when it is that session's own), back to the list at once.
                if (open) InfoRow(onClick = {
                    val own = view!!.agents.firstOrNull()?.session?.key ?: (of as? ChatOf.Session)?.key ?: ""
                    val archive: suspend () -> Unit = { app.api(station).setArchived(thread.id, own, true); app.toast = t("android-chat.archived") }
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
            // Making it public, a card of its own (Publish.kt).
            shownPublish(view?.publish)?.let { shown ->
                Spacer(Modifier.height(10.dp))
                PublishList(app, station, about.id, shown)
            }
        }
    }
}

/**
 * The chat's sharing with the viewer's other workspaces (docs/chat-share.md; web mobile/Chat.tsx ShareRow): where it is
 * shared at the row's end, under way a spinner there; a tap opens the sheet that changes it, for those who may (its
 * starter, an owner or admin).
 */
@Composable
private fun ShareRow(app: AppState, station: String, thread: Long, share: ChatShare) {
    val session = share.session
    val busy = app.isDoing("chat.xshare", "station" to station, "session" to session)
    val failed = app.failedOf("chat.xshare", "station" to station, "session" to session)
    InfoRow(onClick = if (!share.may || busy) null else ({ openShare(app, station, thread, session, share) })) {
        IconIn(Icons.Users, 16.dp, C.ink)
        // Its name whole; where it is shared after it, at the row's end, cut short rather than wrapped.
        Text(t("web-pages.chat.xshare"), fontSize = 14.sp, color = C.ink, maxLines = 1, softWrap = false)
        Text(share.text, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
        if (busy || failed != null) DoingMark(busy, failed)
        else if (share.may) IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/** Which of the viewer's other workspaces it is shared with, ticked, and whether their agents may send: done, the sheet goes at once. */
private fun openShare(app: AppState, station: String, thread: Long, session: String, share: ChatShare) {
    app.sheet = SheetSpec(0.6f, fit = (22 + 48 + 44 + share.places.size * 48 + 12 + 66 + 70).dp) {
        var ticked by remember { mutableStateOf(share.places.filter { it.on }.map { it.workspace }.toSet()) }
        var write by remember { mutableStateOf(share.write) }
        SheetGrab()
        SheetHead(t("web-pages.chat.xshare"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Text(t("web-pages.chat.xshare.lead"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
            share.places.forEach { p ->
                PickRow(p.name, checked = p.workspace in ticked) { ticked = if (p.workspace in ticked) ticked - p.workspace else ticked + p.workspace }
            }
            Box(Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 16.dp)) {
                val none = ticked.isEmpty()
                Row(
                    Modifier.fillMaxWidth().clip(Smooth(14.dp)).background(C.ink.copy(alpha = 0.05f)).clickable(enabled = !none) { write = !write }
                        .padding(horizontal = 14.dp, vertical = 10.dp).alpha(if (none) 0.5f else 1f),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(t("web-pages.chat.xshare.write"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                        Text(t("web-pages.chat.xshare.writeNote"), fontSize = 13.sp, color = C.muted)
                    }
                    Switch(write && !none)
                }
            }
            Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.End) {
                Button(t("common.done"), primary = true) {
                    app.sheet = null
                    val to = share.places.filter { it.workspace in ticked }.map { it.workspace }
                    app.act(t("web-pages.chat.xshare.verb")) { app.api(station).share(thread, session, to, write) }
                }
            }
        }
    }
}

/**
 * Renames the chat (web mobile/sheets.tsx → ask, with `empty`): an empty name gives it back its first message. The core
 * shows the new name at once (views/local.ts), so the sheet goes as it is given, not waiting on the station; a
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

// A group of rows in a sheet, as a small panel's (docs/ui-panels.md): each row's ground under the finger INFO_PAD from
// the group's edge, rounded INFO_ROW, the group's corner concentric with theirs; its words INFO_PAD + INFO_TEXT from
// the edge. A row that leads with a tile (a model's, 36 and rounded 11) has it INFO_IN inside it all round, so the
// tile is concentric with the row and the group too.
private val INFO_PAD = 6.dp
private val INFO_ROW = 14.dp
private val INFO_TEXT = 10.dp
private val INFO_IN = 4.dp

@Composable
fun InfoList(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(Smooth(concentricOut(INFO_ROW, INFO_PAD))).background(C.ink.copy(alpha = 0.05f)).padding(INFO_PAD)) { content() }
}

@Composable
fun InfoRow(onClick: (() -> Unit)? = null, tile: Boolean = false, content: @Composable RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(Smooth(INFO_ROW)).let { if (onClick != null) it.clickable(onClick = onClick) else it }
            .padding(horizontal = if (tile) INFO_IN else INFO_TEXT, vertical = INFO_IN),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}
