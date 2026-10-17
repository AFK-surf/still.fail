// A station's files put into a message, as the phone's web does (web/src/mobile/StationFiles.tsx; the wide screen drags
// them from a chat's 文件 tab): ＋'s Station 文件 opens the places (each station's home, for a member who browses every
// folder, and its folders pinned), a folder entered by a tap, the way back as crumbs; files ticked (and the folder shown,
// as a whole), then 添加. Each goes in named by its path (which station has it, and where: the message says so, nothing
// goes up), or as a file where the chat says so; its card, tapped, switches that (a folder of the chat's own station
// goes as a zip). A file goes up as the station stages it (`drive.stage`) on the chat's station, else read from its own
// and sent up.
package fail.still.android.screens

import fail.still.android.ui.Spinner
import fail.still.android.ui.Waiting
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.data.DriveEntry
import fail.still.android.data.DriveFolder
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.drive.DriveCache
import fail.still.android.drive.kindIcon
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Seg
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.DisposableEffect

/**
 * A file or folder of a station's in a draft: which station has it (`station`, its name `stationName`), where (`path`,
 * as the station names it), and how it goes (`mode`: "path", named; "file", sent). `root` and `at`: where it is in that
 * station's drive, to send it as a file.
 */
class RefFile(val station: String, val stationName: String, val path: String, val dir: Boolean, val root: String, val at: String, mode: String) {
    var mode by mutableStateOf(mode)
}

/** Where a file named by its path is, as the message says it (the core's words for it, composer.ts `pathWords`). */
fun pathWords(ref: RefFile): String = t(if (ref.dir) "common.folderOn" else "common.pathOn", "station" to ref.stationName, "path" to ref.path)

/** The draft's key the chat's say is kept by ("<station>:<chat>", as the web keys it). */
private fun chatKey(draft: Draft, station: String) = draft.keptAs ?: "new:$station"

/** A place of a station's drive: the station, a root, a path under it. */
private class Place(val station: String, val stationName: String, val root: String, val rootName: String, val path: String)

/** What is ticked: a file of a folder, or the folder shown, as a whole. */
private class Ticked(val station: String, val stationName: String, val root: String, val at: String, val name: String, val size: Long, val dir: Boolean) {
    val path get() = absoluteOf(root, at)
    val key get() = "$station\n$path"
}

private fun absoluteOf(root: String, path: String) = if (path.isEmpty()) root else root.trimEnd('/', '\\') + "/" + path
private fun joinIn(dir: String, name: String) = if (dir.isEmpty()) name else "$dir/$name"

/** ＋'s Station 文件: the workspace's stations' files, to tick and add to `draft` (its chat on `station`). */
fun openStationFiles(app: AppState, draft: Draft, station: String) {
    app.sheet = SheetSpec(0.86f, draggable = true) {
        var place by remember { mutableStateOf<Place?>(null) }
        val ticked = remember { mutableStateMapOf<String, Ticked>() }
        // How far each folder was scrolled, for one gone back to.
        val scrolls = remember { mutableMapOf<String, Pair<Int, Int>>() }
        fun toggle(x: Ticked) { if (ticked.remove(x.key) == null) ticked[x.key] = x }
        SheetGrab()
        SheetHead(t("web-pages.chat.files"))
        Crumbs(place) { place = it }
        Box(Modifier.weight(1f)) {
            val p = place
            if (p == null) Places(station.substringBefore('/')) { place = it }
            else FolderRows(app, p, scrolls, { ticked.containsKey(it.key) }, ::toggle) { name -> place = Place(p.station, p.stationName, p.root, p.rootName, joinIn(p.path, name)) }
        }
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(if (ticked.isEmpty()) t("web-mobile.files.add") else t("web-mobile.files.addCount", "n" to ticked.size), primary = true, enabled = ticked.isNotEmpty()) {
                val all = ticked.values.toList()
                app.sheet = null
                addRefs(app, draft, station, all)
            }
        }
    }
}

/** The way to the folder shown: all the places, then its station's place and the folders under it; each a way back. */
@Composable
private fun Crumbs(place: Place?, onGo: (Place?) -> Unit) {
    val steps = buildList<Pair<String, Place?>> {
        add(t("web-mobile.files.places") to null)
        if (place != null) {
            add("${place.stationName} · ${place.rootName}" to Place(place.station, place.stationName, place.root, place.rootName, ""))
            place.path.split('/').filter { it.isNotEmpty() }.let { parts ->
                parts.forEachIndexed { i, part -> add(part to Place(place.station, place.stationName, place.root, place.rootName, parts.take(i + 1).joinToString("/"))) }
            }
        }
    }
    val scroll = rememberScrollState()
    LaunchedEffect(steps.size, scroll.maxValue) { scroll.scrollTo(scroll.maxValue) }
    Row(Modifier.fillMaxWidth().heightIn(min = 28.dp).horizontalScroll(scroll).padding(start = 17.dp, end = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        steps.forEachIndexed { i, (name, to) ->
            if (i > 0) IconIn(Icons.ChevronRight, 12.dp, C.subtle)
            val last = i == steps.lastIndex
            Text(
                name, fontSize = 14.sp, color = if (last) C.ink else C.muted, fontWeight = if (last) FontWeight.SemiBold else null, maxLines = 1,
                modifier = Modifier.clip(Smooth(6.dp)).clickable(enabled = !last) { onGo(to) }.padding(horizontal = 3.dp, vertical = 3.dp),
            )
        }
    }
}

/** Each station's places: its home (for a member who browses every folder), then its folders pinned. */
@Composable
private fun Places(scope: String, onGo: (Place) -> Unit) {
    val app = fail.still.android.LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(scope))
    val list = stations.value.orEmpty().filter { it.overview?.drive != null }
    LazyColumn(contentPadding = PaddingValues(bottom = 8.dp)) {
        when {
            stations.value == null -> item { Waiting(text = t("common.reading"), error = stations.error?.message) }
            list.isEmpty() -> item { Note(t("web-main.rail.filesNone")) }
            else -> list.forEach { s ->
                val drive = s.overview!!.drive!!
                item(key = "s:" + s.station) { SectionHeader(s.name, if (s.online) null else t("web-pages.stations.offline")) }
                val home = drive.home
                if (drive.anywhere == true && home != null) item(key = "h:" + s.station) {
                    PickRow(t("web-pages.drive.home"), sub = home, leading = { IconIn(Icons.Server, 20.dp, C.ink) }) { onGo(Place(s.station, s.name, home, t("web-pages.drive.home"), "")) }
                }
                items(drive.roots, key = { "r:" + s.station + "\n" + it.path }) { r ->
                    PickRow(r.name, sub = r.path, leading = { IconIn(Icons.Folder, 20.dp, C.ink) }) { onGo(Place(s.station, s.name, r.path, r.name, "")) }
                }
            }
        }
    }
}

/** A folder: itself to tick as a whole, then what is in it (a folder entered, a file ticked). */
@Composable
private fun FolderRows(app: AppState, p: Place, scrolls: MutableMap<String, Pair<Int, Int>>, ticked: (Ticked) -> Boolean, onToggle: (Ticked) -> Unit, onEnter: (String) -> Unit) {
    val folder by rememberTopic<DriveFolder>(app.core, Topics.drive(p.station, p.root, p.path))
    // Each folder its own scroll: one entered starts at its top, one gone back to is where it was left.
    val key = "${p.station}\n${p.root}\n${p.path}"
    val state = remember(key) { val (i, o) = scrolls[key] ?: (0 to 0); LazyListState(i, o) }
    DisposableEffect(key) { onDispose { scrolls[key] = state.firstVisibleItemIndex to state.firstVisibleItemScrollOffset } }
    val whole = Ticked(p.station, p.stationName, p.root, p.path, if (p.path.isEmpty()) p.rootName else p.path.substringAfterLast('/'), 0, true)
    val of = { e: DriveEntry -> Ticked(p.station, p.stationName, p.root, joinIn(p.path, e.name), e.name, e.size, e.dir) }
    LazyColumn(state = state, contentPadding = PaddingValues(bottom = 8.dp)) {
        item(key = "whole") {
            PickRow(t("web-mobile.files.wholeFolder"), sub = whole.path, checked = ticked(whole), leading = { IconIn(Icons.Folder, 20.dp, C.ink) }) { onToggle(whole) }
            Box(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 4.dp).heightIn(min = 1.dp, max = 1.dp).background(C.line))
        }
        val shown = folder.value
        when {
            shown == null -> item { Waiting(text = t("common.reading"), error = folder.error?.let { it.message ?: t("android-misc.failed") }) }
            fail.still.android.drive.arranged(shown.entries, app.driveSort, app.driveHidden).isEmpty() -> item { Note(t("web-pages.drive.emptyFolder")) }
            else -> items(fail.still.android.drive.arranged(shown.entries, app.driveSort, app.driveHidden), key = { it.name }) { e ->
                val icon: @Composable () -> Unit = { IconIn(kindIcon(e.kind), 20.dp, C.ink) }
                if (e.dir) PickRow(e.name, sub = e.timeText, leading = icon) { onEnter(e.name) }
                else PickRow(e.name, sub = listOf(e.sizeText.ifEmpty { fileSize(e.size) }, e.timeText).filter { it.isNotEmpty() }.joinToString(" · "), checked = ticked(of(e)), leading = icon) { onToggle(of(e)) }
            }
        }
    }
}

@Composable
private fun Note(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))

/** Ticked files into the draft: named by their path, or (where the chat says so) sent as files; a folder only named. */
private fun addRefs(app: AppState, draft: Draft, station: String, all: List<Ticked>) {
    val asFiles = app.dropsAsFiles(chatKey(draft, station))
    all.forEach { x ->
        val ref = RefFile(x.station, x.stationName, x.path, x.dir, x.root, x.at, if (asFiles && !x.dir) "file" else "path")
        val f = Pending(System.nanoTime(), x.name, x.size, null, ref = ref)
        draft.files += f
        if (ref.mode == "file") sendUp(app, draft, station, f)
    }
}

/** A file of a station's switched to go as a file: staged on the chat's station from its own drive (a folder zipped
 *  there), or read from the station that has it and sent up to the chat's. Once up, it is kept, switched back or not. */
private fun sendUp(app: AppState, draft: Draft, station: String, f: Pending) {
    val ref = f.ref ?: return
    if (f.done != null || (f.error == null && f.sent != null)) return
    f.error = null
    f.sent = 0
    app.scope.launch {
        try {
            f.done = if (ref.station == station) app.api(station).driveStage(ref.root, ref.at, zip = ref.dir)
            else {
                val kept = DriveCache.fetch(app.api(ref.station), ref.root, ref.at, 0, f.size)
                app.api(station).upload(f.name, kept.file.length(), { kept.file.inputStream() }, null, null) { f.sent = it }
            }
            draft.save()
        } catch (e: CoreException) {
            f.error = e.message
        } catch (_: java.io.IOException) {
            f.error = t("android-chat.file.uploadFailed")
        } finally {
            if (f.done == null) f.sent = null
        }
    }
}

/**
 * A file of a station's in the composer: its name, and where it is (named by its path: outlined, dashed, as it stays
 * where it is) or how it goes up; tapped, RefSheet.
 */
@Composable
internal fun RefCard(f: Pending, onRemove: () -> Unit, shape: Shape, onClick: () -> Unit) {
    val ref = f.ref!!
    val named = f.named
    val busy = !named && f.done == null && f.error == null
    val zipped = !named && ref.dir
    val name = if (zipped) "${f.name}.zip" else f.name
    val note = when {
        named -> "${ref.stationName} · ${t("web-main.file.modePath")}"
        f.error != null -> f.error!!
        busy -> uploadingText(f)
        else -> fileSize(f.done?.size ?: f.size)
    }
    val line = C.ink.copy(alpha = 0.22f)
    Row(
        Modifier.width(236.dp).clip(shape)
            .let { if (named) it.drawBehind { drawOutline(shape.createOutline(size, layoutDirection, this), line, style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx())))) } else it.background(chatInk().neutral) }
            .clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (busy) Spinner() else IconIn(if (ref.dir && named) Icons.Folder else Icons.Read, 16.dp, C.muted)
        Column(Modifier.weight(1f)) {
            Text(name, fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(note, fontSize = 11.sp, lineHeight = 16.sp, color = if (f.error != null && !named) C.red else C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        Box(Modifier.size(22.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.06f)).clickable(onClick = onRemove), contentAlignment = Alignment.Center) {
            IconIn(Icons.Close, 12.dp, C.muted)
        }
    }
}

/**
 * A file of a station's in the composer, tapped (the wide screen's card says this on hover): its name, where it is, how
 * it goes (its path, or the file; a folder of the chat's own station as a zip), and whether this chat takes such files
 * as files.
 */
fun openRefSheet(app: AppState, draft: Draft, f: Pending, station: String) {
    val ref = f.ref ?: return
    val zips = ref.dir && ref.station == station
    app.sheet = SheetSpec(0.42f) {
        val key = chatKey(draft, station)
        val where = ref.path.substring(0, maxOf(ref.path.lastIndexOf('/'), ref.path.lastIndexOf('\\')).coerceAtLeast(0)).ifEmpty { ref.path }
        SheetGrab()
        SheetHead(f.name)
        Text("${ref.stationName} · $where", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 14.dp))
        if (!ref.dir || zips) Column(Modifier.padding(start = 20.dp, end = 20.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(t("web-main.file.sendAs"), fontSize = 13.sp, color = C.muted)
            Seg(listOf(t("web-main.file.modePath"), t(if (ref.dir) "web-main.file.modeZip" else "web-main.file.modeFile")), if (ref.mode == "path") 0 else 1, { i ->
                ref.mode = if (i == 0) "path" else "file"
                if (ref.mode == "file") sendUp(app, draft, station, f)
            }, fill = true)
        }
        var chat by remember { mutableStateOf(app.dropsAsFiles(key)) }
        Row(
            Modifier.padding(start = 20.dp, end = 20.dp, bottom = 14.dp).fillMaxWidth().clip(Smooth(14.dp)).background(C.chip)
                .clickable { chat = !chat; app.setDropsAsFiles(key, chat) }.padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(t("web-main.file.chatAsFiles"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = C.ink, modifier = Modifier.weight(1f))
            Switch(chat)
        }
    }
}
