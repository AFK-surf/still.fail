// A station's drive (docs/drive.md): the folders it lends its members, one page per folder (App.kt Screen.Drive), so
// going in and coming back is the stack's slide and the edge swipe. One root shows what is in it at once; several are
// listed as folders, one that cannot be browsed in red with why. A row opens by its kind: a folder goes in, text and
// Markdown are read (Reader.kt), video and audio play (Player.kt), pictures, PDFs, code, tables and pages open in the
// chat's viewer (FilePreview.kt), the rest goes to another app. Held, a row is chosen (others then by a tap, as the
// phone's own file managers do), and what is chosen is downloaded, its paths copied, deleted (to the machine's trash
// where the station has one), one renamed or shared. The order and whether hidden files show are the device's, as the
// web's (prefs `driveViews`); a folder shown is kept as it is on the station's disk (the core watches it).
// The workspace's owners and admins choose the folders (⋯); read-only members get no way to change anything. Laid out
// as the phone web's (web/src/mobile/Drive.tsx), the reference for the phone (docs/mobile-parity.md).
package fail.still.android.drive

import androidx.compose.ui.graphics.Color
import fail.still.android.ui.CARD_PAD
import fail.still.android.ui.LIST_ROW_CORNER
import fail.still.android.ui.LIST_PAD
import fail.still.android.ui.LIST_CARD_CORNER
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import fail.still.android.ui.pressText
import fail.still.android.ui.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.Attachment
import fail.still.android.data.DriveEntry
import fail.still.android.data.DriveFolder
import fail.still.android.data.DriveFolders
import fail.still.android.data.DrivePlace
import fail.still.android.data.DriveRoot
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceView
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.ui.Button
import fail.still.android.ui.DoingMark
import fail.still.android.screens.DriveKey
import fail.still.android.ui.PickRow
import fail.still.android.screens.Shown
import fail.still.android.screens.ask
import fail.still.android.screens.confirm
import fail.still.android.screens.download
import fail.still.android.ui.fileSize
import fail.still.android.ui.C
import fail.still.android.ui.DownloadChip
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.android.ui.Progress
import fail.still.android.ui.Spinner
import fail.still.android.ui.WaitLine
import fail.still.android.ui.Waiting
import fail.still.core.CoreException
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.compose.foundation.lazy.items
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import fail.still.android.data.DriveCrumb
import fail.still.android.data.PickFolder
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.kindIcon
import fail.still.android.data.DriveCache
import fail.still.android.data.arranged
import fail.still.android.data.freeName
import fail.still.android.data.picked
import fail.still.android.screens.Elsewhere

// ── what an entry is ────────────────────────────────────────────────────

/** A path under a root, `/` between its components; `dir` empty for the root itself. */
fun join(dir: String, name: String) = if (dir.isEmpty()) name else "$dir/$name"
fun parentOf(path: String) = path.substringBeforeLast('/', "")
fun nameOf(path: String) = path.substringAfterLast('/')

/** What a root is called: its name as the station lends it, else its path's last part. */
fun rootLabel(roots: List<DriveRoot>?, root: String) = roots?.firstOrNull { it.path == root }?.name ?: root.trimEnd('/', '\\').substringAfterLast('/').ifEmpty { root }

/** Why a root cannot be browsed (in red) and what to do about it; null while it can (web drive/useDrive.ts rootTrouble). */
fun rootTrouble(state: String): Pair<String, String>? = when (state) {
    "ok" -> null
    "missing" -> t("android-misc.drive.root.missing") to t("android-misc.drive.root.missingHint")
    "not_a_directory" -> t("android-misc.drive.root.notFolder") to t("android-misc.drive.root.notFolderHint")
    else -> t("android-misc.drive.root.unreadable") to t("android-misc.drive.root.unreadableHint")
}

/** Where a path under a root is on the station. */
fun absoluteIn(root: String, path: String) = if (path.isEmpty()) root else root.trimEnd('/', '\\') + "/" + path

/** What a name a file or folder may have says is wrong with it (empty, a slash, . or ..); null when nothing is. */
fun nameProblem(name: String): String? {
    val n = name.trim()
    if (n.isEmpty()) return t("android-misc.drive.name.empty")
    if ('/' in n || '\\' in n || n == "." || n == "..") return t("android-misc.drive.name.bad")
    return null
}

/** What the viewer may do with a station's drive: name the folders it lends (owners and admins), change what is in them (not a read-only member). */
private class DriveRights(val manage: Boolean, val write: Boolean, val trash: Boolean = false, val zip: Boolean = false)

@Composable
private fun rights(current: WorkspaceEntry, s: StationView?): DriveRights {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    val drive = s?.overview?.drive
    return DriveRights(manage = ws.value?.manager == true, write = s?.overview?.viewer?.role != "viewer" && ws.value?.role != "viewer", trash = drive?.trash == true, zip = drive?.zip == true)
}

// ── uploads ─────────────────────────────────────────────────────────────

/**
 * A file going up into a folder of a drive, shown in its folder's list until it is there: how much of it the station
 * has; its name taken there (`taken`: replace it or keep both); why it failed (`failed`: tried again or let go).
 */
class DriveUpload(val station: String, val root: String, val dir: String, name: String, val uri: Uri) {
    var name by mutableStateOf(name)
    var size by mutableLongStateOf(0L)
    var sent by mutableLongStateOf(0L)
    /** waiting | going | taken | failed */
    var state by mutableStateOf("waiting")
    var error by mutableStateOf<String?>(null)
    internal var job: Job? = null
    internal var answer: CompletableDeferred<Boolean?>? = null
    /** Replace a file of its name when it goes up. */
    internal var replace = false
    /** What its folder holds now, for a name taken there and another to keep both by. */
    internal var held: () -> List<DriveEntry> = { emptyList() }
}

/** The uploads, whatever page is shown (they go on past the page that started them), one going at a time. */
object DriveUploads {
    val list = mutableStateListOf<DriveUpload>()
    private var pumping = false

    fun add(app: AppState, context: Context, ups: List<DriveUpload>, held: () -> List<DriveEntry>) {
        ups.forEach { it.held = held }
        list += ups
        pump(app, context)
    }

    /** Its name taken: replaced (`true`) or both kept (`false`). */
    fun settle(up: DriveUpload, replace: Boolean) { up.answer?.complete(replace) }

    /** Let go: off the list, what it was doing stopped. */
    fun cancel(up: DriveUpload) { up.answer?.complete(null); up.job?.cancel(); list.remove(up) }

    /** Failed: tried again from the start. */
    fun retry(app: AppState, context: Context, up: DriveUpload, held: () -> List<DriveEntry>) { up.held = held; up.state = "waiting"; up.error = null; up.sent = 0; pump(app, context) }

    private fun pump(app: AppState, context: Context) {
        if (pumping) return
        pumping = true
        app.scope.launch {
            try {
                while (true) {
                    val up = list.firstOrNull { it.state == "waiting" } ?: break
                    val job = launch { send(app, context, up) }
                    up.job = job
                    job.join()
                }
            } finally { pumping = false }
        }
    }

    private suspend fun send(app: AppState, context: Context, up: DriveUpload) {
        val held = up.held
        val resolver = context.contentResolver
        up.state = "going"
        try {
            val (_, known) = withContext(Dispatchers.IO) { picked(resolver, up.uri) }
            // A provider that does not say how big it is: read it once to know.
            up.size = if (known >= 0) known else withContext(Dispatchers.IO) { resolver.openInputStream(up.uri)?.use { s -> s.skip(Long.MAX_VALUE) } ?: 0L }
            val open = { resolver.openInputStream(up.uri) ?: throw java.io.IOException(t("android-misc.drive.upload.unreadable")) }
            while (true) {
                try {
                    app.api(up.station).driveUpload(up.root, join(up.dir, up.name), up.size, open, up.replace) { up.sent = it }
                    list.remove(up)
                    return
                } catch (e: CoreException) {
                    // Its name taken by a file (a folder of that name cannot be replaced): asked here, in its row.
                    if (e.status != 409 || up.replace || held().any { it.name == up.name && it.dir }) throw e
                    val answer = CompletableDeferred<Boolean?>()
                    up.answer = answer
                    up.state = "taken"
                    val replace = answer.await() ?: return
                    up.answer = null
                    up.state = "going"
                    up.sent = 0
                    if (replace) up.replace = true
                    else up.name = freeName(up.name, held().map { it.name }.toSet() + list.filter { it !== up && it.dir == up.dir }.map { it.name })
                }
            }
        } catch (e: CoreException) {
            up.state = "failed"; up.error = e.message
        } catch (e: java.io.IOException) {
            up.state = "failed"; up.error = e.message ?: ""
        }
    }
}

/** Puts the files picked into a folder of the drive, one after another, each a row in that folder's list while it goes. */
fun uploadInto(app: AppState, context: Context, station: String, root: String, dir: String, uris: List<Uri>, held: () -> List<DriveEntry>) {
    if (uris.isEmpty()) return
    val resolver = context.contentResolver
    app.scope.launch {
        val ups = uris.map { uri -> DriveUpload(station, root, dir, withContext(Dispatchers.IO) { picked(resolver, uri).first }, uri) }
        DriveUploads.add(app, context, ups, held)
    }
}

// ── fetching for another app ────────────────────────────────────────────

/** Files of the drive being fetched to hand to another app (or to Downloads): how far each has come (0–100), by station and path. */
object DriveFetches {
    val progress = mutableStateMapOf<String, Long>()
    fun id(station: String, root: String, path: String) = "$station\n$root\n$path"
}

/** A file of the drive kept on the phone (DriveCache; for another app to open, or to save), fetched a part at a time with its progress shown on its row. */
private suspend fun fetched(app: AppState, context: Context, station: String, root: String, entry: DriveEntry, path: String): File {
    val id = DriveFetches.id(station, root, path)
    DriveFetches.progress[id] = 0
    try {
        return DriveCache.fetch(app.api(station), root, path, entry.mtime, entry.size) { at, total -> DriveFetches.progress[id] = if (total > 0) at * 100 / total else 0 }.file
    } finally {
        DriveFetches.progress.remove(id)
    }
}

/** How another app is handed a file: to open it (VIEW) or to share it (SEND). */
private fun hand(context: Context, file: File, type: String, share: Boolean): Boolean {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val mime = type.ifEmpty { "application/octet-stream" }
    val intent = if (share) Intent(Intent.ACTION_SEND).setType(mime).putExtra(Intent.EXTRA_STREAM, uri)
    else Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    return try {
        context.startActivity(Intent.createChooser(intent, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true
    } catch (_: ActivityNotFoundException) { false }
}

/** Fetches a file and hands it to another app (`share`: to send it somewhere; else to open it). */
fun openElsewhere(app: AppState, context: Context, station: String, root: String, entry: DriveEntry, path: String, share: Boolean) {
    app.scope.launch {
        try {
            val file = fetched(app, context, station, root, entry, path)
            if (!hand(context, file, entry.type, share)) app.toast = t("android-misc.drive.noApp")
        } catch (e: CoreException) {
            app.toast = t("android-misc.drive.fetchFailed", "name" to entry.name, "error" to e.message)
        }
    }
}

/** Fetches a file into the phone's Downloads. */
fun saveToDownloads(app: AppState, context: Context, station: String, root: String, entry: DriveEntry, path: String) {
    app.scope.launch {
        try {
            val file = fetched(app, context, station, root, entry, path)
            app.toast = if (download(context, entry.name, file)) t("android-chat.file.saved") else t("android-chat.file.saveFailed")
        } catch (e: CoreException) {
            app.toast = t("android-misc.drive.fetchFailed", "name" to entry.name, "error" to e.message)
        }
    }
}

// ── the page ────────────────────────────────────────────────────────────

/** A sheet's height for a title and `rows` rows (a sheet is as tall as what it holds). */
private fun fit(rows: Int) = (96 + rows * 48 + 24).dp

/**
 * A page of a station's drive (as the phone web's, web/src/mobile/Drive.tsx): `root` null is the drive itself (its one
 * root's contents, or its roots as folders); else the folder `path` under `root`.
 */
@Composable
fun DriveScreen(current: WorkspaceEntry, station: String, root: String?, path: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == station }
    val roots = s?.overview?.drive?.roots
    val can = rights(current, s)
    // The drive's own page with one root, and nothing wrong with it: what is in it is the page.
    val only = roots?.singleOrNull()?.takeIf { it.state == "ok" }?.path
    val folderRoot = root ?: only
    if (s == null || roots == null || folderRoot == null) return RootsPage(app, station, s, roots, stations.error?.message, can)
    FolderPage(app, station, s, roots, folderRoot, path, top = root == null, can)
}

@Composable
private fun RootsPage(app: AppState, station: String, s: StationView?, roots: List<DriveRoot>?, error: String?, can: DriveRights) {
    Column(Modifier.fillMaxSize().background(C.bg)) {
        NavBar(s?.name ?: "", app::pop, t("android-misc.drive.title"), trailing = if (can.manage && !roots.isNullOrEmpty()) ({
            NavButton(Icons.More, { openRoots(app, station) })
        }) else null)
        when {
            // The station's folders lent still on their way (or what kept them), as every list's first read.
            roots == null && (error != null || s?.overview == null) -> Waiting(text = t("common.reading"), error = error)
            roots == null -> Note(t("android-misc.drive.oldStation"))
            roots.isEmpty() -> Empty(if (can.manage) t("android-misc.drive.none.manager") else t("android-misc.drive.none.member")) {
                if (can.manage) Button(t("android-misc.drive.choose"), primary = true) { openFolderPicker(app, station, emptyList()) }
            }
            else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 30.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding())) {
                item(key = "count") { Count(t("android-misc.drive.roots.count", "n" to roots.size)) }
                itemsIndexed(roots, key = { _, r -> r.path }) { i, r -> RootRow(app, station, r, roots, i == 0, i == roots.lastIndex, can.manage) }
            }
        }
    }
}

/** A folder lent: its name, where it is; one that cannot be browsed now with why in red and what to do about it. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun RootRow(app: AppState, station: String, r: DriveRoot, roots: List<DriveRoot>, first: Boolean, last: Boolean, manage: Boolean) {
    val c = C
    val trouble = rootTrouble(r.state)
    Row(
        Modifier.cardRow(first, last, c.surface)
            .combinedClickable(onClick = { app.push(Screen.Drive(station, r.path, "")) }, onLongClick = if (manage) ({
                app.sheet = SheetSpec(0.3f, fit = fit(1)) {
                    SheetGrab()
                    SheetHead(r.name)
                    PickRow(t("android-misc.drive.roots.stop"), color = C.link, leading = { IconIn(Icons.Close, 20.dp, C.accent) }) { unshare(app, station, roots, r) }
                }
            }) else null)
            .padding(horizontal = CARD_PAD - LIST_PAD, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconIn(Icons.Folder, 22.dp, c.muted)
        Column(Modifier.weight(1f)) {
            Text(r.name, fontSize = 15.sp, lineHeight = 20.sp, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(r.path, fontSize = 12.sp, lineHeight = 16.sp, color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (trouble != null) {
                Text(trouble.first, fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold, color = c.red, modifier = Modifier.padding(top = 3.dp))
                Text(trouble.second, fontSize = 12.sp, lineHeight = 16.sp, color = c.muted)
            }
        }
        IconIn(Icons.ChevronRight, 14.dp, c.subtle)
    }
}

private fun unshare(app: AppState, station: String, roots: List<DriveRoot>, r: DriveRoot) {
    confirm(app, t("android-misc.drive.roots.stopTitle", "name" to r.name), t("android-misc.drive.roots.stopText"), t("android-misc.drive.roots.stop"), danger = true, what = t("android-misc.drive.roots.what")) {
        app.api(station).driveSetRoots(roots.map { it.path } - r.path)
    }
}

/** A folder: back to where it was opened from, its name; where it is under its root (each step a tap away), what it holds in a line, its entries. */
@Composable
private fun FolderPage(app: AppState, station: String, s: StationView, roots: List<DriveRoot>, root: String, path: String, top: Boolean, can: DriveRights) {
    val context = LocalContext.current
    val c = C
    val folder by rememberTopic<DriveFolder>(app.core, Topics.drive(station, root, path))
    val entries = folder.value?.entries.orEmpty()
    val latest by rememberUpdatedState(entries)
    val held = { latest }
    val home = s.overview?.drive?.home
    val name = if (path.isNotEmpty()) nameOf(path) else if (root == home && roots.none { it.path == root }) t("web-pages.drive.home") else rootLabel(roots, root)
    val back = when {
        top -> s.name
        path.isEmpty() -> t("android-misc.drive.title")
        parentOf(path).isEmpty() -> rootLabel(roots, root)
        else -> nameOf(parentOf(path))
    }
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    var previewing by remember { mutableStateOf<DriveEntry?>(null) }
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> uploadInto(app, context, station, root, path, uris, held) }
    fun upload() = pick.launch(arrayOf("*/*"))
    fun reload() {
        if (refreshing) return
        scope.launch {
            refreshing = true
            try { app.api(station).driveRefresh(root, path) } catch (e: CoreException) { app.toast = t("android-misc.act.failed", "what" to t("android-misc.drive.refreshWhat"), "error" to e.message) } finally { refreshing = false }
        }
    }
    val uploads = DriveUploads.list.filter { it.station == station && it.root == root && it.dir == path }
    val shownEntries = arranged(entries, app.driveSort, app.driveHidden)
    // What is chosen (a row held, then others tapped), by name: what the bar on top then acts on.
    val chosen = remember(station, root, path) { mutableStateListOf<String>() }
    val choosing = chosen.isNotEmpty()
    BackHandler(enabled = choosing) { chosen.clear() }
    val chosenEntries = { entries.filter { it.name in chosen } }

    Column(Modifier.fillMaxSize().background(c.bg)) {
        if (choosing) NavBar(t("common.cancel"), { chosen.clear() }, t("android-misc.drive.chosen", "n" to chosen.size), trailing = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    t(if (chosen.size == shownEntries.size) "android-misc.drive.chooseNone" else "android-misc.drive.chooseAll"), fontSize = 15.sp, color = c.link,
                    modifier = Modifier.clip(Smooth(6.dp)).clickable { if (chosen.size == shownEntries.size) chosen.clear() else { chosen.clear(); chosen.addAll(shownEntries.map { it.name }) } }.padding(horizontal = 8.dp, vertical = 6.dp),
                )
                Box(Modifier.semantics { contentDescription = t("android-misc.drive.chosenActions") }) {
                    NavButton(Icons.More, { openChosenSheet(app, context, station, root, path, chosenEntries(), can, entries.map { it.name }.toSet()) { chosen.clear() } })
                }
            }
        }) else NavBar(back, app::pop, name, trailing = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(34.dp).clip(CircleShape).clickable(enabled = !refreshing) { reload() }.semantics { contentDescription = t("android-misc.drive.refresh") }, contentAlignment = Alignment.Center) {
                    if (refreshing) Spinner() else IconIn(Icons.Refresh, 18.dp)
                }
                when {
                    can.write -> Box(Modifier.semantics { contentDescription = t("android-misc.drive.add") }) {
                        NavButton(Icons.Plus, {
                            val rows = if (can.manage && top) 3 else 2
                            app.sheet = SheetSpec(0.4f, fit = fit(rows)) {
                                SheetGrab()
                                SheetHead(name)
                                PickRow(t("android-misc.drive.upload"), leading = { IconIn(Icons.Upload, 20.dp, C.ink) }) { app.sheet = null; upload() }
                                PickRow(t("android-misc.drive.mkdir"), leading = { IconIn(Icons.FolderPlus, 20.dp, C.ink) }) { newFolder(app, station, root, path) }
                                if (can.manage && top) PickRow(t("android-misc.drive.roots.manage"), leading = { IconIn(Icons.Folder, 20.dp, C.ink) }) { openRoots(app, station) }
                            }
                        }, 20.dp)
                    }
                }
                // How the folder is shown (its order, hidden files), and the folders lent for those who name them.
                Box(Modifier.semantics { contentDescription = t("android-misc.drive.view") }) { NavButton(Icons.More, { openViewSheet(app, station, can.manage && top) }) }
            }
        })
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 30.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding())) {
            if (path.isNotEmpty()) item(key = "crumbs") { Crumbs(app, station, root, rootLabel(roots, root), path) }
            val error = folder.error
            val value = folder.value
            // Not read now (the station away, the folder refused): what was read last stays, said to be so.
            if (error != null && value != null) item(key = "stale") {
                Row(Modifier.padding(horizontal = 20.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(t("android-misc.drive.stale", "error" to (error.message ?: "")), fontSize = 13.sp, color = c.muted, modifier = Modifier.weight(1f, fill = false), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Text(t("android-misc.drive.retry"), fontSize = 13.sp, color = c.link, modifier = Modifier.clip(Smooth(6.dp)).clickable { reload() }.padding(4.dp))
                }
            }
            when {
                error != null && value == null -> item(key = "error") {
                    Row(Modifier.padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(error.message, fontSize = 14.sp, color = c.red, modifier = Modifier.weight(1f, fill = false))
                        Text(t("android-misc.drive.retry"), fontSize = 14.sp, color = c.link, modifier = Modifier.clip(Smooth(6.dp)).clickable { reload() }.padding(4.dp))
                    }
                }
                value == null -> item(key = "reading") { Waiting(text = t("common.reading")) }
                else -> {
                    item(key = "count") { Count(value.countText + if (value.truncated == true) " · " + t("android-misc.drive.truncated") else "") }
                    itemsIndexed(uploads, key = { _, u -> "up:" + System.identityHashCode(u) }) { i, u -> UploadRow(app, context, u, i == 0, i == uploads.lastIndex, held) }
                    if (shownEntries.isEmpty() && uploads.isEmpty()) item(key = "empty") {
                        Empty(t("android-misc.drive.empty")) { if (can.write) Button(t("android-misc.drive.upload"), primary = false) { upload() } }
                    }
                    itemsIndexed(shownEntries, key = { _, e -> "e:" + e.name }) { i, e ->
                        val full = join(path, e.name)
                        val toggle = { if (e.name in chosen) chosen.remove(e.name) else chosen.add(e.name); Unit }
                        EntryRow(station, root, full, e, i == 0, i == shownEntries.lastIndex, chosen = if (choosing) e.name in chosen else null,
                            onOpen = { if (choosing) toggle() else open(app, context, station, root, path, e) { previewing = it } },
                            // Held: chosen, as the phone's own file managers do; what is chosen is acted on from the bar.
                            onHold = toggle,
                        )
                    }
                }
            }
        }
    }
    // Pictures, PDFs, code, tables and pages: the chat's viewer, over the page; a picture steps to the folder's others.
    val shown = previewing
    if (shown != null) {
        val shownOf = { e: DriveEntry -> Shown(DriveKey.of(root, e.mtime), Attachment(e.name, join(path, e.name), e.size)) }
        val opened = remember(shown) { shownOf(shown) }
        Elsewhere.preview(station, opened, { latest.filter { it.kind == "image" }.map(shownOf) }) { previewing = null }
    }
}

/** The line over a list: what it holds. */
@Composable
private fun Count(text: String) = Text(text, fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.padding(start = 24.dp, end = 20.dp, top = 2.dp, bottom = 6.dp))

@Composable
private fun Note(text: String) {
    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { Text(text, color = C.muted, fontSize = 14.sp, textAlign = TextAlign.Center) }
}

/** Nothing here: a folder's mark, why, and what can be done about it. */
@Composable
private fun Empty(text: String, action: @Composable () -> Unit = {}) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 56.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        IconIn(Icons.Folder, 40.dp, C.subtle)
        Text(text, fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
        action()
    }
}

/**
 * Card rows in a lazy list: each row its part of one rounded card (the first and last carry its corners), a list card's
 * (ui/Parts.kt RowsCard): each row's own ground (pressed, chosen) LIST_PAD in from the card's edge and rounded
 * LIST_ROW_CORNER, concentric with it; its words CARD_PAD in.
 */
private fun cardShape(first: Boolean, last: Boolean) = Smooth(
    topStart = if (first) LIST_CARD_CORNER else 0.dp, topEnd = if (first) LIST_CARD_CORNER else 0.dp,
    bottomEnd = if (last) LIST_CARD_CORNER else 0.dp, bottomStart = if (last) LIST_CARD_CORNER else 0.dp,
)

private fun Modifier.cardRow(first: Boolean, last: Boolean, ground: Color) =
    padding(horizontal = 12.dp).padding(bottom = if (last) 10.dp else 0.dp).fillMaxWidth().clip(cardShape(first, last)).background(ground)
        .padding(start = LIST_PAD, end = LIST_PAD, top = if (first) LIST_PAD else 0.dp, bottom = if (last) LIST_PAD else 0.dp).clip(Smooth(LIST_ROW_CORNER))

/** Where the folder is under its root: the root, then each folder down to this one, each but the last a way back to it. */
@Composable
private fun Crumbs(app: AppState, station: String, root: String, rootName: String, path: String) {
    val parts = path.split('/').filter { it.isNotEmpty() }
    val levels = listOf(rootName to Screen.Drive(station, root, "")) + parts.mapIndexed { i, p -> p to Screen.Drive(station, root, parts.take(i + 1).joinToString("/")) }
    val scroll = rememberScrollState()
    // The end of a long path is what matters: in view.
    LaunchedEffect(path, scroll.maxValue) { scroll.scrollTo(scroll.maxValue) }
    Row(Modifier.fillMaxWidth().horizontalScroll(scroll).padding(start = 21.dp, end = 20.dp, top = 2.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        levels.forEachIndexed { i, (label, to) ->
            if (i > 0) IconIn(Icons.ChevronRight, 12.dp, C.subtle)
            val last = i == levels.lastIndex
            Text(
                label, fontSize = 13.sp, color = if (last) C.ink else C.muted, fontWeight = if (last) FontWeight.SemiBold else null, maxLines = 1,
                modifier = Modifier.clip(Smooth(6.dp)).clickable(enabled = !last) {
                    // Back to it where it is in the stack; else opened there.
                    // The root as the drive's own page with one root has it (no root named) is the same page.
                    val at = app.stack.indexOfLast { it == to || (to.path.isEmpty() && it is Screen.Drive && it.station == station && it.root == null && it.path.isEmpty()) }
                    if (at >= 0) repeat(app.stack.size - 1 - at) { app.pop() } else app.push(to)
                }.padding(horizontal = 3.dp, vertical = 2.dp),
            )
        }
    }
}

/** Opens an entry as its kind wants. */
private fun open(app: AppState, context: Context, station: String, root: String, dir: String, e: DriveEntry, preview: (DriveEntry) -> Unit) {
    val path = join(dir, e.name)
    when (e.kind) {
        "folder" -> app.push(Screen.Drive(station, root, path))
        "text", "markdown" -> app.push(Screen.DriveRead(station, root, path))
        "video", "audio" -> app.push(Screen.DrivePlay(station, root, path))
        "image", "pdf", "code", "csv", "html", "subtitle" -> preview(e)
        else -> openElsewhere(app, context, station, root, e, path, share = false)
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EntryRow(station: String, root: String, path: String, e: DriveEntry, first: Boolean, last: Boolean, chosen: Boolean? = null, onOpen: () -> Unit, onHold: () -> Unit) {
    val app = LocalApp.current
    val c = C
    val busy = app.isDoing("drive.remove", "root" to root, "path" to path) || app.isDoing("drive.rename", "root" to root, "from" to path)
    val failed = app.failedOf("drive.remove", "root" to root, "path" to path) ?: app.failedOf("drive.rename", "root" to root, "from" to path)
    val fetching = DriveFetches.progress[DriveFetches.id(station, root, path)]
    Row(
        Modifier.cardRow(first, last, c.surface).background(if (chosen == true) c.accent.copy(alpha = 0.12f) else c.surface).combinedClickable(enabled = !busy, onClick = onOpen, onLongClick = onHold).padding(horizontal = CARD_PAD - LIST_PAD, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Choosing: each row's mark says whether it is chosen.
        if (chosen != null) Box(Modifier.size(22.dp).clip(CircleShape).background(if (chosen) c.accent else c.ink.copy(alpha = 0.08f)), contentAlignment = Alignment.Center) {
            if (chosen) IconIn(Icons.Check, 14.dp, c.surface)
        }
        else IconIn(kindIcon(e.kind), 22.dp, c.muted)
        Column(Modifier.weight(1f)) {
            Text(e.name, fontSize = 15.sp, lineHeight = 20.sp, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val line = if (e.dir) e.timeText else listOf(e.sizeText, e.timeText).filter { it.isNotEmpty() }.joinToString(" · ")
            if (line.isNotEmpty()) Text(line, fontSize = 12.sp, lineHeight = 16.sp, color = c.muted, maxLines = 1)
        }
        when {
            busy || failed != null -> DoingMark(busy, failed, inline = true)
            fetching != null -> DownloadChip(fetching)
            e.kind == "text" || e.kind == "markdown" -> ReadShare(station, root, path)
            e.dir -> IconIn(Icons.ChevronRight, 14.dp, c.subtle)
        }
    }
}

/** A file going up: its name, how far it has got (a thin bar); its name taken there (replace or keep both), or why it failed. */
@Composable
private fun UploadRow(app: AppState, context: Context, u: DriveUpload, first: Boolean, last: Boolean, held: () -> List<DriveEntry>) {
    val c = C
    Row(
        Modifier.cardRow(first, last, c.surface).padding(start = CARD_PAD - LIST_PAD, end = 0.dp, top = 11.dp, bottom = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconIn(Icons.Upload, 22.dp, c.muted)
        Column(Modifier.weight(1f)) {
            Text(u.name, fontSize = 15.sp, lineHeight = 20.sp, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            when (u.state) {
                "taken" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(t("android-misc.drive.exists.title"), fontSize = 12.sp, lineHeight = 16.sp, color = c.muted)
                    Text(t("android-misc.drive.exists.replace"), fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold, color = c.link, modifier = Modifier.pressText { DriveUploads.settle(u, true) })
                    Text(t("android-misc.drive.exists.both"), fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.SemiBold, color = c.link, modifier = Modifier.pressText { DriveUploads.settle(u, false) })
                }
                "failed" -> Text(t("android-misc.drive.upload.failed", "error" to (u.error ?: "")), fontSize = 12.sp, lineHeight = 16.sp, color = c.red, maxLines = 2, overflow = TextOverflow.Ellipsis)
                else -> {
                    Text(t("android-misc.drive.upload.going", "sent" to fileSize(u.sent), "size" to fileSize(u.size)), fontSize = 12.sp, lineHeight = 16.sp, color = c.muted, maxLines = 1)
                    // Its size not known: a sweep.
                    Progress(if (u.size > 0) u.sent.toFloat() / u.size else null, Modifier.padding(top = 5.dp))
                }
            }
        }
        if (u.state == "failed") RowKey(Icons.Retry, t("android-misc.drive.retry")) { DriveUploads.retry(app, context, u, held) }
        RowKey(Icons.Close, t("common.cancel")) { DriveUploads.cancel(u) }
    }
}

@Composable
private fun RowKey(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(34.dp).clip(CircleShape).clickable(onClick = onClick).semantics { contentDescription = label }, contentAlignment = Alignment.Center) { IconIn(icon, 16.dp, C.muted) }
}

/** How far a text has been read on this device, when it has been opened: grey, as every ordinary figure is. */
@Composable
private fun ReadShare(station: String, root: String, path: String) {
    val app = LocalApp.current
    val place by rememberTopic<DrivePlace>(app.core, Topics.drivePlace(station, root, path))
    val p = place.value ?: return
    val of = p.of?.takeIf { it > 0 } ?: return
    val share = (p.at / of).coerceIn(0.0, 1.0)
    // Opened and left at its start: nothing read yet.
    if (share < 0.01) return
    Text(if (share >= 0.995) t("android-misc.drive.read.done") else "${(share * 100).toInt()}%", fontSize = 12.sp, color = C.muted)
}

// ── what can be done to an entry ────────────────────────────────────────

/** How a folder is shown on this device, as the web's: its order, and whether hidden files show; with the folders lent, for those who name them. */
private fun openViewSheet(app: AppState, station: String, manage: Boolean) {
    val sorts = listOf("name", "time", "size", "kind")
    app.sheet = SheetSpec(0.5f, fit = fit(sorts.size + 1 + if (manage) 1 else 0)) {
        SheetGrab()
        SheetHead(t("android-misc.drive.view"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            sorts.forEach { by ->
                PickRow(t("web-pages.drive.sortBy.$by"), checked = app.driveSort.substringBefore('-') == by) { app.setDriveView("sort", if (by == "name") null else by) }
            }
            PickRow(t("web-pages.drive.showHidden"), checked = app.driveHidden) { app.setDriveView("hidden", if (app.driveHidden) null else "shown") }
            if (manage) PickRow(t("android-misc.drive.roots.manage"), leading = { IconIn(Icons.Folder, 20.dp, C.ink) }) { openRoots(app, station) }
        }
    }
}

/** What is chosen, from the bar over it: one as a row held always was (rename, download, share…); several downloaded, their paths copied, deleted. */
private fun openChosenSheet(app: AppState, context: Context, station: String, root: String, dir: String, items: List<DriveEntry>, can: DriveRights, names: Set<String>, done: () -> Unit) {
    if (items.isEmpty()) return
    if (items.size == 1) return openEntrySheet(app, context, station, root, dir, items[0], can, names, done)
    val files = items.filter { !it.dir }
    app.sheet = SheetSpec(0.4f, fit = fit((if (files.isNotEmpty()) 1 else 0) + 1 + if (can.write) 1 else 0)) {
        SheetGrab()
        SheetHead(t("android-misc.drive.chosen", "n" to items.size))
        if (files.isNotEmpty()) PickRow(t("web-pages.drive.downloadMany", "n" to files.size), leading = { IconIn(Icons.Download, 20.dp, C.ink) }) {
            app.sheet = null; done()
            files.forEach { saveToDownloads(app, context, station, root, it, join(dir, it.name)) }
        }
        PickRow(t("web-pages.drive.copyPaths"), leading = { IconIn(Icons.Copy, 20.dp, C.ink) }) {
            app.sheet = null; done()
            copyPaths(app, context, items.map { absoluteIn(root, join(dir, it.name)) })
        }
        if (can.write) PickRow(t(if (can.trash) "web-pages.drive.toTrashMany" else "web-pages.drive.deleteMany", "n" to items.size), color = C.link, leading = { IconIn(Icons.Trash, 20.dp, C.accent) }) {
            app.sheet = null; done()
            removeAll(app, station, root, dir, items, can.trash)
        }
    }
}

/** One entry: renamed and deleted by those who may change the drive; a file downloaded and shared, a folder downloaded as a zip; its path copied. */
private fun openEntrySheet(app: AppState, context: Context, station: String, root: String, dir: String, e: DriveEntry, can: DriveRights, names: Set<String>, done: () -> Unit) {
    val path = join(dir, e.name)
    val zip = e.dir && can.zip
    val rows = (if (can.write) 2 else 0) + (if (e.dir) (if (zip) 1 else 0) else 2) + 1
    app.sheet = SheetSpec(0.5f, fit = fit(rows)) {
        SheetGrab()
        SheetHead(e.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            if (can.write) PickRow(t("android-misc.drive.rename"), leading = { IconIn(Icons.Edit, 20.dp, C.ink) }) {
                done()
                ask(app, t("android-misc.drive.rename"), e.name, e.name, t("common.save"), what = t("android-misc.drive.rename.what")) { name ->
                    nameProblem(name)?.let { throw CoreException("invalid", it, null) }
                    if (name != e.name && name in names) throw CoreException("exists", t("station.drive.exists"), null)
                    app.api(station).driveRename(root, path, join(dir, name))
                }
            }
            if (!e.dir) {
                PickRow(t("android-misc.drive.download"), leading = { IconIn(Icons.Download, 20.dp, C.ink) }) {
                    app.sheet = null; done()
                    app.toast = t("android-misc.drive.downloading", "name" to e.name)
                    saveToDownloads(app, context, station, root, e, path)
                }
                PickRow(t("android-misc.drive.share"), leading = { IconIn(Icons.External, 20.dp, C.ink) }) { app.sheet = null; done(); openElsewhere(app, context, station, root, e, path, share = true) }
            } else if (zip) PickRow(t("web-pages.drive.downloadZip"), leading = { IconIn(Icons.Download, 20.dp, C.ink) }) {
                app.sheet = null; done()
                app.toast = t("android-misc.drive.downloading", "name" to "${e.name}.zip")
                saveZip(app, context, station, root, path)
            }
            PickRow(t("web-pages.drive.copyPath"), leading = { IconIn(Icons.Copy, 20.dp, C.ink) }) { app.sheet = null; done(); copyPaths(app, context, listOf(absoluteIn(root, path))) }
            if (can.write) PickRow(t(if (can.trash) "web-pages.drive.toTrash" else "android-misc.drive.remove"), color = C.link, leading = { IconIn(Icons.Trash, 20.dp, C.accent) }) {
                done()
                removeAll(app, station, root, dir, listOf(e), can.trash)
            }
        }
    }
}

/** Paths on the clipboard, a line each. */
private fun copyPaths(app: AppState, context: Context, paths: List<String>) {
    (context.getSystemService(Context.CLIPBOARD_SERVICE) as android.content.ClipboardManager).setPrimaryClip(android.content.ClipData.newPlainText("path", paths.joinToString("\n")))
    app.toast = t("web-pages.drive.pathCopied")
}

/** A folder zipped on the station and saved into the phone's Downloads. */
private fun saveZip(app: AppState, context: Context, station: String, root: String, path: String) {
    app.scope.launch {
        try {
            val z = app.api(station).driveZip(root, path)
            saveToDownloads(app, context, station, z.root, DriveEntry(z.name, false, z.size, 0, "application/zip", "other", "", ""), z.path)
        } catch (e: CoreException) {
            app.toast = t("android-misc.drive.fetchFailed", "name" to nameOf(path), "error" to e.message)
        }
    }
}

/**
 * Deleted: to the machine's trash where the station has one, nothing asked (said once done); where none takes them (or
 * a station without one), asked first, then for good.
 */
private fun removeAll(app: AppState, station: String, root: String, dir: String, items: List<DriveEntry>, trash: Boolean) {
    fun forGood(list: List<DriveEntry>) {
        val one = list.singleOrNull()
        confirm(
            app, if (one != null) t(if (one.dir) "android-misc.drive.remove.folderTitle" else "android-misc.drive.remove.fileTitle", "name" to one.name) else t("web-pages.drive.deleteManyAsk", "n" to list.size),
            t(if (list.any { it.dir }) "android-misc.drive.remove.folderText" else "android-misc.drive.remove.fileText"),
            t("android-misc.drive.remove"), danger = true, what = t("android-misc.drive.remove.what"),
        ) { list.forEach { app.api(station).driveRemove(root, join(dir, it.name), permanent = true) } }
    }
    if (!trash) return forGood(items)
    app.act(t("android-misc.drive.remove.what")) {
        val left = items.filter { e ->
            try { app.api(station).driveRemove(root, join(dir, e.name)); false } catch (x: CoreException) { if (x.code == "no_trash") true else throw x }
        }
        if (left.isNotEmpty()) forGood(left) else app.toast = t("web-pages.drive.trashed", "n" to items.size)
    }
}

/** A new folder in `dir`, named here. */
private fun newFolder(app: AppState, station: String, root: String, dir: String) {
    ask(app, t("android-misc.drive.mkdir"), "", t("android-misc.drive.mkdir.placeholder"), t("android-misc.drive.mkdir.make"), what = t("android-misc.drive.mkdir.what")) { name ->
        nameProblem(name)?.let { throw CoreException("invalid", it, null) }
        app.api(station).driveMkdir(root, join(dir, name))
    }
}

// ── the folders lent ────────────────────────────────────────────────────

/** The folders the station lends (the owners and admins): each tapped to stop lending it; another one added. */
private fun openRoots(app: AppState, station: String) {
    app.sheet = SheetSpec(0.7f, draggable = true) {
        val workspace = station.substringBefore('/')
        val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(workspace))
        val roots = stations.value?.firstOrNull { it.station == station }?.overview?.drive?.roots.orEmpty()
        SheetGrab()
        SheetHead(t("android-misc.drive.roots.manage"), trailing = { if (app.isDoing("drive.setRoots")) Spinner() })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Text(t("android-misc.drive.roots.note"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 6.dp))
            roots.forEach { r ->
                val trouble = rootTrouble(r.state)
                PickRow(r.name, sub = r.path, leading = { IconIn(Icons.Folder, 20.dp, C.ink) },
                    mark = if (trouble != null) ({ Text(trouble.first, fontSize = 12.sp, color = C.red) }) else null) { unshare(app, station, roots, r) }
            }
            PickRow(t("android-misc.drive.roots.add"), color = C.link, leading = { IconIn(Icons.Plus, 20.dp, C.accent) }) { openFolderPicker(app, station, roots.map { it.path }) }
        }
    }
}

/** Where the picker is: the folder asked for (null: the home), the way there as known before the station answers, whether its row said the station may not read it. */
private class PickAt(val path: String?, val way: List<DriveCrumb>, val unreadable: Boolean)

/** The way to `path` as the station would give it: from the home when it is under it (its name the station's word for it), else from the top. */
private fun wayTo(path: String, here: DriveFolders): List<DriveCrumb> {
    val home = here.home.trimEnd('/', '\\')
    val homeName = here.crumbs?.firstOrNull()?.takeIf { it.path == here.home }?.name
    val under = homeName != null && home.isNotEmpty() && (path == here.home || path.startsWith("$home/") || path.startsWith("$home\\"))
    val top = if (under) DriveCrumb(homeName!!, here.home) else DriveCrumb("/", "/")
    var at = if (under) home else ""
    val rest = if (under) path.substring(home.length) else path
    return listOf(top) + rest.split('/', '\\').filter { it.isNotEmpty() }.map { at = "$at/$it"; DriveCrumb(it, at) }
}

/**
 * The station's folders, from its home: the way there on top (each step a way back), a filter for the names, then at the
 * home the usual places (its own folders, the disks) over its folders. A folder the station may not read says so; it can
 * be entered but not lent, and how to let the station read it is told. `lent`: the folders lent already.
 */
fun openFolderPicker(app: AppState, station: String, lent: List<String>) {
    app.sheet = SheetSpec(0.85f, draggable = true) {
        var at by remember { mutableStateOf(PickAt(null, emptyList(), false)) }
        var shown by remember { mutableStateOf<DriveFolders?>(null) }
        var denied by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        var filter by remember { mutableStateOf("") }
        val focus = LocalFocusManager.current
        // Each place asked for anew; a later one supersedes what is still on its way.
        LaunchedEffect(at) {
            shown = null; error = null; denied = at.unreadable
            try { shown = app.api(station).driveFolders(at.path).also { denied = it.unreadable } }
            catch (e: CoreException) { if (e.code == "permission") denied = true else error = e.message }
        }
        fun go(to: PickAt) { filter = ""; focus.clearFocus(); at = to }
        val here = shown
        // A station from before gives neither the way nor where each folder is: made from the path.
        val way = here?.let { it.crumbs ?: wayTo(it.path, it) } ?: at.way
        val entries = here?.let { h -> h.entries ?: h.folders.map { PickFolder(it, h.path.trimEnd('/') + "/" + it) } }.orEmpty()
        val wanted = filter.trim()
        val places = if (here != null && here.path == here.home && wanted.isEmpty()) here.places.filter { it.path != here.home } else emptyList()
        // At home the usual places are above: not listed again under their names on disk.
        val listed = if (wanted.isEmpty()) entries.filter { e -> places.none { it.path == e.path } } else entries.filter { it.name.contains(wanted, ignoreCase = true) }
        SheetGrab()
        SheetHead(t("android-misc.drive.pick.title"))
        PickCrumbs(way) { i, c -> go(PickAt(c.path, way.take(i + 1), false)) }
        PickFilter(filter) { filter = it }
        // Each folder from its top (one list's scroll is not the next folder's).
        androidx.compose.runtime.key(at.path) { LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(bottom = 8.dp)) {
            when {
                error != null -> item(key = "error") { Text(error!!, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) }
                denied -> item(key = "denied") { Note(t("android-misc.drive.pick.unreadable")) }
                // Each folder gone into is read anew: a line, said only when it takes a while (no shapes flashing at each step).
                here == null -> item(key = "reading") { WaitLine(t("common.reading"), modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) }
                else -> {
                    if (places.isNotEmpty()) {
                        item(key = "places") { SectionHeader(t("android-misc.drive.pick.places")) }
                        items(places, key = { "p:" + it.path }) { p -> PickFolderRow(p) { go(PickAt(p.path, wayTo(p.path, here), p.unreadable)) } }
                        item(key = "folders") { SectionHeader(t("android-misc.drive.pick.folders")) }
                    }
                    if (listed.isEmpty()) item(key = "none") {
                        Text(
                            if (wanted.isEmpty()) t("android-misc.drive.pick.empty") else t("android-misc.drive.pick.noMatch", "q" to wanted),
                            fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                        )
                    }
                    items(listed, key = { "f:" + it.path }) { e -> PickFolderRow(e) { go(PickAt(e.path, way + DriveCrumb(e.name, e.path), e.unreadable)) } }
                }
            }
        } }
        if (denied) Text(t("android-misc.drive.pick.unreadableNote"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 8.dp))
        val taken = here != null && here.path in lent
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(if (taken) t("android-misc.drive.pick.already") else t("android-misc.drive.pick.choose"), primary = true, enabled = here != null && !taken && !denied) {
                val p = here?.path ?: return@Button
                app.sheet = null
                app.act(t("android-misc.drive.roots.what"), done = t("android-misc.drive.roots.added", "name" to p.trimEnd('/').substringAfterLast('/').ifEmpty { p })) { app.api(station).driveSetRoots(lent + p) }
            }
        }
    }
}

/** The way to the folder shown, scrolled to its end: each step but the last a way back to it. */
@Composable
private fun PickCrumbs(way: List<DriveCrumb>, onPick: (Int, DriveCrumb) -> Unit) {
    val scroll = rememberScrollState()
    LaunchedEffect(way.lastOrNull()?.path, scroll.maxValue) { scroll.scrollTo(scroll.maxValue) }
    Row(Modifier.fillMaxWidth().heightIn(min = 28.dp).horizontalScroll(scroll).padding(start = 17.dp, end = 20.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        way.forEachIndexed { i, c ->
            if (i > 0) IconIn(Icons.ChevronRight, 12.dp, C.subtle)
            val last = i == way.lastIndex
            Text(
                c.name, fontSize = 14.sp, color = if (last) C.ink else C.muted, fontWeight = if (last) FontWeight.SemiBold else null, maxLines = 1,
                modifier = Modifier.clip(Smooth(6.dp)).clickable(enabled = !last) { onPick(i, c) }.padding(horizontal = 3.dp, vertical = 3.dp),
            )
        }
    }
}

/** A pill to type a part of a folder's name in: only those with it are listed; × clears it. */
@Composable
private fun PickFilter(text: String, onChange: (String) -> Unit) {
    Row(
        Modifier.padding(horizontal = 20.dp).padding(bottom = 6.dp).fillMaxWidth().height(38.dp).clip(CircleShape).background(C.ink.copy(alpha = 0.06f)).padding(start = 12.dp, end = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconIn(Icons.Search, 16.dp, C.muted)
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (text.isEmpty()) Text(t("android-misc.drive.pick.filter"), fontSize = 15.sp, color = C.muted, maxLines = 1)
            BasicTextField(
                text, onChange, singleLine = true, cursorBrush = SolidColor(C.accent),
                textStyle = TextStyle(fontSize = 15.sp, color = C.ink),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = t("android-misc.drive.pick.filter") },
            )
        }
        if (text.isNotEmpty()) Box(
            Modifier.size(28.dp).clip(CircleShape).clickable { onChange("") }.semantics { contentDescription = t("android-misc.drive.pick.filterClear") },
            contentAlignment = Alignment.Center,
        ) { IconIn(Icons.Close, 14.dp, C.muted) }
    }
}

/** A folder or a place to go into: a disk's mark for a disk; whether the station may not read it, under its name. */
@Composable
private fun PickFolderRow(f: PickFolder, onClick: () -> Unit) {
    PickRow(f.name, sub = if (f.unreadable) t("android-misc.drive.pick.unreadable") else null, leading = { IconIn(if (f.disk) Icons.Disk else Icons.Folder, 20.dp, C.ink) }, onClick = onClick)
}

