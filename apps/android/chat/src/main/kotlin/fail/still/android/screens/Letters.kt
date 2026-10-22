// What a chat's agents and other chats' agents wrote each other (session_send): not said in the chat, read in a sheet
// of its own (the core's `chatLetters` view; web Letters.tsx). First the chats it wrote with, a row each, the last
// written with first; one opened, its letters both ways in the order written.
package fail.still.android.screens

import fail.still.android.data.t
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.data.ChatLettersView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.Spinner
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting

/** The chat's letters in a sheet, from its bar (Chat.kt ChatBar): each drawn as the chat draws a message (SaidAlone). */
fun openLetters(app: AppState, ctx: Here, thread: Long) {
    app.sheet = SheetSpec(0.8f, draggable = true) {
        val topic by rememberTopic<ChatLettersView>(app.core, Topics.chatLetters(ctx.station, thread))
        var opened by remember { mutableStateOf<String?>(null) }
        SheetGrab()
        SheetHead(t("web-main.letters.title"))
        val view = topic.value
        // Not here yet: its rows to come.
        if (view == null || (view.chats.isEmpty() && !view.whole)) return@SheetSpec Waiting(WaitShape.Rows, error = topic.error?.message, modifier = Modifier.weight(1f))
        val chat = view.chats.firstOrNull { it.key == opened }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 30.dp)) {
            if (view.chats.isEmpty()) Text(t("web-main.letters.none"), fontSize = 15.sp, color = C.muted, modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp))
            if (chat == null) view.chats.forEach { c ->
                // A chat it wrote with: its title, how many and when, the last letter in brief under them.
                Column(
                    Modifier.fillMaxWidth().clickable { opened = c.key }.padding(horizontal = 18.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(c.title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        val ago = c.time?.get("lastActiveAt")?.ago
                        Text(listOfNotNull(t("web-main.letters.count", "n" to c.letters.size), ago).joinToString(" · "), fontSize = 13.sp, color = C.muted)
                    }
                    Text(c.last, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            } else {
                // One opened: back to the list, its title (which opens that chat), then its letters.
                Row(Modifier.padding(start = 6.dp, end = 18.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    Box(
                        Modifier.size(36.dp).clip(CircleShape).clickable { opened = null }.semantics { contentDescription = t("web-main.letters.back") },
                        contentAlignment = Alignment.Center,
                    ) { IconIn(Icons.ChevronLeft, 20.dp, C.accent) }
                    val link = chat.link
                    Text(
                        chat.title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false).let { mod ->
                            if (link != null) mod.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { app.openLink(link) } else mod
                        },
                    )
                }
                Column(Modifier.padding(horizontal = 14.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    chat.letters.forEach { m -> SaidAlone(ctx, m) }
                }
            }
            // Not all of the chat is here yet: older ones may come.
            if (!view.whole) Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) { Spinner() }
        }
    }
}
