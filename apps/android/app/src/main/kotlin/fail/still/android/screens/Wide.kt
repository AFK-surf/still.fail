// A screen wider than a phone (an opened foldable, a phone on its side), as web mobile/app.tsx WIDE draws it: the pages
// the screen's whole width; at its bottom left, level with the composer and as tall, a button raises the latest chats
// over the page (the composer starts beside it); Home's new-chat button is at its bottom right.
package fail.still.android.screens

import fail.still.android.data.t
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import fail.still.android.ui.keyboard
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.Text
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatsView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.page
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.floatingStill

/** Whether the screen is wide (App.kt Pages): Home leaves its new-chat button to WideCorners then, the composer room for Recent. */
val LocalWide = androidx.compose.runtime.staticCompositionLocalOf { false }

/** Wider than this, the screen is wide (web: app.tsx WIDE). */
val WideAt = 680.dp

/** A new chat on a wide screen: a column up to 680 wide in the middle, with at least 72 of room either side. */
val NewChatColumn: Modifier = Modifier.padding(horizontal = 72.dp).widthIn(max = 680.dp)

/** Where the composer starts on a wide screen: beside the latest chats' button (10 + 52 + 10). */
val BesideRecent = 72.dp

/** What is at the screen's bottom corners, over the page (Home draws its own new-chat button only when not wide). */
@Composable
fun BoxScope.WideCorners(current: WorkspaceEntry, top: Screen) {
    val app = LocalApp.current
    val foot = Modifier.windowInsetsPadding(WindowInsets.keyboard.union(WindowInsets.navigationBars))
    when (top) {
        Screen.Home -> {
            val decisions = decisionsWaiting(current)
            androidx.compose.foundation.layout.Row(
                Modifier.align(Alignment.BottomEnd).then(foot).padding(end = 10.dp, bottom = 10.dp),
                horizontalArrangement = androidx.compose.foundation.layout.Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically,
            ) {
                DecisionsCapsule(decisions, Modifier.floatingStill(CircleShape))
                NewChatDisc()
            }
        }
        // A message's page is the chat's own, over it (Annotate.kt).
        is Screen.Annotate -> {}
        // The decisions: one at a time, back to the list; their foot is theirs.
        Screen.Decisions -> {}
        else -> Recent(current, top, foot)
    }
}

/**
 * The new-chat button: a disc of the 奏 capsule's glass in the accent, 令 white (Home.kt's Toolbar). Not frosted over the
 * pages (app.haze): drawn inside what that blurs, a frosted ring there shows the blur's own edges.
 */
@Composable
fun NewChatDisc() {
    val app = LocalApp.current
    Box(
        Modifier.floatingStill(CircleShape, C.accent).size(56.dp)
            .clickable { app.push(Screen.NewChat) }.semantics { contentDescription = t("android-misc.wide.newChat") },
        contentAlignment = Alignment.Center,
    ) { IconIn(Icons.Ling, 44.dp, Color.White) }
}

/**
 * The button for the latest chats, at the screen's bottom left as high as the composer is (ChatHost.kt: 10 from the
 * foot, 52 tall on one line), and the chats it raises over the page (not dimmed): the list's first six, the open one
 * marked; a new chat at their head, the whole list at their foot. One picked takes the place of the page open.
 */
@Composable
private fun BoxScope.Recent(current: WorkspaceEntry, top: Screen, foot: Modifier) {
    val app = LocalApp.current
    // Put away when the page changes under them (a new chat becoming its chat, a link opened), as web's on a new address.
    var open by remember(top) { mutableStateOf(false) }
    BackHandler(open) { open = false }
    if (open) Box(Modifier.fillMaxSize().clickable(remember { MutableInteractionSource() }, null) { open = false })
    AnimatedVisibility(
        open, Modifier.align(Alignment.BottomStart).then(foot).padding(start = 10.dp, bottom = 72.dp),
        enter = fadeIn(tween(180)) + scaleIn(tween(280), 0.6f, TransformOrigin(0.08f, 1.1f)),
        exit = fadeOut(tween(160)) + scaleOut(tween(200), 0.6f, TransformOrigin(0.08f, 1.1f)),
    ) {
        val chats by rememberTopic<ChatsView>(app.core, Topics.chats(current.workspace.id, false))
        val view = chats.value
        val shape = RoundedCornerShape(22.dp)
        Column(Modifier.width(340.dp).heightIn(max = 560.dp).shadow(14.dp, shape, ambientColor = Color.Black.copy(alpha = 0.2f), spotColor = Color.Black.copy(alpha = 0.2f)).floatingStill(shape)) {
            Row(Modifier.fillMaxWidth().padding(start = 18.dp, end = 12.dp, top = 12.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("android-misc.wide.recent"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, modifier = Modifier.weight(1f))
                Box(
                    Modifier.size(32.dp).clip(CircleShape).background(C.accent).clickable { open = false; app.open(Screen.NewChat) }
                        .semantics { contentDescription = t("android-misc.wide.newChat") },
                    contentAlignment = Alignment.Center,
                ) { IconIn(Icons.Ling, 26.dp, Color.White) }
            }
            if (view == null) Text(chats.error?.message ?: t("android-misc.wide.loading"), fontSize = 14.sp, color = if (chats.error != null) C.red else C.muted, modifier = Modifier.padding(18.dp))
            // No rows: what the list says in their place (the core's `note`), as the home list does.
            else if (view.days.isEmpty()) {
                val note = view.note
                val failing = note?.failing?.firstOrNull()?.text
                val said = when {
                    note?.reading == true -> t("android-misc.wide.loading")
                    failing != null -> failing
                    else -> t("android-misc.wide.empty")
                }
                Text(said, fontSize = 14.sp, color = if (failing != null && note?.reading != true) C.red else C.muted, modifier = Modifier.padding(18.dp))
            }
            else LazyColumn(Modifier.weight(1f, fill = false).padding(horizontal = 6.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) {
                items(view.days.flatMap { it.items }.take(6), key = { "${it.station}/${it.id}" }) { item ->
                    val here = top is Screen.Chat && top.station == item.station && top.of == item.page
                    ChatRowBody(
                        item, view.leading ?: "agents", false, stationTag = view.stations.size > 1,
                        modifier = Modifier.clip(RoundedCornerShape(14.dp)).background(if (here) C.accentBg else Color.Transparent)
                            .clickable { open = false; if (!here) app.open(Screen.Chat(item.station, item.page)) },
                    )
                }
            }
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(C.line))
            Row(
                Modifier.fillMaxWidth().clickable { open = false; app.home() }.padding(start = 18.dp, end = 16.dp, top = 12.dp, bottom = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(t("android-misc.wide.all"), fontSize = 14.sp, color = C.accentInk, modifier = Modifier.weight(1f))
                IconIn(Icons.ChevronRight, 16.dp, C.accentInk)
            }
        }
    }
    Box(
        Modifier.align(Alignment.BottomStart).then(foot).padding(start = 10.dp, bottom = 10.dp).size(52.dp)
            .then(if (open) Modifier.shadow(1.dp, CircleShape).clip(CircleShape).background(C.ink) else Modifier.floatingStill(CircleShape))
            .clickable { open = !open }.semantics { contentDescription = t("android-misc.wide.recent") },
        contentAlignment = Alignment.Center,
    ) { IconIn(Icons.Chats, 22.dp, if (open) C.bg else C.ink) }
}
