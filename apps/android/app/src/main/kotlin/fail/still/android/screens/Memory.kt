// The agents' memory on a station, in two layers, shown as it is (the agents write it), as the desktop's Memory.tsx has
// it: the global memory (what holds across projects, read at every session's start) and each project's memory, a skill
// whose description starts with 项目记忆： and says when it applies (its whole text is read when a task matches). The
// station's other skills are listed too. Read only.
package fail.still.android.screens

import fail.still.android.ui.t
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.StationView
import fail.still.android.data.SkillFile
import fail.still.android.data.StationMemory
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.Markdown
import fail.still.android.ui.NavBar
import fail.still.android.ui.SectionHeader
import fail.still.core.CoreException

@Composable
fun MemoryScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    var memory by remember { mutableStateOf<StationMemory?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    // Read once as the page opens (it changes as agents write it, not while it is looked at), and after a skill's
    // sharing changed here.
    var round by remember { mutableStateOf(0) }
    val names = stations.value.orEmpty().associate { it.id to it.name }
    val share = { skill: SkillFile, on: Boolean ->
        app.act(t("web-main.memory.share.switch")) { app.api(address).shareSkill(skill.name, on); round += 1 }
    }
    LaunchedEffect(address, round) {
        try { memory = StillFailJson.decodeFromJsonElement(StationMemory.serializer(), app.api(address).memory()) }
        catch (e: CoreException) { error = e.message }
        catch (e: IllegalArgumentException) { error = e.message }
    }
    Column(Modifier.fillMaxSize()) {
        NavBar(s?.name ?: stationName(address), app::pop, t("android-misc.memory.title"), sub = { Text(t("android-misc.memory.sub"), fontSize = 11.sp, color = C.muted, maxLines = 1) })
        val m = memory
        if (m == null) return Loading(error?.let { t("android-misc.memory.loadFailed", "error" to it) } ?: t("android-misc.reading"))
        val projects = m.skills.filter { it.project }
        val others = m.skills.filter { !it.project }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 4.dp)) {
            SectionHeader(t("android-misc.memory.global"), start = 24.dp)
            Note(t("android-misc.memory.global.note"))
            Card { Markdown(m.global.text.trim().ifEmpty { t("android-misc.memory.empty") }, size = 14) }
            SectionHeader(t("android-misc.memory.projects"), start = 24.dp)
            Note(t("android-misc.memory.projects.note"))
            if (projects.isEmpty()) Note(t("android-misc.memory.projects.none"))
            else ListCard { projects.forEach { SkillRow(it, address, names, share) } }
            if (others.isNotEmpty()) {
                SectionHeader(t("android-misc.memory.skills"), start = 24.dp)
                Note(t("android-misc.memory.skills.note"))
                ListCard { others.forEach { SkillRow(it, address, names, share) } }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/**
 * The memory of every station, from settings (SettingsHome.kt), as the narrow web's MemoriesScreen: a row for each,
 * opening its memory (above); memory is kept on each station and not shared between them.
 */
@Composable
fun MemoriesScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val stations = topic.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-misc.settings"), app::pop)
        LargeTitle("", t("android-misc.memory.title"))
        PageNote(t("android-misc.memory.note"))
        if (stations == null) Text(topic.error?.message ?: t("android-misc.stations.loading"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(20.dp))
        else ListCard {
            stations.forEach { s ->
                if (s.online) GoRow(s.name, t("android-misc.memory.row")) { app.push(Screen.Memory(s.station)) }
                else ListRow {
                    Column(Modifier.weight(1f)) {
                        Text(s.name, fontSize = 15.sp, color = C.ink)
                        Text(t("android-misc.memory.offline"), fontSize = 13.sp, color = C.muted)
                    }
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

@Composable
private fun Note(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp))

/** A skill as a row that opens to its text, rendered; whether it is shared with the workspace's other stations (a switch
 * when open, on this station's own), or whose it is. */
@Composable
private fun SkillRow(skill: SkillFile, station: String, names: Map<String, String>, share: (SkillFile, Boolean) -> Unit) {
    val app = LocalApp.current
    var open by rememberSaveable(skill.name) { mutableStateOf(false) }
    val about = skill.about ?: skill.description
    // As the web's row (Memory.tsx, shared by its phone and PC): inset in the card, tinted while open (the web's --hover).
    Column(Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 2.dp)) {
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                .background(if (open) C.ink.copy(alpha = if (C.dark) 0.05f else 0.065f) else Color.Transparent)
                .clickable { open = !open }.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            IconIn(if (open) Icons.ChevronDown else Icons.ChevronRight, 16.dp, C.subtle, Modifier.padding(top = 2.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(skill.name, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.ink)
                    if (skill.builtin) Text(t("android-misc.memory.builtin"), fontSize = 12.sp, color = C.subtle)
                    when (skill.share?.role) {
                        "user" -> Text(t("web-main.memory.share.from", "station" to (names[skill.share.host] ?: skill.share.host.take(8))), fontSize = 12.sp, color = C.subtle)
                        "host" -> Text(t("web-main.memory.share.shared"), fontSize = 12.sp, color = C.subtle)
                    }
                }
                Text(about.ifEmpty { t("android-misc.memory.noWhen") }, fontSize = 13.sp, color = C.muted)
            }
        }
        if (open && !skill.builtin && skill.share?.role != "user") {
            val busy = app.isDoing("skill.share", "station" to station, "name" to skill.name)
            val on = skill.share?.role == "host"
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !busy) { share(skill, !on) }.padding(start = 38.dp, end = 12.dp, top = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Text(t("web-main.memory.share.switch"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
                DoingMark(busy, app.failedOf("skill.share", "station" to station, "name" to skill.name), 14.dp)
                Switch(on)
            }
            val conflicts = skill.share?.conflicts.orEmpty()
            if (conflicts.isNotEmpty()) Text("${t("web-main.memory.share.conflict")}: ${conflicts.joinToString("、")}", fontSize = 12.sp, color = C.warn, modifier = Modifier.padding(start = 38.dp, end = 12.dp, top = 6.dp))
        }
        if (open) Markdown((skill.body ?: skill.text).ifEmpty { t("android-misc.memory.empty") }, Modifier.padding(start = 38.dp, end = 12.dp, top = 12.dp, bottom = 18.dp), size = 14)
    }
}
