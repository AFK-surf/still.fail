// A station's software and whether newer versions are out (the station's updates.rs), as the web's Versions.tsx says
// it: the station itself, Claude Code and Codex, each updated (or a runtime installed) from here by whoever may (a
// workspace's owner or admin). Grey but for what wants doing: a newer version out, an update going on, one that failed.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
    val checked = updates.first().checkedAt
    val channel = updates.firstOrNull { it.id == "station" }?.channel
    SectionHeader("版本", checked?.let { "上次检查 ${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(it))}" }, start = 24.dp)
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
                    Text("测试版", fontSize = 15.sp, color = C.ink)
                    Text("新版本先到这里，可能不稳定", fontSize = 13.sp, color = C.muted)
                }
                Switch(on)
            }
        }
        ListRow(onClick = if (checked == null || checking) null else ({
            checking = true; failed = null
            scope.launch { try { api.checkSoftware() } catch (e: CoreException) { failed = e.message } finally { checking = false } }
        })) {
            Text(if (checked == null) "正在检查版本…" else if (checking) "正在检查…" else "检查更新", fontSize = 15.sp, color = C.muted, modifier = Modifier.weight(1f))
            if (checking || checked == null) Spinner(13.dp)
        }
    }
    failed?.let { Text(it, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 10.dp)) }
}

/** One piece of software: its name and version, what is out, and what may be done with it. */
@Composable
private fun VersionRow(v: SoftwareVersion, manager: Boolean, busy: Boolean, onUpdate: () -> Unit) {
    val verb = if (v.installed) "更新" else "安装"
    val shown = if (v.installed) v.version ?: (if (v.id == "station") "开发版" else "版本未知") else "未安装"
    // What the web says on hover, said under the name.
    val note = listOfNotNull(
        v.note,
        if (v.installed && !v.newer && v.downgrade != true && v.latest != null) "已是最新" else null,
        if (v.installed && v.latest == null && v.checkedAt != null) "查不到最新版本" else null,
        if (v.state == "failed") v.message else null,
    ).filter { it.isNotBlank() }.joinToString("；")
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
                    Text("测试版", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = C.accentInk, maxLines = 1,
                        modifier = Modifier.clip(RoundedCornerShape(50)).background(C.accentBg).padding(horizontal = 6.dp, vertical = 1.dp))
                }
            }
            if (note.isNotEmpty()) Text(note, fontSize = 13.sp, color = if (v.state == "failed") C.red else C.muted)
        }
        when {
            v.state == "updating" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Spinner(12.dp)
                Text(if (v.installed) "正在更新${if (v.id == "station") "（等 agent 这一轮跑完）" else ""}…" else "正在安装…", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.accentInk)
            }
            v.state == "failed" -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("${verb}失败", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.red)
                action("重试")
            }
            !v.installed -> action("安装")
            v.newer && v.latest != null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("→ ${v.latest}", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.accentInk)
                action("更新")
            }
            v.downgrade == true && v.latest != null -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("→ ${v.latest}", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.accentInk)
                action("回到正式版")
            }
        }
    }
}
