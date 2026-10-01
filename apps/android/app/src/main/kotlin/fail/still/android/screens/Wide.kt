// A screen wider than a phone (an opened foldable, a phone on its side), as web mobile/app.tsx WIDE draws it: the pages
// keep a column up to 680 wide with at least 72 of room either side; at the screen's bottom left, level with the
// composer and as tall, a button raises the latest chats over the page; Home's new-chat button is at the screen's
// corner, not the column's.
package fail.still.android.screens

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
import androidx.compose.ui.unit.Dp
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

/** Whether the pages are in a column (App.kt Pages): Home leaves its new-chat button to the screen's corner then. */
val LocalWide = androidx.compose.runtime.staticCompositionLocalOf { false }

/** Wider than this, the pages keep a column (web: styles/root.css.ts, app.tsx WIDE). */
val WideAt = 680.dp

/** The column's width on a screen `width` wide: up to 680, with at least 72 of room either side. */
fun columnWidth(width: Dp): Dp = minOf(680.dp, width - 144.dp)

/** What is at the screen's bottom corners, over the column (Home draws its own new-chat button only when not wide). */
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
                if (decisions > 0) DecisionsCapsule(decisions, Modifier.floatingStill(CircleShape))
                NewChatDisc()
            }
        }
        // A message's page is the chat's own, over it (Annotate.kt).
        is Screen.Annotate -> {}
        else -> Recent(current, top, foot)
    }
}

/**
 * The new-chat button: a disc in the accent in a ring (Home.kt's Toolbar). Not frosted over the pages (app.haze): drawn
 * inside what that blurs, a frosted ring there shows the blur's own edges.
 */
@Composable
fun NewChatDisc() {
    val app = LocalApp.current
    Box(
        Modifier.floatingStill(CircleShape).padding(6.dp).size(44.dp).clip(CircleShape).background(C.accent)
            .clickable { app.push(Screen.NewChat) }.semantics { contentDescription = "新建对话" },
        contentAlignment = Alignment.Center,
    ) { IconIn(Icons.Edit, 20.dp, Color.White) }
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
                Text("最近的会话", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink, modifier = Modifier.weight(1f))
                Box(
                    Modifier.size(32.dp).clip(CircleShape).background(C.accent).clickable { open = false; app.open(Screen.NewChat) }
                        .semantics { contentDescription = "新建对话" },
                    contentAlignment = Alignment.Center,
                ) { IconIn(Icons.Edit, 17.dp, Color.White) }
            }
            if (view == null) Text(chats.error?.message ?: "正在读取会话…", fontSize = 14.sp, color = if (chats.error != null) C.red else C.muted, modifier = Modifier.padding(18.dp))
            else LazyColumn(Modifier.weight(1f, fill = false).padding(horizontal = 6.dp), verticalArrangement = Arrangement.spacedBy(0.dp)) {
                items(view.days.flatMap { it.items }.take(6), key = { "${it.station}/${it.id}" }) { item ->
                    val here = top is Screen.Chat && top.station == item.station && top.of == item.page
                    ChatRowBody(
                        item, view.leading ?: "agents", false,
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
                Text("全部会话", fontSize = 14.sp, color = C.accentInk, modifier = Modifier.weight(1f))
                IconIn(Icons.ChevronRight, 16.dp, C.accentInk)
            }
        }
    }
    Box(
        Modifier.align(Alignment.BottomStart).then(foot).padding(start = 10.dp, bottom = 10.dp).size(52.dp)
            .then(if (open) Modifier.shadow(1.dp, CircleShape).clip(CircleShape).background(C.ink) else Modifier.floatingStill(CircleShape))
            .clickable { open = !open }.semantics { contentDescription = "最近的会话" },
        contentAlignment = Alignment.Center,
    ) { IconIn(Icons.Chats, 22.dp, if (open) C.bg else C.ink) }
}
