// Who is in a chat, as its row in the list shows it (web/src/RowPicture.tsx): the picture, its agents' marks or its
// people's faces as `lead` says (AppState.rowPicture), and at the title's end the other.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import fail.still.android.data.ChatItem
import fail.still.android.data.Maker
import fail.still.android.data.Person
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.Mark

/** Whose pictures lead: "agents" or "people"; `setting` auto by how many people the scope has (unknown: as if alone). */
fun leading(setting: String, members: Long?): String = when (setting) {
    "agents", "people" -> setting
    else -> if ((members ?: 1L) > 1L) "people" else "agents"
}

/** A row's agents by their mark: those that look the same (one maker's models) are drawn once. */
private data class AgentGroup(val key: String, val maker: Maker?, val runtime: String)

private fun agentGroups(item: ChatItem): List<AgentGroup> =
    item.agents.map { AgentGroup(it.maker?.id ?: it.runtime, it.maker, it.runtime) }.distinctBy { it.key }

/** A chat's people in words, who started it said: "小王 发起 · Lina、你". */
private fun peopleLabel(item: ChatItem): String {
    val people = item.people.orEmpty()
    val starter = people.firstOrNull { it.id == item.creator?.id }
    val rest = people.filter { it !== starter }.joinToString("、") { it.shown.display }
    return listOfNotNull(starter?.let { "${it.shown.display} 发起" }, rest.ifEmpty { null }).joinToString(" · ")
}

private data class Cell(val x: Int, val y: Int, val size: Int)

/** Where each of a 40dp picture's cells goes, by how many there are (web: RowPicture.tsx CELLS[40]). */
private val CELLS = mapOf(
    1 to listOf(Cell(0, 0, 40)),
    2 to listOf(Cell(0, 0, 24), Cell(16, 16, 24)),
    3 to listOf(Cell(11, 0, 18), Cell(0, 22, 18), Cell(22, 22, 18)),
    4 to listOf(Cell(0, 0, 18), Cell(22, 0, 18), Cell(0, 22, 18), Cell(22, 22, 18)),
)

/**
 * Several in one picture: one fills it; two overlap corner to corner, a gap of the row's ground between; three in a
 * triangle, four in a square; more, the fourth cell counts the rest.
 */
@Composable
private fun Cluster(count: Int, draw: @Composable (index: Int, size: Dp) -> Unit) {
    val cells = CELLS.getValue(minOf(count, 4))
    val more = if (count > 4) count - 3 else 0
    cells.forEachIndexed { i, c ->
        val overlap = count == 2 && i == 1
        Box(
            Modifier.offset(c.x.dp, c.y.dp).size(c.size.dp)
                .then(if (overlap) Modifier.border(1.5.dp, C.bg, CircleShape) else Modifier),
            contentAlignment = Alignment.Center,
        ) {
            if (more > 0 && i == cells.size - 1) Box(
                Modifier.fillMaxSize().clip(CircleShape).background(lerp(C.bg, C.ink, 0.1f)), contentAlignment = Alignment.Center,
            ) { Text("+$more", fontSize = if (c.size >= 24) 12.sp else 10.sp, fontWeight = FontWeight.SemiBold, color = C.muted, lineHeight = 12.sp) }
            else draw(i, c.size.dp)
        }
    }
}

/** A person, round: their account's picture, else a lettered one; ringed in ink when they started the chat. */
@Composable
private fun Face(person: Person, size: Dp, starter: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Avatar(person.email ?: person.id, person.shown.name, size, picture = person.shown.picture)
        if (starter) Box(Modifier.size(size + 4.dp).border(1.5.dp, C.ink, CircleShape))
    }
}

/**
 * Who is in a chat, as its row's 40dp picture: what leads, its agents (one mark per maker) or its people (who
 * started it ringed). With no one to lead (a station that does not say who, a chat with no agent yet), the other, then
 * still.fail's mark.
 */
@Composable
fun RowPicture(item: ChatItem, lead: String, modifier: Modifier = Modifier) {
    val people = item.people.orEmpty()
    val groups = agentGroups(item)
    val byPeople = if (lead == "people") people.isNotEmpty() else groups.isEmpty() && people.isNotEmpty()
    val label = if (byPeople) peopleLabel(item) else item.agents.joinToString("、") { it.agentText }
    Box(modifier.size(40.dp).semantics { contentDescription = label }) {
        when {
            byPeople -> Cluster(people.size) { i, size -> Face(people[i], size, people.size > 1 && people[i].id == item.creator?.id) }
            groups.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Mark(26.dp) }
            else -> Cluster(groups.size) { i, size ->
                val g = groups[i]
                MakerIcon(g.maker, g.runtime, if (size == 40.dp) 28.dp else size - 4.dp)
            }
        }
    }
}

/**
 * What does not lead, small at the title's end: the agents beside the people (a mark per maker); the
 * people beside the agents, only when someone other than the viewer is in the chat.
 */
@Composable
fun RowAside(item: ChatItem, lead: String, modifier: Modifier = Modifier) {
    val people = item.people.orEmpty()
    if (lead == "people" && people.isNotEmpty()) {
        val groups = agentGroups(item)
        if (groups.isEmpty()) return
        val rest = groups.size - 3
        Row(modifier.semantics { contentDescription = item.agents.joinToString("、") { it.agentText } }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            groups.take(3).forEach { g -> MakerIcon(g.maker, g.runtime, 14.dp) }
            if (rest > 0) Text("+$rest", fontSize = 12.sp, color = C.muted)
        }
        return
    }
    if (people.none { !it.shown.mine }) return
    val shown = people.take(3)
    Row(modifier.semantics { contentDescription = peopleLabel(item) }, verticalAlignment = Alignment.CenterVertically) {
        shown.forEachIndexed { i, p ->
            val starter = people.size > 1 && p.id == item.creator?.id
            Face(
                p, 18.dp, starter,
                Modifier.then(if (i > 0) Modifier.offset((-3 * i).dp) else Modifier).then(if (starter) Modifier.zIndex(1f) else Modifier)
                    .border(1.5.dp, if (starter) Color.Transparent else C.bg, CircleShape),
            )
        }
        if (people.size > shown.size) Text("+${people.size - shown.size}", fontSize = 12.sp, color = C.muted, modifier = Modifier.offset((-3 * (shown.size - 1) + 3).dp))
    }
}
