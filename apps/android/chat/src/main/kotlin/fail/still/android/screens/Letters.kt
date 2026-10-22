// What a chat's agents and other chats' agents wrote each other (session_send): not said in the chat, read in a sheet
// of its own, by the other chat, both ways in the order written (the core's `chatLetters` view; web Letters.tsx).
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.data.ChatLettersView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
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
        SheetGrab()
        SheetHead(t("web-main.letters.title"))
        val view = topic.value
        // Not here yet: its messages to come.
        if (view == null || (view.chats.isEmpty() && !view.whole)) return@SheetSpec Waiting(WaitShape.Messages, error = topic.error?.message, modifier = Modifier.weight(1f))
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(start = 14.dp, end = 14.dp, top = 4.dp, bottom = 30.dp),
            verticalArrangement = Arrangement.spacedBy(28.dp),
        ) {
            if (view.chats.isEmpty()) Text(t("web-main.letters.none"), fontSize = 15.sp, color = C.muted, modifier = Modifier.padding(vertical = 12.dp))
            view.chats.forEach { chat ->
                Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    // The other chat: its title (which opens it) and how many.
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val link = chat.link
                        Text(
                            chat.title, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false).let { mod ->
                                if (link != null) mod.clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { app.openLink(link) } else mod
                            },
                        )
                        Text(t("web-main.letters.count", "n" to chat.letters.size), fontSize = 13.sp, color = C.muted)
                    }
                    chat.letters.forEach { m -> SaidAlone(ctx, m) }
                }
            }
            // Not all of the chat is here yet: older ones may come.
            if (!view.whole) Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { Spinner() }
        }
    }
}
