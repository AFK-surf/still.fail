// The archive (web/src/pages/Archive.tsx): chats archived by hand or by the station once they idled (a day by
// default), of every station online in one list, newest first and grouped by the day they were archived. Each can be
// opened to read (its composer restores it), put back in the list, and one archived with its session deleted for good. Anything new said in a chat the station
// archived brings it back by itself; one archived by hand takes no messages until shown again. A row: its title with when (and where) at the end of its line, then what can be done with it; its
// last message the whole line under it. No lines between.
package fail.still.android.screens

import fail.still.android.ui.Spinner
import fail.still.android.ui.Waiting
import fail.still.android.data.t
import fail.still.android.ui.Smooth
import androidx.compose.foundation.background
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.ArchiveItem
import fail.still.android.data.ArchiveView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.DoingMark

@Composable
fun ArchiveScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    // It can be very long: only those with the words looked for, and only the newest so many, more as it is scrolled near
    // its end; every station's archive as the core puts it together, and takes a chat out of once restored or deleted.
    var q by rememberSaveable { mutableStateOf("") }
    var limit by rememberSaveable { mutableIntStateOf(Topics.ARCHIVE_PAGE) }
    val archive by rememberTopic<ArchiveView>(app.core, Topics.archive(current.workspace.id, q.trim(), limit))
    // Asked for more (or other words), what was shown stays until it comes: no rows taken away meanwhile.
    val last = remember { arrayOfNulls<ArchiveView>(1) }
    val view = archive.value?.also { last[0] = it } ?: last[0]
    val restore = { item: ArchiveItem -> app.act(t("android-misc.archive.restoreWhat"), t("android-misc.archive.restored")) { app.api(item.station).setArchived(item.thread, item.session, false) } }
    val delete = { item: ArchiveItem ->
        confirm(app, t("android-misc.archive.deleteTitle", "title" to item.title), t("android-misc.archive.deleteText"), t("common.delete"), danger = true,
            what = t("android-misc.archive.deleteWhat")) {
            app.api(item.station).deleteSession(item.session)
            app.toast = t("android-misc.archive.deleted")
        }
    }
    val list = rememberLazyListState()
    // A screen or so before the end, the next rows.
    val near by remember { derivedStateOf { list.layoutInfo.visibleItemsInfo.lastOrNull()?.index?.let { it >= list.layoutInfo.totalItemsCount - 12 } == true } }
    LaunchedEffect(near, view) { if (near && view?.more == true) limit += Topics.ARCHIVE_PAGE }
    // 令 in the bar's notch, as on the chats' list; nothing of its own to add.
    PlacePage(current, "archive", null, back = fail.still.android.placeLabel("chats")) { top ->
    LazyColumn(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.navigationBars), state = list, contentPadding = PaddingValues(top = top, bottom = 24.dp)) {
        item(key = "search") { ArchiveSearch(q) { q = it; limit = Topics.ARCHIVE_PAGE } }
        // Nothing to show yet and still read (or some stations' could not be): the first read's shapes, what is waited on and
        // the stations that failed as its pills (so not their red lines too).
        if (view == null || view.days.isEmpty() && (view.wait.reading || view.wait.failing.isNotEmpty())) item(key = "wait") {
            Waiting(note = view?.wait, text = t("common.readingStations"), error = if (view == null) archive.error?.message else null)
        } else {
            view.errors.forEach { e -> item(key = "error/${e.station}") { Text(e.text, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) } }
            view.note?.let { note -> item(key = "note") { Text(note, fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) } }
            // What lands here, said only while nothing has.
            if (view.days.isEmpty() && q.isBlank()) item(key = "empty") { PlaceEmpty(t("android-misc.archive.note")) }
            view.days.forEach { day ->
                item(key = "day/${day.label}") { SectionHeader(day.label) }
                items(day.items, key = { "${it.station}/${it.thread ?: it.session}" }) { item ->
                    // Restoring or deleting it under way: a spinner in place of its actions; failed: a red mark beside them a moment.
                    val busy = app.isDoing("chat.archive", "station" to item.station, "session" to item.session) ||
                        app.isDoing("session.delete", "station" to item.station, "key" to item.session)
                    val failed = app.failedOf("chat.archive", "station" to item.station, "session" to item.session)
                        ?: app.failedOf("session.delete", "station" to item.station, "key" to item.session)
                    // Tapped, its chat: read there, and restored from its composer.
                    ArchiveRow(item, busy, failed, { app.push(Screen.Chat(item.station, ChatOf.Session(item.session))) }, { restore(item) }, { delete(item) })
                }
            }
        }
        item(key = "room") { BarRoom() }
    }
    }
}

/** Looking for one by its title or last line: the chats' search field (Search.kt), over the list. */
@Composable
private fun ArchiveSearch(q: String, onChange: (String) -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 8.dp).height(38.dp)
            .clip(Smooth(19.dp)).background(C.ink.copy(alpha = 0.06f)).padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconIn(Icons.Search, 17.dp, C.muted)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (q.isEmpty()) Text(t("web-pages.archive.search"), fontSize = 16.sp, color = C.muted, maxLines = 1)
            BasicTextField(
                q, onChange, singleLine = true, cursorBrush = SolidColor(C.accent),
                textStyle = TextStyle(fontSize = 16.sp, color = C.ink),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = t("web-pages.archive.search") },
            )
        }
    }
}

@Composable
private fun ArchiveRow(item: ArchiveItem, busy: Boolean, failed: String?, onOpen: () -> Unit, onRestore: () -> Unit, onDelete: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(start = 20.dp, end = 10.dp, top = 6.dp, bottom = 6.dp)) {
        Row(Modifier.height(34.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(item.title, fontSize = 16.sp, lineHeight = 22.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            // When (and where), then what can be done: no pointer to point with, so always there.
            Text(
                listOfNotNull(item.place, item.clock).joinToString("  "),
                fontSize = 12.sp, color = C.subtle, maxLines = 1,
                modifier = Modifier.semantics { contentDescription = item.how },
            )
            if (busy) Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { Spinner() }
            else Row(verticalAlignment = Alignment.CenterVertically) {
                if (failed != null) Box(Modifier.size(34.dp), contentAlignment = Alignment.Center) { DoingMark(false, failed) }
                Action(Icons.Retry, t("android-misc.archive.restoreNamed", "title" to item.title), onRestore)
                if (item.deletable) Action(Icons.Trash, t("android-misc.archive.deleteNamed", "title" to item.title), onDelete)
            }
        }
        Text(
            item.last, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(end = 10.dp),
        )
    }
}

@Composable
private fun Action(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(34.dp).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) {
        IconIn(icon, 16.dp, C.muted)
    }
}
