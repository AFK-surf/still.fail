// The agents' memory on a station, in two layers, shown as it is (the agents write it), as the web's Memory.tsx has
// it: the global memory (what holds across projects, read at every session's start) and each project's memory, a skill
// whose description starts with 项目记忆： and says when it applies (its whole text is read when a task matches). The
// station's other skills are listed too. A page lists them (the global memory by its parts, a row for each skill), and
// each opens on a page of its own to be read: a skill with its other files, the global memory a part at a time.
package fail.still.android.screens

import fail.still.android.data.t
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
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
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.MemorySection
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
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting
import fail.still.android.ui.Markdown
import fail.still.android.ui.NavBar
import fail.still.android.ui.SectionHeader
import fail.still.core.CoreException

/** The last memory read of each station, so a page opened from the list has it at once (it is read again). */
private val kept = mutableMapOf<String, StationMemory>()

private class MemoryRead(val memory: StationMemory?, val error: String?, val reload: () -> Unit)

/** A station's memory, read as a page opens (it changes as agents write it, not while it is looked at) and after a
 * skill's sharing changed here, or why it could not be. */
@Composable
private fun rememberMemory(address: String): MemoryRead {
    val app = LocalApp.current
    var memory by remember(address) { mutableStateOf(kept[address]) }
    var error by remember(address) { mutableStateOf<String?>(null) }
    var round by remember(address) { mutableStateOf(0) }
    LaunchedEffect(address, round) {
        try {
            val m = StillFailJson.decodeFromJsonElement(StationMemory.serializer(), app.api(address).memory())
            kept[address] = m; memory = m; error = null
        }
        catch (e: CoreException) { error = e.message }
        catch (e: IllegalArgumentException) { error = e.message }
    }
    return MemoryRead(memory, error) { round += 1 }
}

/** The global memory's parts (all of it in one, from a core before them). */
private fun sectionsOf(m: StationMemory): List<MemorySection> {
    val text = m.global.text.trim()
    return m.global.sections.orEmpty().ifEmpty { if (text.isEmpty()) emptyList() else listOf(MemorySection(t("android-misc.memory.global"), text, "")) }
}

/** What a skill is for in a line, for its row (the core's; a core before it: when it applies, whole). */
private val SkillFile.line get() = brief ?: about ?: description

@Composable
fun MemoryScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    val names = stations.value.orEmpty().associate { it.id to it.name }
    val read = rememberMemory(address)
    var builtinOpen by rememberSaveable(address) { mutableStateOf(false) }
    Column(Modifier.fillMaxSize()) {
        NavBar(s?.name ?: stationName(address), app::pop, t("android-misc.memory.title"), sub = { Text(t("android-misc.memory.sub"), fontSize = 11.sp, color = C.muted, maxLines = 1) })
        val m = read.memory ?: return Waiting(WaitShape.Cards, text = t("common.reading"), error = read.error?.let { t("android-misc.memory.loadFailed", "error" to it) })
        val sections = sectionsOf(m)
        val projects = m.skills.filter { it.project }
        val skills = m.skills.filter { !it.project && !it.builtin }
        val builtin = m.skills.filter { !it.project && it.builtin }
        val skillRow = @Composable { k: SkillFile ->
            MemoryRow(k.name, k.line.ifEmpty { t("android-misc.memory.noWhen") }, k.size, tag = tagOf(k, names)) { app.push(Screen.MemoryDoc(address, k.name)) }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 4.dp)) {
            SectionHeader(t("android-misc.memory.global"), listOfNotNull(t("web-main.memory.global.when"), m.global.size).joinToString(" · "), start = 24.dp)
            if (sections.isEmpty()) Note(t("android-misc.memory.empty"))
            else ListCard { sections.forEachIndexed { i, p -> MemoryRow(p.title, null, p.note.ifEmpty { null }) { app.push(Screen.MemoryDoc(address, null, i)) } } }
            SectionHeader(t("android-misc.memory.projects"), t("web-main.memory.projects.when"), start = 24.dp)
            if (projects.isEmpty()) Note(t("android-misc.memory.projects.none"))
            else ListCard { projects.forEach { skillRow(it) } }
            if (skills.isNotEmpty() || builtin.isNotEmpty()) {
                SectionHeader(t("android-misc.memory.skills"), start = 24.dp)
                ListCard {
                    skills.forEach { skillRow(it) }
                    if (builtin.isNotEmpty()) MemoryRow(
                        t("android-misc.memory.builtin"), if (builtinOpen) null else builtin.joinToString(t("web-main.list.separator")) { it.name },
                        t("web-main.memory.count", "n" to builtin.size), open = builtinOpen,
                    ) { builtinOpen = !builtinOpen }
                    if (builtinOpen) builtin.forEach { skillRow(it) }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** Whose a skill is, after its name: another station's, or shared from here. */
private fun tagOf(skill: SkillFile, names: Map<String, String>): String? = when (skill.share?.role) {
    "user" -> t("web-main.memory.share.from", "station" to (names[skill.share.host] ?: skill.share.host.take(8)))
    "host" -> t("web-main.memory.share.shared")
    else -> null
}

/** A row that opens a page (or, `open` given, folds a group open): its name and whose, a line under it, how much is in it. */
@Composable
private fun MemoryRow(title: String, sub: String?, value: String?, tag: String? = null, open: Boolean? = null, onClick: () -> Unit) {
    ListRow(onClick = onClick) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (tag != null) Text(tag, fontSize = 12.sp, color = C.subtle, maxLines = 1)
            }
            if (sub != null) Text(sub, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (value != null) Text(value, fontSize = 13.sp, color = C.muted, maxLines = 1, modifier = Modifier.widthIn(max = 120.dp))
        IconIn(if (open == true) Icons.ChevronDown else Icons.ChevronRight, 14.dp, C.subtle)
    }
}

/** One of a station's memory pages: a skill with when it is read, its sharing and its files (`skill`), or the global
 * memory a part at a time (from `at`). */
@Composable
fun MemoryDocScreen(current: WorkspaceEntry, address: String, skill: String?, at: Int) {
    val app = LocalApp.current
    val read = rememberMemory(address)
    var picked by rememberSaveable(address, skill) { mutableStateOf(at) }
    val m = read.memory
    val k = if (skill == null) null else m?.skills?.firstOrNull { it.name == skill }
    val sub = when {
        skill == null -> t("web-main.memory.global.when")
        k == null -> null
        k.project -> t("android-misc.memory.projects")
        k.builtin -> t("android-misc.memory.builtin")
        else -> t("web-main.memory.skill")
    }
    Column(Modifier.fillMaxSize()) {
        NavBar(t("android-misc.memory.title"), app::pop, skill ?: t("android-misc.memory.global"), sub = sub?.let { { Text(it, fontSize = 11.sp, color = C.muted, maxLines = 1) } })
        if (m == null) return Waiting(WaitShape.Cards, text = t("common.reading"), error = read.error?.let { t("android-misc.memory.loadFailed", "error" to it) })
        // Read, and the skill is not in it (taken away since): said, not waited on.
        if (skill != null && k == null) return Text(t("web-main.memory.gone"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(24.dp))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 4.dp)) {
            if (k == null) {
                val sections = sectionsOf(m)
                val i = picked.coerceIn(0, (sections.size - 1).coerceAtLeast(0))
                DocChips(sections.map { it.title to it.note }, i) { picked = it }
                Card { Markdown(sections.getOrNull(i)?.text?.ifEmpty { null } ?: t("android-misc.memory.empty"), size = 14) }
            } else {
                Card {
                    Text(t("web-main.memory.when"), fontSize = 12.sp, fontWeight = FontWeight.Medium, color = C.subtle)
                    Text((k.about ?: k.description).ifEmpty { t("android-misc.memory.noWhen") }, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 2.dp))
                    if (!k.builtin && k.share?.role != "user") ShareRow(k, address, read.reload)
                }
                val pages = listOf(Triple(t("web-main.memory.overview"), null as String?, (k.body ?: k.text))) +
                    k.files.orEmpty().map { Triple(it.label ?: it.name, it.size, it.text) }
                val i = picked.coerceIn(0, pages.size - 1)
                DocChips(pages.map { it.first to it.second }, i) { picked = it }
                Card { Markdown(pages[i].third.ifEmpty { t("android-misc.memory.empty") }, size = 14) }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** Whether a skill of this station's is shared with the workspace's other stations, and the edits two made at once. */
@Composable
private fun ShareRow(skill: SkillFile, station: String, changed: () -> Unit) {
    val app = LocalApp.current
    val busy = app.isDoing("skill.share", "station" to station, "name" to skill.name)
    val on = skill.share?.role == "host"
    Row(
        Modifier.fillMaxWidth().padding(top = 12.dp).clickable(enabled = !busy) {
            app.act(t("web-main.memory.share.switch")) { app.api(station).shareSkill(skill.name, !on); changed() }
        },
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(t("web-main.memory.share.switch"), fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f))
        DoingMark(busy, app.failedOf("skill.share", "station" to station, "name" to skill.name))
        Switch(on)
    }
    val conflicts = skill.share?.conflicts.orEmpty()
    if (conflicts.isNotEmpty()) Text(t("web-main.memory.share.conflicts", "names" to conflicts.joinToString(t("web-main.list.separator"))), fontSize = 12.sp, color = C.warn, modifier = Modifier.padding(top = 6.dp))
}

/** Pages to pick between, as a row of pills scrolled across when they do not fit (none for a single page): a skill's
 * files, the global memory's parts; each with how much is in it. */
@Composable
private fun DocChips(items: List<Pair<String, String?>>, picked: Int, onPick: (Int) -> Unit) {
    if (items.size < 2) return
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(start = 12.dp, end = 12.dp, bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        items.forEachIndexed { i, (label, note) ->
            val on = i == picked
            Text(
                buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal)) { append(label) }
                    if (!note.isNullOrEmpty()) withStyle(SpanStyle(color = (if (on) C.bg else C.ink).copy(alpha = 0.6f))) { append("  $note") }
                },
                fontSize = 13.sp, color = if (on) C.bg else C.ink, maxLines = 1,
                modifier = Modifier.clip(RoundedCornerShape(50)).background(if (on) C.ink else C.chip).clickable { onPick(i) }.padding(horizontal = 14.dp, vertical = 7.dp),
            )
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
        if (stations == null) Waiting(WaitShape.Rows, count = 3, text = t("common.readingStations"), error = topic.error?.message)
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
