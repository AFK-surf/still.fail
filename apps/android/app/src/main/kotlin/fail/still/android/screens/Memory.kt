// The agents' memory on a station, in two layers, shown as it is (the agents write it), as the desktop's Memory.tsx has
// it: the global memory (what holds across projects, read at every session's start) and each project's memory, a skill
// whose description starts with 项目记忆： and says when it applies (its whole text is read when a task matches). The
// station's other skills are listed too. Read only.
package fail.still.android.screens

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
    // Read once as the page opens (it changes as agents write it, not while it is looked at).
    LaunchedEffect(address) {
        try { memory = StillFailJson.decodeFromJsonElement(StationMemory.serializer(), app.api(address).memory()) }
        catch (e: CoreException) { error = e.message }
        catch (e: IllegalArgumentException) { error = e.message }
    }
    Column(Modifier.fillMaxSize()) {
        NavBar(s?.name ?: stationName(address), app::pop, "记忆", sub = { Text("所有会话共用，由 agent 自己维护", fontSize = 11.sp, color = C.muted, maxLines = 1) })
        val m = memory
        if (m == null) return Loading(error?.let { "读不到这台 station 的记忆：$it。更早的 station 还没有这一页，更新后就有。" } ?: "正在读取…")
        val projects = m.skills.filter { it.project }
        val others = m.skills.filter { !it.project }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 4.dp)) {
            SectionHeader("全局记忆", start = 24.dp)
            Note("每个会话开始时都会读。只放跨项目都适用的：团队怎么协作、怎么回复。")
            Card { Markdown(m.global.text.trim().ifEmpty { "（空的）" }, size = 14) }
            SectionHeader("项目记忆", start = 24.dp)
            Note("每个项目一份，是一个 skill：会话开始时只读「什么时候用」那句，做到相关的事才读全文。项目不一定是代码仓库。")
            if (projects.isEmpty()) Note("还没有项目记忆。agent 学到只跟某个项目有关的东西时，会自己建一个。")
            else ListCard { projects.forEach { SkillRow(it) } }
            if (others.isNotEmpty()) {
                SectionHeader("其他 skill", start = 24.dp)
                Note("团队共用的技能说明，agent 做到相关的事时读。")
                ListCard { others.forEach { SkillRow(it) } }
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
        TopBack("设置", app::pop)
        LargeTitle("", "记忆")
        PageNote("每台 station 上所有会话共用的记忆，由 agent 自己维护，各台 station 之间不同步。")
        if (stations == null) Text(topic.error?.message ?: "正在读取 station…", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(20.dp))
        else ListCard {
            stations.forEach { s ->
                if (s.online) GoRow(s.name, "全局记忆 · 项目记忆") { app.push(Screen.Memory(s.station)) }
                else ListRow {
                    Column(Modifier.weight(1f)) {
                        Text(s.name, fontSize = 15.sp, color = C.ink)
                        Text("离线，读不到它的记忆", fontSize = 13.sp, color = C.muted)
                    }
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

@Composable
private fun Note(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp))

/** A skill as a row that opens to its text, rendered. */
@Composable
private fun SkillRow(skill: SkillFile) {
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
                    if (skill.builtin) Text("station 自带", fontSize = 12.sp, color = C.subtle)
                }
                Text(about.ifEmpty { "（没写什么时候用）" }, fontSize = 13.sp, color = C.muted)
            }
        }
        if (open) Markdown((skill.body ?: skill.text).ifEmpty { "（空的）" }, Modifier.padding(start = 38.dp, end = 12.dp, top = 12.dp, bottom = 18.dp), size = 14)
    }
}
