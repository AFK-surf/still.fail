// A chat relayed to a channel (docs/relay.md), from its sheet (ChatInfo.kt): the sheet that picks where (web
// mobile/Chat.tsx RelaySheet, Relay.tsx useRelay).
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
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

private fun platform(c: RelayConnect) = when (c.kind) { "slack" -> "Slack"; "lark" -> "Lark"; else -> t("web-pages.connect.feishu.name") }

/**
 * Relays the chat to a channel: the search (or a pasted Slack message link, which offers that message's thread), the
 * places by connect as the station reads them as the sheet opens, the note, 「接力」. Done, the sheet goes at once and a
 * toast says where it went (or why not).
 */
internal fun openRelay(app: AppState, station: String, thread: Long) {
    app.sheet = SheetSpec(0.9f) {
        var read by remember { mutableStateOf<Places>(Places.Reading) }
        var query by remember { mutableStateOf("") }
        var picked by remember { mutableStateOf<Pair<String, RelayPlace>?>(null) }
        var note by remember { mutableStateOf("") }
        LaunchedEffect(thread) {
            read = try { Places.Ok(app.api(station).relayPlaces(thread)) } catch (e: CoreException) { Places.Failed(errorText(e)) }
        }
        val link = query.trim().takeIf { SLACK_LINK.containsMatchIn(it) }
        val q = query.trim().lowercase()
        SheetGrab()
        SheetHead(t("web-main.relay.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 20.dp, end = 20.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("web-main.relay.lead"), fontSize = 13.sp, color = C.muted)
            Field(query, { query = it }, t("web-main.relay.searchOrLink"), max = 400)
            val shown = read
            when {
                link != null -> PlaceRow(t("web-main.relay.thread"), t("web-main.relay.kind.thread"), on = true) {}
                shown is Places.Reading -> WaitLine(t("web-main.relay.reading"))
                shown is Places.Failed -> Text(shown.error, fontSize = 13.sp, color = C.red)
                shown is Places.Ok && shown.connects.isEmpty() -> Text(t("web-main.relay.noConnects"), fontSize = 13.sp, color = C.muted)
                shown is Places.Ok -> Column {
                    shown.connects.forEach { c ->
                        val places = if (q.isEmpty()) c.places else c.places.filter { it.name.lowercase().contains(q) }
                        Row(Modifier.padding(start = 8.dp, top = 8.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            SlackMark(13.dp, if (c.kind == "slack") null else "feishu")
                            Text("${platform(c)} · ${c.team ?: c.name}", fontSize = 12.sp, color = C.muted)
                        }
                        when {
                            c.error != null -> Text(t("web-main.relay.unread", "error" to c.error!!), fontSize = 12.sp, color = C.red, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
                            places.isEmpty() -> Text(if (q.isEmpty()) t("web-main.relay.noPlaces") else t("web-main.relay.noMatch"), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp))
                        }
                        places.forEach { p ->
                            val name = if (p.kind == "channel") "${if (p.private) "🔒 " else ""}#${p.name}" else p.name
                            PlaceRow(name, kindNote(p), on = picked?.first == c.id && picked?.second?.id == p.id) { picked = c.id to p }
                        }
                    }
                }
            }
            Text(t("web-main.relay.note"), fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp))
            Field(note, { note = it }, t("web-main.relay.notePlaceholder"), max = 2000)
            Button(t("web-main.relay.go"), primary = true, enabled = link != null || picked != null, modifier = Modifier.fillMaxWidth()) {
                val to = picked
                app.sheet = null
                app.act(t("web-main.relay.verb")) {
                    val place = app.api(station).relay(thread, to?.first, to?.second?.id, link, note)
                    app.toast = t("web-main.relay.done", "place" to place)
                }
            }
        }
    }
}

/** A place to pick: its name, and what relaying there does at the row's end; picked, on the accent's ground. */
@androidx.compose.runtime.Composable
private fun PlaceRow(name: String, note: String, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 40.dp).clip(Smooth(10.dp)).let { if (on) it.background(C.accentBg) else it }
            .clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(name, fontSize = 15.sp, color = if (on) C.accentInk else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(note, fontSize = 12.sp, color = if (on) C.accentInk else C.muted, maxLines = 1)
    }
}
