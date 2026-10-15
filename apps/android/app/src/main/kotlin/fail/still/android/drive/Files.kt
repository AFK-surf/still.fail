// 文件 as a place of the bottom bar (Places.kt): every station's lent folders in one flat list (docs/drive.md), each
// opening its folder's page (DriveScreen.kt); a "+" (in the bar's notch) lends another, on a station the viewer may name
// folders on.
package fail.still.android.drive

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.LocalBarRoom
import fail.still.android.Screen
import fail.still.android.data.DriveRoot
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.WorkspaceView
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.screens.PickRow
import fail.still.android.screens.PlacePage
import fail.still.android.ui.BarAction
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Smooth

/** A folder lent, and the station it is on. */
private class Lent(val s: StationView, val root: DriveRoot)

@Composable
fun FilesScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val ws = current.workspace
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(ws.id))
    val workspace by rememberTopic<WorkspaceView>(app.core, Topics.workspace(ws.id))
    val list = stations.value
    val lent = list.orEmpty().flatMap { s -> s.overview?.drive?.roots.orEmpty().map { Lent(s, it) } }
    // Where another folder can be lent: a station online that has a drive (a station from before it has none), by
    // whoever may name its folders (the workspace's owners and admins).
    val lenders = if (workspace.value?.manager == true) list.orEmpty().filter { it.online && it.overview?.drive != null } else emptyList()
    val add = if (lenders.isNotEmpty()) BarAction("lend-folder", t("android-misc.bar.action.files"), Icons.Plus) { lend(app, lenders) } else null
    val room = LocalBarRoom.current
    val foot = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 30.dp + room
    val known = (list != null || stations.error != null) && (workspace.value != null || workspace.error != null)
    PlacePage(current, "files", add, known) { top ->
        when {
            list == null -> Box(Modifier.padding(top = top)) { Note(stations.error?.message ?: t("android-misc.drive.reading")) }
            lent.isEmpty() -> Column(
                Modifier.fillMaxWidth().padding(top = top).padding(horizontal = 32.dp, vertical = 56.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                IconIn(Icons.Folder, 40.dp, C.subtle)
                Text(if (lenders.isNotEmpty()) t("android-misc.files.none.manager") else t("android-misc.files.none.member"), fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            }
            else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = top, bottom = foot)) {
                itemsIndexed(lent, key = { _, l -> "${l.s.station}|${l.root.path}" }) { i, l -> FolderRow(app, l, i == 0, i == lent.lastIndex) }
            }
        }
    }
}

/** A folder: its mark, its name, the station it is on in grey at its end; a station offline dims its folders. */
@Composable
private fun FolderRow(app: AppState, l: Lent, first: Boolean, last: Boolean) {
    val shape = Smooth(
        topStart = if (first) 16.dp else 0.dp, topEnd = if (first) 16.dp else 0.dp,
        bottomEnd = if (last) 16.dp else 0.dp, bottomStart = if (last) 16.dp else 0.dp,
    )
    Row(
        Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(shape).background(C.surface)
            .clickable { app.push(Screen.Drive(l.s.station, l.root.path, "")) }
            .padding(horizontal = 16.dp, vertical = 14.dp)
            .alpha(if (l.s.online) 1f else 0.45f),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        IconIn(Icons.Folder, 22.dp, C.muted)
        Text(l.root.name, fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        Text(l.s.name, fontSize = 13.sp, color = C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 140.dp))
    }
}

@Composable
private fun Note(text: String) {
    Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { Text(text, color = C.muted, fontSize = 14.sp, textAlign = TextAlign.Center) }
}

/** Another folder lent: on the one station there is, or the one chosen first. */
private fun lend(app: AppState, on: List<StationView>) {
    fun pick(s: StationView) = openFolderPicker(app, s.station, s.overview?.drive?.roots.orEmpty().map { it.path })
    if (on.size == 1) return pick(on[0])
    app.sheet = SheetSpec(0.4f, fit = (96 + on.size * 48 + 24).dp) {
        SheetGrab()
        SheetHead(t("android-misc.files.lendOn"))
        on.forEach { s -> PickRow(s.name) { app.sheet = null; pick(s) } }
        Spacer(Modifier.height(12.dp))
    }
}
