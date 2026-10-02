package fail.still.android.screens

import fail.still.android.ui.t
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SheetHead
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

@Serializable
internal data class PreviewLoading(val percent: Int, val total: Int, val finished: Int, val failed: Int, val resources: List<PreviewResource>)
@Serializable
internal data class PreviewResource(val id: Long, val method: String, val path: String, val since: Double, val ended: Double? = null, val status: Int? = null, val error: String? = null)
private fun loadTopic(station: String, port: Int) = buildJsonObject { put("topic", "previewLoad"); put("station", station); put("port", port) }
private fun PreviewLoading.label() =
    if (failed > 0) t("android-chat.load.label.failed", "percent" to percent, "finished" to finished, "total" to total, "failed" to failed)
    else t("android-chat.load.label", "percent" to percent, "finished" to finished, "total" to total)

@Composable
internal fun PreviewLoad(station: String, port: Int) {
    val app = LocalApp.current
    val state by rememberTopic<PreviewLoading>(app.core, loadTopic(station, port))
    val value = state.value ?: return
    val color = if (value.failed > 0) C.red else C.muted
    Box(Modifier.size(28.dp).semantics { contentDescription = value.label() }.clickable {
        app.sheet = SheetSpec(0.62f) { PreviewLoadDetails(station, port) }
    }, contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(20.dp)) {
            val stroke = Stroke(2.dp.toPx())
            drawCircle(color.copy(alpha = 0.18f), radius = 8.dp.toPx(), style = stroke)
            drawArc(color, -90f, value.percent * 3.6f, false, topLeft = androidx.compose.ui.geometry.Offset(2.dp.toPx(), 2.dp.toPx()), size = androidx.compose.ui.geometry.Size(16.dp.toPx(), 16.dp.toPx()), style = stroke)
        }
    }
}

@Composable
private fun PreviewLoadDetails(station: String, port: Int) {
    val app = LocalApp.current
    val state by rememberTopic<PreviewLoading>(app.core, loadTopic(station, port))
    val value = state.value ?: return
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp)) {
        SheetHead(value.label())
        Text(t("android-chat.load.note"), color = C.muted, fontSize = 12.sp)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(top = 12.dp)) {
            if (value.total == 0) Text(t("android-chat.load.waiting"), color = C.muted, fontSize = 13.sp)
            value.resources.forEach { r ->
                val color = if (r.error != null || (r.status ?: 0) >= 400) C.red else C.muted
                Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(r.path, color = color, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                        Text(if (r.ended == null) t("android-chat.load.loading") else if (r.error != null) t("android-chat.load.failed") else "${r.status}", color = color, fontSize = 12.sp)
                        if (r.ended != null) Text("${(r.ended - r.since).toLong().coerceAtLeast(0)} ms", color = color, fontSize = 12.sp)
                    }
                    r.error?.let { Text(it, color = color, fontSize = 12.sp) }
                }
            }
        }
    }
}
