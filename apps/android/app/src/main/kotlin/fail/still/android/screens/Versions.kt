// A station's software and whether newer versions are out (the station's updates.rs), as the web's Versions.tsx says
// it: the station itself, Claude Code and Codex, each updated (or a runtime installed) from here by whoever may (a
// workspace's owner or admin). Grey but for what wants doing: a newer version out, an update going on, one that failed.
package fail.still.android.screens

import fail.still.android.ui.t
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.SoftwareVersion
import fail.still.android.ui.C
import fail.still.android.ui.DownloadChip
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.SectionHeader
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import java.text.DateFormat
import java.util.Date

/**
 * The station's versions as a section of its page: one to a row, then the check (with when it last looked). `updates`:
 * its overview's (none from a station older than them: nothing shows); `manager`: may update; `beta`: the 测试版 switch
 * is offered (the core's `betaOffered`).
 */
@Composable
fun Versions(station: String, updates: List<SoftwareVersion>?, manager: Boolean, beta: Boolean = false) {
    if (updates.isNullOrEmpty()) return
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(station)
    var updating by remember { mutableStateOf<String?>(null) }
    var checking by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf<String?>(null) }
    // The channel asked for, while it is being set: the switch shows it at once.
    var switching by remember { mutableStateOf<String?>(null) }
    // Updating by itself as asked, while it is being turned on or off.
    var turning by remember { mutableStateOf<Boolean?>(null) }
    val checked = updates.first().checkedAt
    val channel = updates.firstOrNull { it.id == "station" }?.channel
    val auto = updates.firstOrNull { it.id == "station" }?.auto
    SectionHeader(t("android-misc.versions.title"), checked?.let { t("android-misc.versions.lastChecked", "time" to DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(it))) }, start = 24.dp)
    ListCard {
        updates.forEach { v ->
            VersionRow(v, manager, busy = updating == v.id) {
                updating = v.id; failed = null
                scope.launch { try { api.updateSoftware(v.id) } catch (e: CoreException) { failed = e.message } finally { updating = null } }
            }
        }
        if (beta && manager && channel != null) {
            val on = (switching ?: channel) == "beta"
            ListRow(onClick = if (switching != null) null else ({
                val to = if (on) "stable" else "beta"
                switching = to; failed = null
                scope.launch { try { api.setSoftwareChannel(to) } catch (e: CoreException) { failed = e.message } finally { switching = null } }
            })) {
                Column(Modifier.weight(1f)) {
                    Text(t("android-misc.versions.beta"), fontSize = 15.sp, color = C.ink)
                    Text(t("android-misc.versions.beta.text"), fontSize = 13.sp, color = C.muted)
                }
                Switch(on)
            }
        }
        if (manager && auto != null) {
            val on = turning ?: auto
            ListRow(onClick = if (turning != null) null else ({
                turning = !on; failed = null
                scope.launch { try { api.setSoftwareAuto(!on) } catch (e: CoreException) { failed = e.message } finally { turning = null } }
            })) {
                Column(Modifier.weight(1f)) {
                    Text(t("android-misc.versions.auto"), fontSize = 15.sp, color = C.ink)
                    Text(if (updates.firstOrNull { it.id == "station" }?.idleOnly == true) "有客户端连接或 agent 工作时不自动更新，连续空闲 5 分钟后更新" else t("android-misc.versions.auto.text"), fontSize = 13.sp, color = C.muted)
                }
                Switch(on)
            }
        }
        ListRow(onClick = if (checked == null || checking) null else ({
            checking = true; failed = null
            scope.launch { try { api.checkSoftware() } catch (e: CoreException) { failed = e.message } finally { checking = false } }
        })) {
            Text(if (checked == null) t("android-misc.versions.checkingVersions") else if (checking) t("android-misc.versions.checking") else t("android-misc.versions.check"), fontSize = 15.sp, color = C.muted, modifier = Modifier.weight(1f))
            if (checking || checked == null) Spinner(13.dp)
        }
    }
    failed?.let { Text(it, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 10.dp)) }
}

/** One piece of software: its name and version, what is out, and what may be done with it. */
@Composable
private fun VersionRow(v: SoftwareVersion, manager: Boolean, busy: Boolean, onUpdate: () -> Unit) {
    val shown = if (v.installed) v.version ?: (if (v.id == "station") t("android-misc.versions.dev") else t("android-misc.versions.unknown")) else t("android-misc.versions.notInstalled")
    // What the web says on hover, said under the name.
    val note = listOfNotNull(
        if (v.state == "idle") v.done else null,
        v.note,
        if (v.installed && !v.newer && v.downgrade != true && v.latest != null) t("android-misc.updates.latest") else null,
        if (v.installed && v.latest == null && v.checkedAt != null) t("android-misc.versions.checkFailed") else null,
        if (v.state == "failed") v.message else null,
    ).filter { it.isNotBlank() }.joinToString(t("android-misc.versions.sep"))
    val action = @Composable { label: String ->
        if (manager && v.updatable) {
            if (busy) Spinner(13.dp)
            else Text(label, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.accent, modifier = Modifier.clickable(onClick = onUpdate))
        }
    }
    ListRow {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(v.name, fontSize = 15.sp, color = C.ink, maxLines = 1)
                Text(shown, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                if (v.channel == "beta") {
                    Text(t("android-misc.versions.beta"), fontSize = 11.sp, fontWeight = FontWeight.Medium, color = C.accentInk, maxLines = 1,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(C.accentBg).padding(horizontal = 6.dp, vertical = 1.dp))
                }
            }
            // Its line kept while there is nothing to say: the rows stay put as checks and updates come and go.
            Text(note.ifEmpty { " " }, fontSize = 13.sp, color = if (v.state == "failed") C.red else C.muted)
        }
        // On the name's line, not halfway down to its note: as tall as that line (an unseen 15sp line), centered in it.
        Box(Modifier.align(Alignment.Top), contentAlignment = Alignment.CenterEnd) {
            Text(" ", fontSize = 15.sp)
            when {
                v.state == "updating" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val percent = v.percent
                    if (percent != null) DownloadChip(percent) else Spinner(12.dp)
                    // Where it is, as the station says (one older than that: nothing more than 正在更新).
                    Text(v.progress ?: if (v.installed) t("android-misc.versions.updating") else t("android-misc.versions.installing"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.accentInk)
                }
                v.state == "failed" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(if (v.installed) t("android-misc.versions.updateFailed") else t("android-misc.versions.installFailed"), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.red)
                    action(t("common.retry"))
                }
                !v.installed -> action(t("android-misc.versions.install"))
                v.newer && v.latest != null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Latest(v.latest)
                    action(t("android-misc.versions.update"))
                }
                v.downgrade == true && v.latest != null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Latest(v.latest)
                    action(t("android-misc.versions.backToStable"))
                }
            }
        }
    }
}

/** What it would go to: an arrow drawn as tall as the figures, at their stroke, centred on them, then the version. */
@Composable
private fun Latest(version: String) = Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(3.dp)) {
    IconIn(Icons.ArrowRight, 18.dp, C.accentInk)
    Text(version, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.accentInk)
}
