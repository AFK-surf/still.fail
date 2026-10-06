// A visualization sent as a file (an HTML page placed in a message): fetched from its station with what its widget
// kept, drawn in the message (ui/Viz.kt draws the page), opened on its own, and what it keeps next sent back.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import fail.still.android.LocalApp
import fail.still.android.data.Attachment
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.VizFrame
import fail.still.android.ui.VizFull
import fail.still.android.ui.webSubtle
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull

/** A visualization's page and what its widget kept (on the station, by the session that sent it and its path), loaded together. */
internal sealed interface Loaded {
    data object Waiting : Loaded
    data object Failed : Loaded
    data class Ready(val html: String, val state: JsonElement?) : Loaded
}

/** Pages fetched, by station, session and path: a file sent never changes. */
private val pages = android.util.LruCache<String, String>(12)
/** What their widgets kept, as last read or kept here (JsonNull: nothing), so a page shown again is shown at once. */
private val keptStates = android.util.LruCache<String, JsonElement>(64)

/** Keeps what a visualization's widget keeps next: here at once, on its station after. */
internal fun keepViz(app: fail.still.android.AppState, scope: kotlinx.coroutines.CoroutineScope, station: String, key: String, path: String, state: JsonElement) {
    keptStates.put("$station/$key/$path", state)
    scope.launch { try { app.api(station).setWidgetState(key, path, state) } catch (_: CoreException) {} }
}

/**
 * A placed HTML file, drawn in its message, with ways to open it on its own under it (icons, as the web has them):
 * the whole screen, or a page of its own in the preview (web mobile's 在侧边打开). `failed`: what shows instead when the file cannot be read (its card).
 */
@Composable
fun VizFile(station: String, key: String, file: Attachment, failed: @Composable () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val loaded = rememberViz(station, key, file)
    var full by remember { mutableStateOf(false) }
    when (val l = loaded) {
        Loaded.Failed -> failed()
        Loaded.Waiting -> Box(Modifier.fillMaxWidth().padding(bottom = 8.dp).height(120.dp).clip(RoundedCornerShape(12.dp)).background(if (C.dark) androidx.compose.ui.graphics.Color(0xFF26272B) else androidx.compose.ui.graphics.Color(0xFFF6F2EA)))
        is Loaded.Ready -> {
            var kept by remember(l) { mutableStateOf(l.state) }
            val keep: (JsonElement) -> Unit = { s -> kept = s; keepViz(app, scope, station, key, file.path, s) }
            Column(Modifier.fillMaxWidth().padding(bottom = 4.dp)) {
                VizFrame(l.html, l.state, onState = keep)
                // Under the page, out of its way: the way to open it on its own, an icon in the chat's grey.
                Row(Modifier.fillMaxWidth().padding(top = 2.dp).height(22.dp), horizontalArrangement = Arrangement.spacedBy(2.dp, Alignment.End)) {
                    Box(Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).semantics { contentDescription = t("android-misc.viz.fullscreen") }.clickable { full = true }, contentAlignment = Alignment.Center) {
                        IconIn(Icons.Expand, 14.dp, webSubtle)
                    }
                    // 在侧边打开: on a phone, as web mobile has it, the file as a page of its own in the preview.
                    Box(Modifier.size(22.dp).clip(RoundedCornerShape(6.dp)).semantics { contentDescription = t("android-misc.viz.openAside") }.clickable { app.push(fail.still.android.Screen.PreviewFile(station, key, file.path, file.name)) }, contentAlignment = Alignment.Center) {
                        IconIn(Icons.PanelOpen, 14.dp, webSubtle)
                    }
                }
            }
            if (full) VizFull(file.name, l.html, kept, keep) { full = false }
        }
    }
}

/** A visualization's page and what it kept, fetched once per file. */
@Composable
internal fun rememberViz(station: String, key: String, file: Attachment): Loaded {
    val app = LocalApp.current
    val id = "$station/$key/${file.path}"
    // Read before: at once, from here (a page scrolled back to, a chat opened again), not after asking its station again.
    val known = remember(id) { pages.get(id)?.let { html -> keptStates.get(id)?.let { Loaded.Ready(html, it.takeIf { s -> s !is JsonNull }) } } }
    val loaded by produceState(known ?: Loaded.Waiting, id) {
        if (known != null) { value = known; return@produceState }
        val api = app.api(station)
        val html = pages.get(id) ?: try {
            api.file(key, file.path.substringAfterLast('/')).toString(Charsets.UTF_8).also { pages.put(id, it) }
        } catch (_: CoreException) { null }
        // What the station cannot say (an older one) is nothing kept.
        val state = keptStates.get(id) ?: try { api.widgetState(key, file.path) ?: JsonNull } catch (_: CoreException) { null }
        if (state != null) keptStates.put(id, state)
        value = if (html == null) Loaded.Failed else Loaded.Ready(html, state?.takeIf { it !is JsonNull })
    }
    return loaded
}

/** A visualization opened on its own (a link to it within a sentence): the whole screen, once it is fetched. */
@Composable
fun VizOpen(station: String, key: String, file: Attachment, onClose: () -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    when (val l = rememberViz(station, key, file)) {
        Loaded.Waiting -> Unit
        Loaded.Failed -> LaunchedEffect(Unit) { app.toast = t("android-misc.viz.cantRead"); onClose() }
        is Loaded.Ready -> {
            var kept by remember(l) { mutableStateOf(l.state) }
            VizFull(file.name, l.html, kept, { s -> kept = s; keepViz(app, scope, station, key, file.path, s) }, onClose)
        }
    }
}
