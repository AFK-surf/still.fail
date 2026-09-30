// Who is in a chat, as its row in the list shows it (web/src/RowPicture.tsx): its agents' marks and its people's faces,
// small at the second line's end, in the order `lead` says (the chats view's `leading`).
package fail.still.android.screens

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
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

/** A row's agents by their mark: those that look the same (one maker's models) are drawn once. */
private data class AgentGroup(val key: String, val maker: Maker?, val runtime: String)

private fun agentGroups(item: ChatItem): List<AgentGroup> =
    item.agents.map { AgentGroup(it.maker?.id ?: it.runtime, it.maker, it.runtime) }.distinctBy { it.key }

/** A person, round: their account's picture, else a lettered one; ringed in ink when they started the chat. */
@Composable
private fun Face(person: Person, size: Dp, starter: Boolean, modifier: Modifier = Modifier) {
    Box(modifier.size(size), contentAlignment = Alignment.Center) {
        Avatar(person.email ?: person.id, person.shown.name, size, picture = person.shown.picture)
        if (starter) Box(Modifier.size(size + 4.dp).border(1.5.dp, C.ink, CircleShape))
    }
}

/**
 * Who is in a chat, small at the end of its second line: its agents (a mark per maker) and its people, those that lead first. The
 * people only when they lead or someone other than the viewer is in the chat.
 */
@Composable
fun RowAside(item: ChatItem, lead: String, modifier: Modifier = Modifier) {
    val people = item.people.orEmpty()
    val groups = agentGroups(item)
    val withPeople = people.isNotEmpty() && (lead == "people" || people.any { !it.shown.mine })
    if (groups.isEmpty() && !withPeople) return
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        if (lead == "people") {
            if (withPeople) Faces(item, people)
            if (groups.isNotEmpty()) Agents(item, groups)
        } else {
            if (groups.isNotEmpty()) Agents(item, groups)
            if (withPeople) Faces(item, people)
        }
    }
}

@Composable
private fun Agents(item: ChatItem, groups: List<AgentGroup>) {
    val rest = groups.size - 3
    Row(Modifier.semantics { contentDescription = item.agents.joinToString("、") { it.agentText } }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        groups.take(3).forEach { g -> MakerIcon(g.maker, g.runtime, 14.dp) }
        if (rest > 0) Text("+$rest", fontSize = 12.sp, color = C.muted)
    }
}

@Composable
private fun Faces(item: ChatItem, people: List<Person>) {
    val shown = people.take(3)
    Row(Modifier.semantics { contentDescription = item.peopleText.orEmpty() }, verticalAlignment = Alignment.CenterVertically) {
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
