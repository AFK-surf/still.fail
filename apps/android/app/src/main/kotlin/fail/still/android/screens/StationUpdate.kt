package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import fail.still.android.LocalApp
import fail.still.android.data.StationUpdateNotice
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Raised
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** The same core-owned open/dismiss/update state as the web's StationUpdate. */
@Composable
fun StationUpdateControl(station: String, notice: StationUpdateNotice?) {
    if (notice == null) return
    val app = LocalApp.current
    val busy = app.isDoing("software.update", "station" to station, "id" to "station")
    val failed = app.failedOf("software.update", "station" to station, "id" to "station")
    fun control(action: String) { app.act("设置更新提醒") { app.core.call("station.updateNotice", buildJsonObject { put("station", station); put("action", action); put("version", notice.version) }) } }
    val accent = if (notice.tone == "trouble") C.red else C.accentInk
    val density = LocalDensity.current
    val gap = with(density) { 10.dp.roundToPx() }
    val margin = with(density) { 12.dp.roundToPx() }
    val position = remember(gap, margin) { object : PopupPositionProvider {
        override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset =
            IntOffset((windowSize.width - popupContentSize.width - margin).coerceAtLeast(0), anchorBounds.bottom + gap)
    } }
    Box {
        Row(Modifier.heightIn(min = 32.dp).semantics { contentDescription = notice.text }.clickable(role = Role.Button) { control(if (notice.open == true) "close" else "open") }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(accent))
            Text(notice.label ?: notice.text, fontSize = 12.sp, lineHeight = 18.sp, color = accent, maxLines = 1)
        }
        if (notice.open == true) {
            val shape = RoundedCornerShape(14.dp)
            val width = minOf(284.dp, (LocalConfiguration.current.screenWidthDp - 24).dp)
            Popup(popupPositionProvider = position, onDismissRequest = { control("close") }, properties = PopupProperties(focusable = true)) {
                Row(Modifier.padding(12.dp).width(width).shadow(12.dp, shape, ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f)).clip(shape).background(Raised).padding(start = 16.dp, end = 8.dp, top = 12.dp, bottom = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(notice.text, fontSize = 13.sp, lineHeight = 19.sp, fontWeight = FontWeight.Medium, color = C.ink)
                        notice.detail?.let { Text(it, fontSize = 12.sp, lineHeight = 17.sp, color = C.muted) }
                    }
                    if (notice.canUpdate == true) Row(Modifier.heightIn(min = 32.dp).clickable(enabled = !busy, role = Role.Button) { app.act("更新 station") { app.api(station).updateSoftware("station") } }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        DoingMark(busy, failed, 12.dp)
                        Text(if (busy) "更新中" else "现在更新", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = C.accentInk)
                    }
                    Box(Modifier.size(32.dp).semantics { contentDescription = if (notice.dismissible == true) "不再提醒此版本" else "收起更新详情" }.clickable(role = Role.Button) { control(if (notice.dismissible == true) "dismiss" else "close") }, contentAlignment = Alignment.Center) { IconIn(Icons.Close, 18.dp, C.muted) }
                }
            }
        }
    }
}
