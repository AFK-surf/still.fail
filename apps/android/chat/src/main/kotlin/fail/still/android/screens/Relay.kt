// A chat relayed to a channel (docs/relay.md), from its sheet (ChatInfo.kt): the sheet that picks where (web
// mobile/Chat.tsx RelaySheet, Relay.tsx useRelay).
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.data.RelayConnect
import fail.still.android.data.RelayPlace
import fail.still.android.data.errorText
import fail.still.android.data.t
import fail.still.android.ui.Avatar
import fail.still.android.ui.Button
import fail.still.android.ui.C
import fail.still.android.ui.Field
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import fail.still.android.ui.Smooth
import fail.still.android.ui.WaitLine
import fail.still.core.CoreException

/** The places as asked (`chat.relayPlaces`): being read, read, or why not. */
private sealed interface Places {
    data object Reading : Places
    data class Ok(val connects: List<RelayConnect>) : Places
    data class Failed(val error: String) : Places
}

/** Whether what was typed is a link to a Slack message (the station finds its workspace among its connects'). */
private val SLACK_LINK = Regex("""^https?://[^/\s]+/archives/[A-Z0-9]+/p\d{16}""")

/** How a place says what relaying there does: a new thread, a new topic, or the group's conversation taken over. */
private fun kindNote(p: RelayPlace) = t(when (p.kind) { "channel" -> "web-main.relay.kind.channel"; "topics" -> "web-main.relay.kind.topics"; else -> "web-main.relay.kind.group" })

/** A connect as people know it: its workspace (Slack) or tenant (Feishu), else its bot's name; with its bot's name too
 * when another of `connects` (several bots in one workspace) has the same workspace. */
private fun workspace(c: RelayConnect, connects: List<RelayConnect>) =
    if (c.team != null && connects.any { it.id != c.id && it.team == c.team }) "${c.team} · ${c.name}" else c.team ?: c.name

private fun placeName(p: RelayPlace) = if (p.kind == "channel") "${if (p.private) "🔒 " else ""}#${p.name}" else p.name

private fun markOf(c: RelayConnect) = if (c.kind == "slack") null else "feishu"

/** A place with the connect it is through. */
private data class Spot(val connect: RelayConnect, val place: RelayPlace)

/** How many places relayed to before are offered as the sheet opens, before 「显示全部」; with no more than FEW places in all, all of them are. */
private const val RECENT = 5
private const val FEW = 8

/** The places offered, as the web's (Relay.tsx arrange): those matching what was typed (starting with it first), relayed to before (latest first), by name; nothing typed, only the recent ones of many unless all were asked for. */
private data class Arranged(val rows: List<Spot>, val recent: Boolean, val total: Int)

private fun arrange(connects: List<RelayConnect>, query: String, all: Boolean): Arranged {
    val q = query.trim().lowercase()
    val rows = connects.flatMap { c -> c.places.map { Spot(c, it) } }
    val shown = (if (q.isEmpty()) rows else rows.filter { it.place.name.lowercase().contains(q) }).sortedWith(
        compareBy<Spot> { if (q.isNotEmpty() && it.place.name.lowercase().startsWith(q)) 0 else 1 }
            .thenByDescending { it.place.used ?: -1L }
            .thenBy { it.place.name },
    )
    val used = shown.filter { it.place.used != null }
    if (q.isEmpty() && !all && rows.size > FEW && used.isNotEmpty()) return Arranged(used.take(RECENT), true, rows.size)
    return Arranged(shown, false, rows.size)
}

/**
 * Relays the chat to a channel: the search (or a pasted Slack message link, which offers that message's thread), the
 * workspaces to look in when there are several, the places relayed to before as it opens (all of them asked for or
 * searched), the one picked with the note, 「接力到 …」. Done, the sheet goes at once and a toast says where it went (or why not).
 */
internal fun openRelay(app: AppState, station: String, thread: Long) {
    app.sheet = SheetSpec(0.9f) {
        var read by remember { mutableStateOf<Places>(Places.Reading) }
        var query by remember { mutableStateOf("") }
        var scope by remember { mutableStateOf<String?>(null) }
        var all by remember { mutableStateOf(false) }
        var picked by remember { mutableStateOf<Spot?>(null) }
        var note by remember { mutableStateOf("") }
        LaunchedEffect(thread) {
            read = try { Places.Ok(app.api(station).relayPlaces(thread)) } catch (e: CoreException) { Places.Failed(errorText(e)) }
        }
        val link = query.trim().takeIf { SLACK_LINK.containsMatchIn(it) }
        SheetGrab()
        SheetHead(t("web-main.relay.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("web-main.relay.lead"), fontSize = 13.sp, color = C.muted)
            val chosen = picked
            if (chosen == null) Field(query, { query = it }, t("web-main.relay.searchOrLink"), max = 400)
            val shown = read
            when {
                link != null -> PlaceRow(null, t("web-main.relay.thread"), null, t("web-main.relay.kind.thread"), on = true) {}
                chosen != null -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    PlaceRow(markOf(chosen.connect), placeName(chosen.place), workspace(chosen.connect, (read as? Places.Ok)?.connects.orEmpty()), "${kindNote(chosen.place)} · ${t("web-main.relay.change")}", on = true) { picked = null }
                    // its picture under the row's mark, its words in line with the place's name
                    Row(Modifier.padding(horizontal = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val image = chosen.connect.botImage
                        if (image != null) Avatar(chosen.connect.id, chosen.connect.name, 16.dp, picture = image) else SlackMark(16.dp, markOf(chosen.connect))
                        Text(t("web-main.relay.via", "bot" to chosen.connect.name), fontSize = 12.sp, color = C.muted)
                    }
                }
                shown is Places.Reading -> WaitLine(t("web-main.relay.reading"))
                shown is Places.Failed -> Text(shown.error, fontSize = 13.sp, color = C.red)
                shown is Places.Ok && shown.connects.isEmpty() -> Text(t("web-main.relay.noConnects"), fontSize = 13.sp, color = C.muted)
                shown is Places.Ok -> Column {
                    val several = shown.connects.size > 1
                    if (several) {
                        Row(Modifier.horizontalScroll(rememberScrollState()).padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            ScopeChip(false, null, t("web-main.relay.allWorkspaces"), scope == null) { scope = null }
                            shown.connects.forEach { c -> ScopeChip(true, markOf(c), workspace(c, shown.connects), scope == c.id) { scope = c.id } }
                        }
                    }
                    val looked = shown.connects.filter { scope == null || it.id == scope }
                    val (rows, recent, total) = arrange(looked, query, all)
                    if (recent) Text(t("web-main.relay.recent"), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
                    rows.forEach { r ->
                        PlaceRow(markOf(r.connect), placeName(r.place), if (several && scope == null) workspace(r.connect, shown.connects) else null, if (r.place.kind == "channel") null else kindNote(r.place), on = false) { picked = r }
                    }
                    if (rows.isEmpty()) Text(if (query.isBlank()) t("web-main.relay.noPlaces") else t("web-main.relay.noMatch"), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
                    if (recent && total > rows.size) {
                        Text(t("web-main.relay.showAll", "count" to total), fontSize = 13.sp, color = C.link, modifier = Modifier.clip(Smooth(8.dp)).clickable { all = true }.padding(horizontal = 8.dp, vertical = 6.dp))
                    }
                    looked.forEach { c ->
                        c.error?.let { Text((if (several) "${workspace(c, shown.connects)} · " else "") + t("web-main.relay.unread", "error" to it), fontSize = 12.sp, color = C.red, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp)) }
                    }
                }
            }
            if (chosen != null || link != null) {
                Text(t("web-main.relay.note"), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp))
                Field(note, { note = it }, t("web-main.relay.notePlaceholder"), max = 2000)
            }
            val label = if (chosen != null) t("web-main.relay.goTo", "place" to placeName(chosen.place)) else t("web-main.relay.go")
            Button(label, primary = true, enabled = link != null || chosen != null, modifier = Modifier.fillMaxWidth()) {
                val to = picked
                app.sheet = null
                app.act(t("web-main.relay.verb")) {
                    val place = app.api(station).relay(thread, to?.connect?.id, to?.place?.id, link, note)
                    app.toast = t("web-main.relay.done", "place" to place)
                }
            }
        }
    }
}

/** A workspace to look in (or all of them): its platform's mark and name; chosen, filled. */
@androidx.compose.runtime.Composable
private fun ScopeChip(logo: Boolean, mark: String?, label: String, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.clip(Smooth(13.dp)).background(if (on) C.ink else C.chip).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (logo) SlackMark(13.dp, mark)
        Text(label, fontSize = 12.sp, color = if (on) C.bg else C.muted, maxLines = 1)
    }
}

/** A place to pick: its platform's mark, its name, its workspace (among several), and what relaying there does at the row's end; picked, on the accent's ground. */
@androidx.compose.runtime.Composable
private fun PlaceRow(mark: String?, name: String, where: String?, note: String?, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 40.dp).clip(Smooth(10.dp)).let { if (on) it.background(C.accentBg) else it }
            .clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        SlackMark(16.dp, mark)
        Text(name, fontSize = 15.sp, color = if (on) C.accentInk else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        if (where != null) Text(where, fontSize = 12.sp, color = if (on) C.accentInk else C.muted, maxLines = 1)
        Spacer(Modifier.weight(1f))
        if (note != null) Text(note, fontSize = 12.sp, color = if (on) C.accentInk else C.muted, maxLines = 1)
    }
}
