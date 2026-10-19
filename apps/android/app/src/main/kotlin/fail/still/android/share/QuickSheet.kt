// What is shared through the share list's second entry (Quick.kt, docs/client-plugins.md): the person's plugins that
// take it. One takes it: it runs at once (`plugins.run`), the sheet says where it went and goes by itself; several: the
// person picks; none: the ordinary sheet, as the first entry shows it. A plugin that puts it in a composer opens the
// app at that chat, as the ordinary sheet does.
package fail.still.android.share

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.data.PluginItem
import fail.still.android.data.PluginsView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.GroupLabel
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.PickRow
import fail.still.android.ui.Waiting
import fail.still.core.CoreException
import fail.still.core.StillFailCore
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** How long the sheet stays once what is shared was sent, saying where. */
private const val SENT_MS = 2200L

/** Where a plugin's run went: sent (the sheet goes by itself), or failed. */
private class Ran(val station: String, val id: String, val sent: Boolean, val error: String?)

@Composable
fun ColumnScope.QuickContent(shared: Shared, core: StillFailCore, workspace: String, onOpen: (Opened) -> Unit, onClose: () -> Unit, onNone: () -> Unit) {
    val state by rememberTopic<PluginsView>(core, remember(workspace, shared.source) { Topics.plugins(workspace, shared.source) })
    val view = state.value
    val scope = rememberCoroutineScope()
    var running by remember { mutableStateOf<Pair<String, String>?>(null) }
    var ran by remember { mutableStateOf<Ran?>(null) }
    val run = { p: PluginItem ->
        if (running == null && ran?.sent != true) {
            running = p.station to p.id
            scope.launch {
                ran = try {
                    val r = core.call("plugins.run", buildJsonObject {
                        put("scope", workspace); put("station", p.station); put("id", p.id); put("source", shared.source)
                    }).jsonObject
                    if (r["sent"]?.jsonPrimitive?.boolean != true) {
                        onOpen(Opened(p.station, r["session"]?.jsonPrimitive?.content, r["key"]?.jsonPrimitive?.content))
                        return@launch
                    }
                    Ran(p.station, p.id, true, null)
                } catch (e: CoreException) {
                    Ran(p.station, p.id, false, t("android-misc.plugins.failed", "error" to (e.message ?: "")))
                }
                running = null
            }
        }
    }
    LaunchedEffect(ran?.sent) {
        if (ran?.sent != true) return@LaunchedEffect
        delay(SENT_MS)
        onClose()
    }
    when {
        view == null -> Waiting(count = 1, text = t("common.reading"), error = state.error?.let { t("android-misc.shareIn.update") }, modifier = Modifier.weight(1f))
        view.items.isEmpty() -> LaunchedEffect(Unit) { onNone() }
        else -> {
            // The one plugin that takes it runs as the sheet comes.
            if (view.items.size == 1) LaunchedEffect(Unit) { run(view.items.first()) }
            Box(Modifier.padding(horizontal = 20.dp)) { GroupLabel(t("android-misc.plugins.with")) }
            view.items.forEach { p ->
                val mine = ran?.takeIf { it.station == p.station && it.id == p.id }
                val sub = when {
                    mine?.sent == true -> t("android-misc.plugins.sent", "chat" to (p.chat ?: p.name))
                    else -> p.chat?.let { t("android-misc.plugins.to", "chat" to it) }
                }
                PickRow(
                    p.name, sub, busy = running == p.station to p.id, done = mine?.sent == true, failed = mine?.error,
                    enabled = running == null && ran?.sent != true, subLines = 1,
                    leading = { Box(Modifier.width(16.dp), contentAlignment = Alignment.Center) { IconIn(Icons.Send, 16.dp, C.muted) } },
                ) { run(p) }
            }
            // Sent: the chat it went to, a tap away, until the sheet goes.
            view.items.firstOrNull { ran?.sent == true && it.station == ran?.station && it.id == ran?.id }?.let { p ->
                Text(
                    t("android-misc.plugins.openChat"), fontSize = 15.sp, color = C.accent, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(horizontal = 20.dp).clickable { onOpen(Opened(p.station, p.action.session, null)) }.padding(vertical = 8.dp),
                )
            }
            Spacer(Modifier.heightIn(min = 24.dp))
        }
    }
}
