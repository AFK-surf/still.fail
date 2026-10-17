// 文件 as a place of the bottom bar (Places.kt): every station's lent folders (docs/drive.md), under a heading for each
// station, each opening its folder's page (DriveScreen.kt); a "+" (in the bar's notch) lends another, on a station the
// viewer may name folders on.
package fail.still.android.drive

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import fail.still.android.screens.PlaceRow
import fail.still.android.ui.SectionHeader
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextAlign
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
import fail.still.android.ui.Waiting

/** A folder lent, and the station it is on; `home` the station's home (every folder of it). */
private class Lent(val s: StationView, val root: DriveRoot, val home: Boolean = false)

@Composable
fun FilesScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val ws = current.workspace
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(ws.id))
    val workspace by rememberTopic<WorkspaceView>(app.core, Topics.workspace(ws.id))
    val list = stations.value
    // Each station's home first, for a member who browses every folder of it (as the web's sidebar), then its folders lent.
    val lent = list.orEmpty().flatMap { s ->
        val drive = s.overview?.drive
        val home = drive?.home?.takeIf { drive.anywhere == true }
        listOfNotNull(home?.let { Lent(s, DriveRoot(it, t("web-pages.drive.home"), "ok"), home = true) }) + drive?.roots.orEmpty().map { Lent(s, it) }
    }
    // Where another folder can be lent: a station online that has a drive (a station from before it has none), by
    // whoever may name its folders (the workspace's owners and admins).
    val lenders = if (workspace.value?.manager == true) list.orEmpty().filter { it.online && it.overview?.drive != null } else emptyList()
    val add = if (lenders.isNotEmpty()) BarAction("lend-folder", t("android-misc.bar.action.files"), Icons.Plus) { lend(app, lenders) } else null
    val room = LocalBarRoom.current
    val foot = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 30.dp + room
    val known = (list != null || stations.error != null) && (workspace.value != null || workspace.error != null)
    PlacePage(current, "files", add, known) { top ->
        when {
            // The stations, or a station up whose folders are not here yet: not "none lent" before it is known.
            list == null || (lent.isEmpty() && list.any { it.online && it.overview == null }) ->
                Waiting(text = t("common.reading"), error = stations.error?.message, modifier = Modifier.padding(top = top))
            lent.isEmpty() -> Column(
                Modifier.fillMaxWidth().padding(top = top).padding(horizontal = 32.dp, vertical = 56.dp),
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                IconIn(Icons.Folder, 40.dp, C.subtle)
                Text(if (lenders.isNotEmpty()) t("android-misc.files.none.manager") else t("android-misc.files.none.member"), fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            }
            else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(top = top, bottom = foot)) {
                // A heading for each station (its name; 离线 beside it while away), its folders under it.
                lent.groupBy { it.s.station }.forEach { (station, rows) ->
                    val s = rows.first().s
                    item(key = "station|$station") { SectionHeader(if (s.online) s.name else t("web-pages.drive.stationAway", "name" to s.name)) }
                    items(rows, key = { l -> "${l.s.station}|${l.root.path}" }) { l -> FolderRow(app, l) }
                }
            }
        }
    }
}

/** A folder, as the desktop sidebar's: its mark (a station's home the station's), its name (faint while the station is away). */
@Composable
private fun FolderRow(app: AppState, l: Lent) {
    PlaceRow(
        l.root.name, onClick = { app.push(Screen.Drive(l.s.station, l.root.path, "")) }, away = !l.s.online,
        mark = { IconIn(if (l.home) Icons.Server else Icons.Folder, 16.dp, C.muted) },
    )
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
