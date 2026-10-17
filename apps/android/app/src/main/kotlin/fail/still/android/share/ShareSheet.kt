// The sheet a shared link or text is sent from (ShareActivity; docs/share-in.md): what is shared at its top, 发到 the
// chats it can go to as a picking sheet's rows (the core's `shareIn`: the one a thing from the same site went to last
// first, saying so), 新 chat last (then which station, when there are more), and the composer's capsule under them.
// Sent, the sheet goes at once (the message waits in the chat's outbox, the core sends it) and a note says where.
package fail.still.android.share

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.chrisbanes.haze.HazeState
import fail.still.android.data.ChatItem
import fail.still.android.data.ShareInView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.screens.Field
import fail.still.android.screens.GroupLabel
import fail.still.android.screens.PickRow
import fail.still.android.screens.SendTextStyle
import fail.still.android.ui.C
import fail.still.android.ui.ComposerCorner
import fail.still.android.ui.ComposerInset
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHost
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.floatingStill
import fail.still.core.CoreException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Where it went: the chat's title (新 chat for one being made) and its item's link. */
private class SentTo(val title: String, val link: String)

/** How long the sheet takes to go (SheetHost's spring), before the window is made the note's alone. */
private const val SHEET_GONE_MS = 320L
/** How long the note stays. */
private const val NOTE_MS = 3000L

/** Above this many chats, the list can be searched. */
private const val SEARCHED_FROM = 6

@Composable
fun ShareScreen(shared: Shared, target: ShareTarget?, onSent: (Int) -> Unit, onOpenApp: (String?) -> Unit, onClose: () -> Unit) {
    var closing by remember { mutableStateOf(false) }
    var sent by remember { mutableStateOf<SentTo?>(null) }
    var gone by remember { mutableStateOf(false) }
    val current by rememberUpdatedState(target)
    val keyboard = LocalSoftwareKeyboardController.current
    val focus = LocalFocusManager.current
    val haze = remember { HazeState() }
    val spec = remember {
        SheetSpec(0.72f, draggable = true, onClose = { closing = true }, solid = true) {
            ShareSheetContent(shared, current, onSent = { focus.clearFocus(); keyboard?.hide(); sent = it; closing = true }, onOpenApp = onOpenApp)
        }
    }
    LaunchedEffect(closing) {
        if (!closing) return@LaunchedEffect
        delay(SHEET_GONE_MS)
        if (sent == null) { onClose(); return@LaunchedEffect }
        gone = true
        delay(NOTE_MS)
        onClose()
    }
    val to = sent
    if (!gone) Box(Modifier.fillMaxSize()) { SheetHost(if (closing) null else spec, haze) { closing = true } }
    else if (to != null) SentNote(to, onHeight = onSent) { onOpenApp(to.link) }
}

/**
 * Where it went, at the foot of the screen as the app's toasts are, with 打开. `onHeight`: how tall it is with the room
 * under it (px), for the window to be made that tall.
 */
@Composable
private fun SentNote(to: SentTo, onHeight: (Int) -> Unit, open: () -> Unit) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    // Laid out from the first frame, faded in: its height is the window's.
    val fade by animateFloatAsState(if (shown) 1f else 0f, tween(200), label = "note")
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.BottomCenter) {
        Box(
            Modifier.fillMaxWidth().onSizeChanged { if (it.height > 0) onHeight(it.height) }
                .windowInsetsPadding(WindowInsets.navigationBars).padding(start = 24.dp, end = 24.dp, bottom = 24.dp),
            contentAlignment = Alignment.BottomCenter,
        ) {
            Row(
                Modifier.graphicsLayer { alpha = fade }.clip(RoundedCornerShape(18.dp)).background(C.ink).padding(start = 16.dp, end = 6.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(t("android-misc.shareIn.sent", "title" to to.title), color = C.bg, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false).padding(vertical = 10.dp))
                Text(t("android-misc.shareIn.open"), color = C.accent, fontSize = 14.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(RoundedCornerShape(12.dp)).clickable(onClick = open).padding(horizontal = 10.dp, vertical = 10.dp))
            }
        }
    }
}

@Composable
private fun ColumnScope.ShareSheetContent(shared: Shared, target: ShareTarget?, onSent: (SentTo) -> Unit, onOpenApp: (String?) -> Unit) {
    SheetGrab()
    SharedHead(shared)
    if (target == null) { Wait(t("android-chat.reading")); return }
    val workspace = target.workspace
    if (workspace == null) { SignInFirst(onOpenApp); return }
    val core = target.core
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var searching by remember { mutableStateOf(false) }
    var note by remember { mutableStateOf("") }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val topic = remember(workspace, query) { Topics.shareIn(workspace, shared.source, query.trim()) }
    val state by rememberTopic<ShareInView>(core, topic)
    val view = state.value
    val pick = { station: String, id: String? ->
        error = null
        scope.launch {
            try {
                core.call("shareIn.pick", buildJsonObject { put("scope", workspace); put("source", shared.source); put("station", station); id?.let { put("id", it) } })
            } catch (e: CoreException) { error = e.message }
        }
    }
    val send = {
        if (!sending) {
            sending = true
            error = null
            scope.launch {
                try {
                    val r = core.call("shareIn.send", buildJsonObject {
                        put("scope", workspace); put("source", shared.source)
                        shared.title?.let { put("title", it) }
                        note.trim().takeIf { it.isNotEmpty() }?.let { put("text", it) }
                    }).jsonObject
                    val station = r["station"]?.jsonPrimitive?.content.orEmpty()
                    val session = r["session"]?.jsonPrimitive?.content.orEmpty()
                    onSent(SentTo(r["title"]?.jsonPrimitive?.content.orEmpty(), ShareActivity.itemLink(station, session)))
                } catch (e: CoreException) {
                    error = t("android-misc.shareIn.failed", "error" to (e.message ?: ""))
                    sending = false
                }
            }
        }
    }
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f)) { GroupLabel(t("android-misc.shareIn.to")) }
        if (searching || (view?.items?.size ?: 0) >= SEARCHED_FROM) Text(
            if (searching) t("common.cancel") else t("android-misc.shareIn.search"), fontSize = 13.sp, color = C.muted,
            modifier = Modifier.padding(top = 14.dp, bottom = 4.dp).clickable { searching = !searching; if (!searching) query = "" },
        )
    }
    if (searching) Field(query, { query = it }, t("android-misc.shareIn.find"), modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 4.dp))
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
        when {
            view == null -> Wait(if (state.error != null) t("android-misc.shareIn.update") else t("android-chat.reading"))
            else -> {
                val picked = view.picked
                view.items.forEach { item ->
                    val kept = view.kept?.takeIf { it.station == item.station && it.id == item.id }
                    PickRow(
                        item.title, kept?.text ?: lineOf(item), checked = picked?.station == item.station && picked.id == item.id,
                        leading = { Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { item.agents.firstOrNull()?.let { MakerIcon(it.maker, it.runtime, 14.dp) } } },
                    ) { pick(item.station, item.id) }
                }
                if (view.items.isEmpty() && query.isNotBlank()) Wait(t("android-chat.ref.none.match"))
                if (view.stations.isNotEmpty() && query.isBlank()) {
                    val new = picked != null && picked.id == null
                    val on = view.stations.firstOrNull { it.station == picked?.station } ?: view.stations.first()
                    PickRow(
                        t("android-misc.shareIn.newChat"), if (new) t("android-misc.shareIn.on", "name" to on.name) else null, checked = new,
                        leading = { Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { IconIn(Icons.Plus, 14.dp, C.muted) } },
                    ) { pick(on.station, null) }
                    // Which station it starts on, when there is a choice.
                    if (new && view.stations.size > 1) view.stations.forEach { s ->
                        PickRow(s.name, checked = s.station == picked?.station, leading = { Spacer(Modifier.width(16.dp)) }) { pick(s.station, null) }
                    }
                }
                view.note?.let { Wait(it) }
            }
        }
    }
    error?.let { Text(it, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) }
    Composer(note, { note = it }, ready = view?.picked != null && !sending, sending = sending, onSend = send)
}

/** What is shared: its title (the app's subject, else its first line), and the site it is from. */
@Composable
private fun SharedHead(shared: Shared) {
    val first = shared.source.lineSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() }.orEmpty()
    val head = shared.title ?: first
    val sub = if (shared.title != null) first else null
    Column(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 2.dp)) {
        Text(head, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
        sub?.let { Text(it, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
    }
}

/** A row's second line: when it was last active, and on which station. */
private fun lineOf(item: ChatItem): String = listOfNotNull(item.time?.get("lastActiveAt")?.ago, item.stationName.takeIf { it.isNotEmpty() }).joinToString(" · ")

@Composable
private fun Wait(text: String) = Text(text, fontSize = 15.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))

/** Nobody signed in on this phone yet: the app first. */
@Composable
private fun SignInFirst(onOpenApp: (String?) -> Unit) {
    Wait(t("android-misc.shareIn.signIn"))
    Text(
        t("android-misc.shareIn.openApp"), fontSize = 15.sp, color = C.accent, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 20.dp).clickable { onOpenApp(null) }.padding(vertical = 8.dp),
    )
    Spacer(Modifier.heightIn(min = 24.dp))
}

/** The composer's capsule (ChatHost's, as it sits under a new chat's page): what is added, and the send button. */
@Composable
private fun Composer(text: String, onText: (String) -> Unit, ready: Boolean, sending: Boolean, onSend: () -> Unit) {
    val style = SendTextStyle.copy(color = C.ink)
    Box(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp)) {
        Row(
            Modifier.fillMaxWidth().floatingStill(RoundedCornerShape(ComposerCorner))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {}
                .padding(ComposerInset),
            verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Box(Modifier.weight(1f).heightIn(min = 36.dp).padding(start = 14.dp, end = 14.dp, top = 7.dp, bottom = 7.dp), contentAlignment = Alignment.CenterStart) {
                if (text.isEmpty()) Text(t("android-misc.shareIn.note"), style = style.copy(color = C.subtle), maxLines = 1, overflow = TextOverflow.Ellipsis)
                BasicTextField(text, onText, textStyle = style, cursorBrush = SolidColor(C.accent), maxLines = 6, modifier = Modifier.fillMaxWidth())
            }
            // As the composer's: the ink when it can go, faint over the capsule's ground while not.
            val idle = C.ink.copy(alpha = 0.18f).compositeOver(C.surface)
            Box(
                Modifier.size(36.dp).clip(CircleShape).background(if (ready || sending) C.ink else idle).clickable(enabled = ready, onClick = onSend)
                    .semantics { contentDescription = t("android-chat.composer.send") },
                contentAlignment = Alignment.Center,
            ) {
                if (sending) CircularProgressIndicator(Modifier.size(16.dp), color = C.surface, strokeWidth = 2.dp)
                else IconIn(Icons.ArrowUp, 18.dp, if (ready) C.bg else C.surface)
            }
        }
    }
}
