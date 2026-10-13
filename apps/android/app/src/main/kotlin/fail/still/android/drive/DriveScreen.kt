// A station's drive (docs/drive.md): the folders it lends its members, one page per folder (App.kt Screen.Drive), so
// going in and coming back is the stack's slide and the edge swipe. One root shows what is in it at once; several are
// listed as folders, one that cannot be browsed in red with why. A row opens by its kind: a folder goes in, text and
// Markdown are read (Reader.kt), video and audio play (Player.kt), pictures, PDFs, code, tables and pages open in the
// chat's viewer (FilePreview.kt), the rest goes to another app. Held, a row offers rename, remove, download and share.
// The workspace's owners and admins choose the folders (⋯); read-only members get no way to change anything.
package fail.still.android.drive

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import fail.still.android.screens.Button
import fail.still.android.screens.DoingMark
import fail.still.android.screens.DriveKey
import fail.still.android.screens.FilePreview
import fail.still.android.screens.PickRow
import fail.still.android.screens.Shown
import fail.still.android.screens.Spinner
import fail.still.android.screens.ask
import fail.still.android.screens.confirm
import fail.still.android.screens.download
import fail.still.android.screens.fileSize
import fail.still.android.ui.C
import fail.still.android.ui.DownloadChip
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec
import fail.still.android.ui.NavButton
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth
import fail.still.core.CoreException
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ── what an entry is ────────────────────────────────────────────────────

/** The line icon an entry of the drive is drawn with, by its kind (the core's `kind`). */
fun kindIcon(kind: String): ImageVector = when (kind) {
    "folder" -> Icons.Folder
    "video" -> Icons.FileVideo
    "audio" -> Icons.FileAudio
    "image" -> Icons.Photo
    "markdown", "text", "subtitle" -> Icons.FileText
    "code", "csv", "html" -> Icons.FileCode
    "pdf" -> Icons.FilePdf
    else -> Icons.File
}

/** A path under a root, `/` between its components; `dir` empty for the root itself. */
fun join(dir: String, name: String) = if (dir.isEmpty()) name else "$dir/$name"
fun parentOf(path: String) = path.substringBeforeLast('/', "")
fun nameOf(path: String) = path.substringAfterLast('/')

/** What a root's name is shown as. */
private fun rootName(root: String) = root.trimEnd('/').substringAfterLast('/').ifEmpty { root }

/** Why a root cannot be browsed, in a line; null when it can. */
fun rootTrouble(state: String): String? = when (state) {
    "ok" -> null
    "missing" -> t("android-misc.drive.root.missing")
    "not_a_directory" -> t("android-misc.drive.root.notFolder")
    "unreadable" -> t("android-misc.drive.root.unreadable")
    else -> t("android-misc.drive.root.unknown")
}

/** A name not among `taken`: "name (1).ext", "name (2).ext"… */
fun freeName(name: String, taken: Set<String>): String {
    if (name !in taken) return name
    val dot = name.lastIndexOf('.').takeIf { it > 0 } ?: name.length
    val stem = name.substring(0, dot)
    val ext = name.substring(dot)
    var n = 1
    while ("$stem ($n)$ext" in taken) n++
    return "$stem ($n)$ext"
}

/** Whether the viewer may change what is in a drive (not a read-only member); null until the workspace is read. */
@Composable
private fun writable(current: WorkspaceEntry): Boolean {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    return ws.value?.let { it.role != "viewer" } ?: false
}

@Composable
private fun manager(current: WorkspaceEntry): Boolean {
    val app = LocalApp.current
    val ws by rememberTopic<WorkspaceView>(app.core, Topics.workspace(current.workspace.id))
    return ws.value?.manager == true
}

// ── uploads ─────────────────────────────────────────────────────────────

/** A file going up into a folder of a drive: how much of it the station has, shown in its folder's list until it is there. */
class DriveUpload(val station: String, val root: String, val dir: String, name: String, val size: Long) {
    var name by mutableStateOf(name)
    var sent by mutableLongStateOf(0L)
}

/** The uploads under way, whatever page is shown (they go on past the page that started them). */
object DriveUploads {
    val list = mutableStateListOf<DriveUpload>()
}

/** What a file of that name already there is to become. */
private enum class Clash { Replace, Both }

/** Asks what to do with a file whose name is taken; null: leave it (the sheet closed). */
private suspend fun askClash(app: AppState, name: String): Clash? {
    val answer = CompletableDeferred<Clash?>()
    app.sheet = SheetSpec(0.3f, fit = 200.dp) {
        DisposableEffect(Unit) { onDispose { answer.complete(null) } }
        SheetGrab()
        SheetHead(t("android-misc.drive.exists.title"))
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("android-misc.drive.exists.text", "name" to name), fontSize = 14.sp, color = C.muted)
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { answer.complete(null); app.sheet = null }
                Button(t("android-misc.drive.exists.both"), primary = false) { answer.complete(Clash.Both); app.sheet = null }
                Button(t("android-misc.drive.exists.replace"), primary = true) { answer.complete(Clash.Replace); app.sheet = null }
            }
        }
    }
    return answer.await()
}

/** A picked document's name and size, as its provider says. */
private fun picked(resolver: ContentResolver, uri: Uri): Pair<String, Long> {
    var name = uri.lastPathSegment?.substringAfterLast('/') ?: "file"
    var size = -1L
    resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { c ->
        if (c.moveToFirst()) {
            c.getString(0)?.let { name = it }
            if (!c.isNull(1)) size = c.getLong(1)
        }
    }
    return name to size
}

/**
 * Puts the files picked into a folder of the drive, one after another, each a row in that folder's list while it goes
 * (on the app's own scope: on past this page). A name taken asks to replace it or keep both; `held` is what the folder
 * holds as last read.
 */
fun uploadInto(app: AppState, context: Context, station: String, root: String, dir: String, uris: List<Uri>, held: () -> List<DriveEntry>) {
    if (uris.isEmpty()) return
    val resolver = context.contentResolver
    app.scope.launch {
        val api = app.api(station)
        val ups = uris.map { uri ->
            val (name, size) = withContext(Dispatchers.IO) { picked(resolver, uri) }
            Triple(uri, DriveUpload(station, root, dir, name, size.coerceAtLeast(0)), size)
        }
        DriveUploads.list += ups.map { it.second }
        for ((uri, up, known) in ups) {
            try {
                // A provider that does not say how big it is: read it once to know.
                val size = if (known >= 0) known else withContext(Dispatchers.IO) { resolver.openInputStream(uri)?.use { s -> s.skip(Long.MAX_VALUE) } ?: 0L }
                val open = { resolver.openInputStream(uri) ?: throw java.io.IOException(t("android-misc.drive.upload.unreadable")) }
                suspend fun send(replace: Boolean) = api.driveUpload(root, join(dir, up.name), size, open, replace) { up.sent = it }
                try {
                    send(false)
                } catch (e: CoreException) {
                    // Taken: a folder by that name cannot be replaced; a file can, or both kept.
                    if (e.status != 409 || held().any { it.name == up.name && it.dir }) throw e
                    val choice = askClash(app, up.name) ?: continue
                    if (choice == Clash.Both) up.name = freeName(up.name, held().map { it.name }.toSet() + DriveUploads.list.filter { it !== up && it.dir == dir }.map { it.name })
                    up.sent = 0
                    send(choice == Clash.Replace)
                }
            } catch (e: CoreException) {
                app.toast = t("android-misc.drive.upload.failed", "name" to up.name, "error" to e.message)
            } catch (e: java.io.IOException) {
                app.toast = t("android-misc.drive.upload.failed", "name" to up.name, "error" to (e.message ?: ""))
            } finally {
                DriveUploads.list.remove(up)
            }
        }
    }
}

// ── fetching for another app ────────────────────────────────────────────

/** Files of the drive being fetched to hand to another app (or to Downloads): how far each has come (0–100), by station and path. */
object DriveFetches {
    val progress = mutableStateMapOf<String, Long>()
    fun id(station: String, root: String, path: String) = "$station\n$root\n$path"
}

/** A file of the drive in the app's cache (for another app to open, or to save), fetched a part at a time with its progress shown on its row. */
private suspend fun fetched(app: AppState, context: Context, station: String, root: String, entry: DriveEntry, path: String): File {
    val id = DriveFetches.id(station, root, path)
    val dir = File(context.cacheDir, "drive/${Integer.toHexString(id.hashCode())}-${entry.mtime}").apply { mkdirs() }
    val file = File(dir, entry.name.replace('/', '_'))
    if (file.exists() && file.length() == entry.size) return file
    val part = File(dir, file.name + ".part")
    part.delete()
    DriveFetches.progress[id] = 0
    try {
        app.api(station).driveToDisk(root, path, part) { at, total -> DriveFetches.progress[id] = if (total > 0) at * 100 / total else 0 }
        withContext(Dispatchers.IO) { part.renameTo(file) }
    } finally {
        DriveFetches.progress.remove(id)
    }
    return file
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

/**
 * A page of a station's drive: `root` null is the drive itself (its one root's contents, or its roots as folders);
 * else the folder `path` under `root`.
 */
@Composable
fun DriveScreen(current: WorkspaceEntry, station: String, root: String?, path: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == station }
    val roots = s?.overview?.drive?.roots
    val manager = manager(current)
    val writable = writable(current)
    // The drive's own page with one root: that root's contents, as if it were opened.
    val folderRoot = root ?: roots?.singleOrNull()?.takeIf { it.state == "ok" }?.path
    val top = root == null
    val folder by rememberTopic<DriveFolder>(app.core, folderRoot?.let { Topics.drive(station, it, path) })
    var refreshing by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    var previewing by remember { mutableStateOf<DriveEntry?>(null) }
    val entries = folder.value?.entries
    val latest by rememberUpdatedState(entries)
    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (folderRoot != null) uploadInto(app, context, station, folderRoot, path, uris) { latest.orEmpty() }
    }
    val title = when {
        root == null && folderRoot == null -> t("android-misc.drive.title")
        path.isEmpty() -> rootName(folderRoot ?: root ?: "")
        else -> nameOf(path)
    }

    Column(Modifier.fillMaxSize().background(C.bg)) {
        DriveBar(
            title = title,
            onBack = app::pop,
            refreshing = refreshing,
            onRefresh = if (folderRoot == null) null else ({
                if (!refreshing) scope.launch {
                    refreshing = true
                    try { app.api(station).driveRefresh(folderRoot, path) } catch (e: CoreException) { app.toast = e.message } finally { refreshing = false }
                }
            }),
            onAdd = if (writable && folderRoot != null && folder.value != null) ({ anchor ->
                app.menu = MenuSpec(anchor, listOf(
                    MenuItem(t("android-misc.drive.upload"), Icons.Upload) { pick.launch(arrayOf("*/*")) },
                    MenuItem(t("android-misc.drive.mkdir"), Icons.FolderPlus) { newFolder(app, station, folderRoot, path, latest.orEmpty().map { it.name }.toSet()) },
                ))
            }) else null,
            onMore = if (manager && top && roots != null && roots.isNotEmpty()) ({ anchor ->
                app.menu = MenuSpec(anchor, listOf(
                    MenuItem(t("android-misc.drive.roots.add"), Icons.FolderPlus) { openFolderPicker(app, station, roots.map { it.path }) },
                    MenuItem(t("android-misc.drive.roots.manage"), Icons.Sliders) { openRoots(app, station) },
                ))
            }) else null,
        )
        when {
            s == null || roots == null -> Note(stations.error?.message ?: t("android-misc.drive.reading"))
            roots.isEmpty() -> NoRoots(manager) { openFolderPicker(app, station, emptyList()) }
            folderRoot == null -> RootList(station, roots)
            else -> FolderPage(app, station, s.name, folderRoot, path, roots.size > 1, folder.value, folder.error, writable) { previewing = it }
        }
    }
    // Pictures, PDFs, code, tables and pages: the chat's viewer, over the page; a picture steps to the folder's others.
    val shown = previewing
    if (shown != null && folderRoot != null) {
        val shownOf = { e: DriveEntry -> Shown(DriveKey.of(folderRoot, e.mtime), Attachment(e.name, join(path, e.name), e.size)) }
        val opened = remember(shown) { shownOf(shown) }
        FilePreview(station, opened.key, opened.file, gallery = { latest.orEmpty().filter { it.kind == "image" }.map(shownOf) }, canDraft = false) { previewing = null }
    }
}

/** The page's one row of chrome: back, where it is, refresh (a ring while it reads), + and ⋯ when they apply. */
@Composable
private fun DriveBar(title: String, onBack: () -> Unit, refreshing: Boolean, onRefresh: (() -> Unit)?, onAdd: ((Rect) -> Unit)?, onMore: ((Rect) -> Unit)?) {
    Row(
        Modifier.fillMaxWidth().background(C.bg).windowInsetsPadding(WindowInsets.statusBars).padding(start = 4.dp, end = 8.dp, top = 6.dp, bottom = 4.dp).height(36.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(36.dp).clip(CircleShape).clickable(onClick = onBack).semantics { contentDescription = t("common.back") }, contentAlignment = Alignment.Center) {
            IconIn(Icons.ChevronLeft, 22.dp, C.accent)
        }
        Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = 2.dp, end = 8.dp))
        if (onRefresh != null) Box(Modifier.size(34.dp).clip(CircleShape).clickable(enabled = !refreshing, onClick = onRefresh).semantics { contentDescription = t("android-misc.drive.refresh") }, contentAlignment = Alignment.Center) {
            if (refreshing) Spinner(16.dp) else IconIn(Icons.Refresh, 18.dp)
        }
        if (onAdd != null) Anchored(Icons.Plus, t("android-misc.drive.add"), 20.dp, onAdd)
        if (onMore != null) Anchored(Icons.More, t("android-misc.drive.more"), 18.dp, onMore)
    }
}

/** A bar's button whose menu opens under it. */
@Composable
private fun Anchored(icon: ImageVector, label: String, size: androidx.compose.ui.unit.Dp, open: (Rect) -> Unit) {
    var at by remember { mutableStateOf(Rect.Zero) }
    Box(Modifier.onGloballyPositioned { at = it.boundsInRoot() }.semantics { contentDescription = label }) {
        NavButton(icon, { open(at) }, size)
    }
}

@Composable
private fun Note(text: String) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) { Text(text, color = C.muted, fontSize = 14.sp, textAlign = TextAlign.Center) }
}

/** Nothing lent yet: the owners and admins can choose a folder; the others are told so. */
@Composable
private fun NoRoots(manager: Boolean, choose: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
        IconIn(Icons.Folder, 36.dp, C.subtle)
        Text(t("android-misc.drive.none.title"), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Text(if (manager) t("android-misc.drive.none.manager") else t("android-misc.drive.none.member"), fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
        if (manager) Box(Modifier.padding(top = 6.dp)) { Button(t("android-misc.drive.choose"), primary = true, onClick = choose) }
    }
}

/** Card rows in a lazy list: each row its part of one rounded card (the first and last carry its corners). */
private fun cardShape(first: Boolean, last: Boolean) = Smooth(
    topStart = if (first) 16.dp else 0.dp, topEnd = if (first) 16.dp else 0.dp,
    bottomEnd = if (last) 16.dp else 0.dp, bottomStart = if (last) 16.dp else 0.dp,
)

private fun Modifier.cardRow(first: Boolean, last: Boolean) =
    padding(horizontal = 12.dp).padding(bottom = if (last) 10.dp else 0.dp).fillMaxWidth().clip(cardShape(first, last))

/** The roots as folders: each its name, where it is on the station under it, and why it cannot be browsed when it cannot. */
@Composable
private fun RootList(station: String, roots: List<DriveRoot>) {
    val app = LocalApp.current
    val c = C
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = 8.dp, bottom = 24.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding())) {
        itemsIndexed(roots, key = { _, r -> r.path }) { i, r ->
            val trouble = rootTrouble(r.state)
            Row(
                Modifier.cardRow(i == 0, i == roots.lastIndex).background(c.surface)
                    .clickable { if (trouble == null) app.push(Screen.Drive(station, r.path, "")) else app.toast = trouble }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                IconIn(Icons.Folder, 20.dp, if (trouble != null) c.red else c.muted)
                Column(Modifier.weight(1f)) {
                    Text(r.name, fontSize = 15.sp, color = if (trouble != null) c.red else c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(trouble ?: r.path, fontSize = 12.sp, lineHeight = 16.sp, color = if (trouble != null) c.red else c.muted, maxLines = if (trouble != null) 3 else 1, overflow = TextOverflow.Ellipsis)
                }
                if (trouble == null) IconIn(Icons.ChevronRight, 14.dp, c.subtle)
            }
        }
    }
}

/** A folder: where it is (each level a tap back), what it holds in a line, then its folders and files. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun FolderPage(
    app: AppState, station: String, stationName: String, root: String, path: String, severalRoots: Boolean,
    folder: DriveFolder?, error: CoreException?, writable: Boolean, preview: (DriveEntry) -> Unit,
) {
    val context = LocalContext.current
    val c = C
    val uploads = DriveUploads.list.filter { it.station == station && it.root == root && it.dir == path }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp + WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding())) {
        item(key = "where") {
            Column(Modifier.padding(start = 17.dp, end = 20.dp, top = 2.dp, bottom = 10.dp)) {
                Crumbs(station, stationName, root, path, severalRoots)
                Text(
                    folder?.countText ?: if (error == null) t("android-misc.drive.reading") else "",
                    fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.padding(start = 3.dp, top = 2.dp),
                )
            }
        }
        if (error != null) item(key = "error") {
            Text(error.message, fontSize = 14.sp, color = c.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        }
        itemsIndexed(uploads, key = { _, u -> "up:" + System.identityHashCode(u) }) { i, u ->
            Row(
                Modifier.cardRow(i == 0, i == uploads.lastIndex).background(c.surface).padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                IconIn(Icons.Upload, 20.dp, c.muted)
                Column(Modifier.weight(1f)) {
                    Text(u.name, fontSize = 15.sp, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(t("android-misc.drive.upload.going", "sent" to fileSize(u.sent), "size" to fileSize(u.size)), fontSize = 12.sp, color = c.muted, maxLines = 1)
                }
                DownloadChip(if (u.size > 0) u.sent * 100 / u.size else 0)
            }
        }
        val list = folder?.entries.orEmpty()
        if (folder != null && list.isEmpty() && uploads.isEmpty()) item(key = "empty") {
            Text(
                if (writable) t("android-misc.drive.empty.writable") else t("android-misc.drive.empty"),
                fontSize = 14.sp, color = c.muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 48.dp),
            )
        }
        entryRows(app, context, station, root, path, list, writable, preview)
        if (folder?.truncated == true) item(key = "truncated") {
            Text(t("android-misc.drive.truncated"), fontSize = 13.sp, color = c.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp))
        }
    }
}

/** The breadcrumb: the station, the root (with several), then each folder down to this one; each but the last a way back to it. */
@Composable
private fun Crumbs(station: String, stationName: String, root: String, path: String, severalRoots: Boolean) {
    val app = LocalApp.current
    val levels = buildList {
        add(stationName to null as Screen?)
        add(rootName(root) to (if (severalRoots) Screen.Drive(station, root, "") else Screen.Drive(station, null, "")))
        val parts = path.split('/').filter { it.isNotEmpty() }
        parts.forEachIndexed { i, p -> add(p to Screen.Drive(station, root, parts.take(i + 1).joinToString("/"))) }
    }
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), verticalAlignment = Alignment.CenterVertically) {
        levels.forEachIndexed { i, (label, to) ->
            if (i > 0) IconIn(Icons.ChevronRight, 12.dp, C.subtle)
            val last = i == levels.lastIndex
            val back = to?.takeIf { !last }?.let { target -> app.stack.indexOfLast { it == target }.takeIf { it >= 0 } }
            Text(
                label, fontSize = 13.sp, color = if (last) C.ink else C.muted, maxLines = 1,
                modifier = Modifier.clip(Smooth(6.dp)).clickable(enabled = back != null) { repeat(app.stack.size - 1 - back!!) { app.pop() } }.padding(horizontal = 3.dp, vertical = 2.dp),
            )
        }
    }
}

/** The folder's entries, as card rows: folders, then files (the core's order). */
@OptIn(ExperimentalFoundationApi::class)
private fun LazyListScope.entryRows(app: AppState, context: Context, station: String, root: String, dir: String, list: List<DriveEntry>, writable: Boolean, preview: (DriveEntry) -> Unit) {
    itemsIndexed(list, key = { _, e -> "e:" + e.name }) { i, e ->
        val path = join(dir, e.name)
        EntryRow(station, root, path, e, i == 0, i == list.lastIndex,
            onOpen = { open(app, context, station, root, dir, e, preview) },
            onHold = { openEntrySheet(app, context, station, root, dir, e, writable, list.map { it.name }.toSet()) { open(app, context, station, root, dir, e, preview) } },
        )
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
private fun EntryRow(station: String, root: String, path: String, e: DriveEntry, first: Boolean, last: Boolean, onOpen: () -> Unit, onHold: () -> Unit) {
    val app = LocalApp.current
    val c = C
    val busy = app.isDoing(setOf("drive.remove", "drive.rename"), "root" to root, "path" to path) || app.isDoing("drive.rename", "root" to root, "from" to path)
    val failed = app.failedOf(setOf("drive.remove"), "root" to root, "path" to path) ?: app.failedOf("drive.rename", "root" to root, "from" to path)
    val fetching = DriveFetches.progress[DriveFetches.id(station, root, path)]
    Row(
        Modifier.cardRow(first, last).background(c.surface).combinedClickable(onClick = onOpen, onLongClick = onHold).padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconIn(kindIcon(e.kind), 20.dp, if (e.dir) c.ink else c.muted)
        Column(Modifier.weight(1f)) {
            Text(e.name, fontSize = 15.sp, lineHeight = 20.sp, color = c.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val line = listOf(e.sizeText, e.timeText).filter { it.isNotEmpty() }.joinToString(" · ")
            if (line.isNotEmpty()) Text(line, fontSize = 12.sp, lineHeight = 16.sp, color = c.muted, maxLines = 1)
        }
        when {
            busy || failed != null -> DoingMark(busy, failed)
            fetching != null -> DownloadChip(fetching)
            e.kind == "text" || e.kind == "markdown" -> ReadShare(station, root, path)
            e.dir -> IconIn(Icons.ChevronRight, 14.dp, c.subtle)
        }
    }
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

/** Held: what the entry is, and what can be done to it (open, download, share; rename and remove for those who may). */
private fun openEntrySheet(app: AppState, context: Context, station: String, root: String, dir: String, e: DriveEntry, writable: Boolean, names: Set<String>, open: () -> Unit) {
    val path = join(dir, e.name)
    val rows = 1 + (if (e.dir) 0 else 2) + (if (writable) 2 else 0)
    app.sheet = SheetSpec(0.5f, fit = (96 + 48 * rows).dp) {
        SheetGrab()
        SheetHead(e.name, lead = { IconIn(kindIcon(e.kind), 18.dp, C.muted) })
        val line = listOf(e.sizeText, e.timeText).filter { it.isNotEmpty() }.joinToString(" · ")
        if (line.isNotEmpty()) Text(line, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 6.dp))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow(t("android-misc.drive.open"), leading = { IconIn(kindIcon(e.kind), 18.dp, C.muted) }) { app.sheet = null; open() }
            if (!e.dir) {
                PickRow(t("android-misc.drive.download"), leading = { IconIn(Icons.Download, 18.dp, C.muted) }) { app.sheet = null; saveToDownloads(app, context, station, root, e, path) }
                PickRow(t("android-misc.drive.share"), leading = { IconIn(Icons.External, 18.dp, C.muted) }) { app.sheet = null; openElsewhere(app, context, station, root, e, path, share = true) }
            }
            if (writable) {
                PickRow(t("android-misc.drive.rename"), leading = { IconIn(Icons.Edit, 18.dp, C.muted) }) {
                    ask(app, t("android-misc.drive.rename.title"), e.name, t("android-misc.drive.name"), t("android-misc.drive.rename"), what = t("android-misc.drive.rename.what")) { name ->
                        if (name.contains('/')) throw CoreException("invalid", t("android-misc.drive.name.slash"), null)
                        if (name in names) throw CoreException("exists", t("station.drive.exists"), null)
                        app.api(station).driveRename(root, path, join(dir, name))
                    }
                }
                PickRow(t("android-misc.drive.remove"), color = C.red, leading = { IconIn(Icons.Trash, 18.dp, C.red) }) {
                    confirm(
                        app, t(if (e.dir) "android-misc.drive.remove.folderTitle" else "android-misc.drive.remove.fileTitle", "name" to e.name),
                        t(if (e.dir) "android-misc.drive.remove.folderText" else "android-misc.drive.remove.fileText"),
                        t("android-misc.drive.remove"), danger = true, what = t("android-misc.drive.remove.what"),
                    ) { app.api(station).driveRemove(root, path) }
                }
            }
        }
    }
}

/** A new folder in `dir`, named here. */
private fun newFolder(app: AppState, station: String, root: String, dir: String, names: Set<String>) {
    ask(app, t("android-misc.drive.mkdir"), "", t("android-misc.drive.name"), t("android-misc.drive.mkdir.make"), what = t("android-misc.drive.mkdir.what")) { name ->
        if (name.contains('/')) throw CoreException("invalid", t("android-misc.drive.name.slash"), null)
        if (name in names) throw CoreException("exists", t("station.drive.exists"), null)
        app.api(station).driveMkdir(root, join(dir, name))
    }
}

// ── the folders lent ────────────────────────────────────────────────────

/** The folders the station lends, each to stop lending (the owners and admins). */
private fun openRoots(app: AppState, station: String) {
    app.sheet = SheetSpec(0.6f, draggable = true) {
        val workspace = station.substringBefore('/')
        val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(workspace))
        val roots = stations.value?.firstOrNull { it.station == station }?.overview?.drive?.roots.orEmpty()
        SheetGrab()
        SheetHead(t("android-misc.drive.roots.title"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            roots.forEach { r ->
                val trouble = rootTrouble(r.state)
                val busy = app.isDoing("drive.setRoots")
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    IconIn(Icons.Folder, 18.dp, if (trouble != null) C.red else C.muted)
                    Column(Modifier.weight(1f)) {
                        Text(r.name, fontSize = 15.sp, color = if (trouble != null) C.red else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(trouble ?: r.path, fontSize = 12.sp, color = if (trouble != null) C.red else C.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    Text(
                        t("android-misc.drive.roots.stop"), fontSize = 14.sp, color = if (busy) C.subtle else C.red,
                        modifier = Modifier.clip(Smooth(8.dp)).clickable(enabled = !busy) {
                            confirm(app, t("android-misc.drive.roots.stopTitle", "name" to r.name), t("android-misc.drive.roots.stopText"), t("android-misc.drive.roots.stop"), danger = true, what = t("android-misc.drive.roots.what")) {
                                app.api(station).driveSetRoots(roots.map { it.path } - r.path)
                            }
                        }.padding(horizontal = 6.dp, vertical = 4.dp),
                    )
                }
            }
            PickRow(t("android-misc.drive.roots.add"), leading = { IconIn(Icons.FolderPlus, 18.dp, C.accent) }, color = C.accent) {
                openFolderPicker(app, station, roots.map { it.path })
            }
        }
    }
}

/**
 * Picks a folder of the station to lend (the owners and admins): from its home, into folders and back up, 选这个文件夹
 * lending the one shown; `lent`, those lent already.
 */
fun openFolderPicker(app: AppState, station: String, lent: List<String>) {
    app.sheet = SheetSpec(0.8f, draggable = true) {
        var at by remember { mutableStateOf<String?>(null) }
        var shown by remember { mutableStateOf<DriveFolders?>(null) }
        var error by remember { mutableStateOf<String?>(null) }
        var loading by remember { mutableStateOf(true) }
        val scope = rememberCoroutineScope()
        fun go(path: String?) {
            loading = true; error = null
            scope.launch {
                try { shown = app.api(station).driveFolders(path); at = shown?.path } catch (e: CoreException) { error = e.message } finally { loading = false }
            }
        }
        androidx.compose.runtime.LaunchedEffect(Unit) { go(null) }
        val here = shown
        SheetGrab()
        SheetHead(t("android-misc.drive.pick.title"), trailing = { if (loading) Spinner(14.dp) })
        Text(here?.path ?: "", fontSize = 13.sp, color = C.muted, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 6.dp))
        error?.let { Text(it, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            here?.parent?.let { up -> PickRow(t("android-misc.drive.pick.up"), sub = up, leading = { IconIn(Icons.ArrowUp, 18.dp, C.muted) }) { go(up) } }
            if (here != null && here.home.isNotEmpty() && here.path != here.home) PickRow(t("android-misc.drive.pick.home"), sub = here.home, leading = { IconIn(Icons.User, 18.dp, C.muted) }) { go(here.home) }
            here?.folders?.forEach { name ->
                PickRow(name, leading = { IconIn(Icons.Folder, 18.dp, C.muted) }) { go(here.path.trimEnd('/') + "/" + name) }
            }
            if (here != null && here.folders.isEmpty()) Text(t("android-misc.drive.pick.empty"), fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))
        }
        val path = at
        val already = path != null && path in lent
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 8.dp, bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) {
            if (already) Text(t("android-misc.drive.pick.already"), fontSize = 13.sp, color = C.muted, modifier = Modifier.weight(1f))
            Button(t("common.cancel"), primary = false) { app.sheet = null }
            Button(t("android-misc.drive.pick.choose"), primary = true, enabled = path != null && !already && !loading) {
                val p = path ?: return@Button
                app.sheet = null
                app.act(t("android-misc.drive.roots.what"), done = t("android-misc.drive.roots.added", "name" to rootName(p))) { app.api(station).driveSetRoots(lent + p) }
            }
        }
    }
}

/** What the station page's row says of a drive: how many folders it lends, or that it lends none. */
fun driveValue(roots: List<DriveRoot>): String = if (roots.isEmpty()) t("android-misc.drive.row.none") else t("android-misc.drive.row.count", "n" to roots.size)

