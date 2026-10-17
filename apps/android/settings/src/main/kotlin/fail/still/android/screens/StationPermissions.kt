// A Mac station's grants to still.fail Helper (the overview's `permissions`, as the core says them: docs/remote-screens.md
// "Grants") on its page, as the phone web's (web/src/StationPermissions.tsx): a row each with what it is for and whether
// it is given; one not given asked for from here (`permissions.request`), which puts the helper's window up on that Mac.
// Where the Mac's screen can be seen and driven the next step is that screen, opened at once, for the person to click in
// the window from wherever they are; else the row says to click Allow on that Mac, and turns as they do. A station that
// says none (not a Mac, or older) shows nothing.
package fail.still.android.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.StationGrant
import fail.still.android.data.StationPermissions
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.DoingMark

/** Each grant's mark (as the web's GRANT_MARK): the screen's two by what they do, the folders by what they hold. */
private fun grantMark(id: String): ImageVector = when (id) {
    "capture" -> Icons.Monitor
    "control" -> Icons.Cursor
    "documents" -> Icons.FileText
    "downloads" -> Icons.Download
    "removable" -> Icons.Disk
    "network" -> Icons.Server
    else -> Icons.Folder
}

/** What a row does at its end (the web's grantEnd): say it is given, open the screen (its window up, the screen drivable), wait for it at the Mac, ask for it, or (a member who may not ask) say it is not given. */
private enum class GrantEnd { Granted, Open, Waiting, Request, Missing }

private fun grantEnd(g: StationGrant, p: StationPermissions): GrantEnd = when {
    g.granted -> GrantEnd.Granted
    g.asking -> if (p.screen != null) GrantEnd.Open else GrantEnd.Waiting
    p.canRequest -> GrantEnd.Request
    else -> GrantEnd.Missing
}

/** The station page's section (Stations.kt StationScreen), under its screens; `name`: the station's, the screen viewer's title. */
@Composable
internal fun StationPermissionsSection(address: String, name: String, p: StationPermissions) {
    val app = LocalApp.current
    val open = { app.openScreen(address, "desktop", name) }
    SectionHeader(t("android-misc.permissions.section"), start = 24.dp)
    ListCard {
        p.grants.forEach { g ->
            val end = grantEnd(g, p)
            ListRow {
                IconIn(grantMark(g.id), 18.dp, C.muted)
                Column(Modifier.weight(1f)) {
                    Text(g.name, fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    // While its window is up, how it is given there.
                    Text(g.line, fontSize = 13.sp, lineHeight = 18.sp, color = if (g.asking) C.ink else C.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                when (end) {
                    GrantEnd.Granted -> EndWords(t("android-misc.permissions.granted"), C.muted)
                    GrantEnd.Waiting -> EndWords(t("android-misc.permissions.waiting"), C.muted)
                    GrantEnd.Missing -> EndWords(t("android-misc.permissions.missing"), C.warn, FontWeight.Medium)
                    GrantEnd.Open -> RowAction(t("android-misc.permissions.openScreen"), onClick = open)
                    GrantEnd.Request -> {
                        val on = arrayOf("station" to address, "grant" to g.id)
                        RowAction(
                            t("android-misc.permissions.request"),
                            description = t("android-misc.permissions.requestLabel", "name" to g.name),
                            busy = app.isDoing("permissions.request", *on), failed = app.failedOf("permissions.request", *on),
                        ) {
                            // One tap: the window up on the Mac, then its screen here to click in it, where it can be driven.
                            app.act(t("android-misc.permissions.requestWhat", "name" to g.name)) { if (app.api(address).requestGrant(g.id)) open() }
                        }
                    }
                }
            }
        }
    }
    // What is unavailable now for want of a grant.
    p.note?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 10.dp)) }
}

/** A row's state at its end, in words. */
@Composable
private fun EndWords(text: String, color: Color, weight: FontWeight = FontWeight.Normal) =
    Text(text, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = weight, color = color, maxLines = 1)

/**
 * What may be done, at a row's end, in the accent (as the station's versions' rows, Versions.kt, and the phone web's):
 * a spinner before it while `busy` (not pressed again), the mark of a failure a moment after (DoingMark). Its press
 * reaches above and below the words.
 */
@Composable
private fun RowAction(label: String, description: String? = null, busy: Boolean = false, failed: String? = null, onClick: () -> Unit) {
    Row(
        Modifier.clickable(enabled = !busy, role = Role.Button, onClick = onClick)
            .let { m -> if (description != null) m.semantics { contentDescription = description } else m }
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (busy || failed != null) DoingMark(busy, failed, inline = true)
        Text(label, fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Medium, color = if (busy) C.muted else C.accent, maxLines = 1)
    }
}
