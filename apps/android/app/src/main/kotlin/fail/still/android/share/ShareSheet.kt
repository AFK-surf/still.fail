// The sheet a shared link or text goes from (ShareActivity; docs/share-in.md): what is shared at its top, 发到 the
// chats it can go to as a picking sheet's rows (the core's `shareIn`: the one a thing from the same site went to last
// first, saying so), 新 chat last (then which station, when there are more). No field of its own: a tap puts what is
// shared in that chat's composer (`shareIn.open`) and opens the app there, where it is added to and sent.
package fail.still.android.share

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
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
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHost
import fail.still.android.ui.SheetSpec
import fail.still.core.CoreException
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Where the app opens once what is shared is in a composer: a chat (its session) of a station, or a new chat on one. */
class Opened(val station: String, val session: String?)

/** How long the sheet takes to go (SheetHost's spring), closed by hand. */
private const val SHEET_GONE_MS = 320L

/** From this many chats, the list can be searched. */
private const val SEARCHED_FROM = 6

@Composable
fun ShareScreen(shared: Shared, target: ShareTarget?, onOpen: (Opened) -> Unit, onOpenApp: () -> Unit, onClose: () -> Unit) {
    var closing by remember { mutableStateOf(false) }
    val current by rememberUpdatedState(target)
    val haze = remember { HazeState() }
    val spec = remember {
        SheetSpec(0.72f, draggable = true, onClose = { closing = true }, solid = true) {
            ShareSheetContent(shared, current, onOpen, onOpenApp)
        }
    }
    LaunchedEffect(closing) {
        if (!closing) return@LaunchedEffect
        delay(SHEET_GONE_MS)
        onClose()
    }
    Box(Modifier.fillMaxSize()) { SheetHost(if (closing) null else spec, haze) { closing = true } }
}

@Composable
private fun ColumnScope.ShareSheetContent(shared: Shared, target: ShareTarget?, onOpen: (Opened) -> Unit, onOpenApp: () -> Unit) {
    SheetGrab()
    SharedHead(shared)
    if (target == null) { Wait(t("android-chat.reading")); return }
    val workspace = target.workspace
    if (workspace == null) { SignInFirst(onOpenApp); return }
    val core = target.core
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var searching by remember { mutableStateOf(false) }
    // 新 chat with more than one station: which one, before it opens.
    var choosing by remember { mutableStateOf(false) }
    // The row being opened (its station and id, null for a new chat): a spinner in its place meanwhile.
    var opening by remember { mutableStateOf<Pair<String, String?>?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val topic = remember(workspace, query) { Topics.shareIn(workspace, shared.source, query.trim()) }
    val state by rememberTopic<ShareInView>(core, topic)
    val view = state.value
    val open = { station: String, id: String? ->
        if (opening == null) {
            opening = station to id
            error = null
            scope.launch {
                try {
                    val r = core.call("shareIn.open", buildJsonObject {
                        put("scope", workspace); put("source", shared.source); put("station", station)
                        id?.let { put("id", it) }
                        shared.title?.let { put("title", it) }
                    }).jsonObject
                    onOpen(Opened(station, r["session"]?.jsonPrimitive?.content))
                } catch (e: CoreException) {
                    error = t("android-misc.shareIn.failed", "error" to (e.message ?: ""))
                    opening = null
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
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 16.dp)) {
        when {
            view == null -> Wait(if (state.error != null) t("android-misc.shareIn.update") else t("android-chat.reading"))
            else -> {
                view.items.forEach { item ->
                    val kept = view.kept?.takeIf { it.station == item.station && it.id == item.id }
                    PickRow(
                        item.title, kept?.text ?: item.last?.preview?.takeIf { it.isNotBlank() } ?: lineOf(item),
                        busy = opening == item.station to item.id, enabled = opening == null, subLines = 1,
                        leading = { Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { item.agents.firstOrNull()?.let { MakerIcon(it.maker, it.runtime, 14.dp) } } },
                    ) { open(item.station, item.id) }
                }
                if (view.items.isEmpty() && query.isNotBlank()) Wait(t("android-chat.ref.none.match"))
                val on = view.stations.firstOrNull { it.station == view.newOn } ?: view.stations.firstOrNull()
                if (on != null && query.isBlank()) {
                    val many = view.stations.size > 1
                    PickRow(
                        t("android-misc.shareIn.newChat"), if (many && choosing) null else t("android-misc.shareIn.on", "name" to on.name),
                        busy = !many && opening == on.station to null, enabled = opening == null,
                        leading = { Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { IconIn(Icons.Compose, 16.dp, C.muted) } },
                    ) { if (many) choosing = !choosing else open(on.station, null) }
                    // Which station it starts on, when there is a choice: the one new chats start on marked.
                    if (many && choosing) view.stations.forEach { s ->
                        PickRow(s.name, checked = s.station == on.station, busy = opening == s.station to null, enabled = opening == null,
                            leading = { Spacer(Modifier.width(16.dp)) }) { open(s.station, null) }
                    }
                }
                view.note?.let { Wait(it) }
            }
        }
    }
    error?.let { Text(it, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 16.dp)) }
}

/** What is shared: its title (the app's subject, else its first line), and the site it is from. */
@Composable
private fun SharedHead(shared: Shared) {
    val first = shared.source.lineSequence().map { it.trim() }.firstOrNull { it.isNotEmpty() }.orEmpty()
    val head = shared.title ?: first
    val sub = if (shared.title != null) first else null
    // Its mark in the rows' column: a link's, or text's.
    val link = Regex("https?://", RegexOption.IGNORE_CASE).containsMatchIn(shared.source)
    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 2.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.width(16.dp).padding(top = 3.dp), contentAlignment = Alignment.Center) { IconIn(if (link) Icons.Web else Icons.Text, 16.dp, C.muted) }
        Column(Modifier.weight(1f)) {
            Text(head, fontSize = 17.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            sub?.let { Text(it, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

/** A row's second line without a last message: when it was last active, and on which station. */
private fun lineOf(item: ChatItem): String = listOfNotNull(item.time?.get("lastActiveAt")?.ago, item.stationName.takeIf { it.isNotEmpty() }).joinToString(" · ")

@Composable
private fun Wait(text: String) = Text(text, fontSize = 15.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp))

/** Nobody signed in on this phone yet: the app first. */
@Composable
private fun SignInFirst(onOpenApp: () -> Unit) {
    Wait(t("android-misc.shareIn.signIn"))
    Text(
        t("android-misc.shareIn.openApp"), fontSize = 15.sp, color = C.accent, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 20.dp).clickable { onOpenApp() }.padding(vertical = 8.dp),
    )
    Spacer(Modifier.heightIn(min = 24.dp))
}
