package fail.still.android.screens

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupPositionProvider
import androidx.compose.ui.window.PopupProperties
import fail.still.android.LocalApp
import fail.still.android.data.StationUpdateNotice
import fail.still.android.ui.C
import fail.still.android.ui.CodeFont
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Raised
import fail.still.android.ui.reducedMotion
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
    val gap = with(density) { (-4).dp.roundToPx() }
    val margin = with(density) { 12.dp.roundToPx() }
    val arrowX = remember { mutableFloatStateOf(0f) }
    val dotCenter = with(density) { 3.dp.toPx() }
    val position = remember(gap, margin, dotCenter) { object : PopupPositionProvider {
        override fun calculatePosition(anchorBounds: IntRect, windowSize: IntSize, layoutDirection: LayoutDirection, popupContentSize: IntSize): IntOffset {
            val left = (windowSize.width - popupContentSize.width - margin).coerceAtLeast(0)
            arrowX.floatValue = (if (layoutDirection == LayoutDirection.Ltr) anchorBounds.left + dotCenter else anchorBounds.right - dotCenter) - left
            return IntOffset(left, anchorBounds.bottom + gap)
        }
    } }
    Box {
        Row(Modifier.heightIn(min = 32.dp).semantics { contentDescription = notice.text }.clickable(role = Role.Button) { control(if (notice.open == true) "close" else "open") }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(accent))
            Text(notice.label ?: notice.text, fontSize = 12.sp, lineHeight = 18.sp, color = accent, maxLines = 1)
        }
        if (notice.open == true) {
            val shape = RoundedCornerShape(14.dp)
            val width = minOf(284.dp, (LocalConfiguration.current.screenWidthDp - 24).dp)
            val surface = Raised
            Popup(popupPositionProvider = position, onDismissRequest = { control("close") }, properties = PopupProperties(focusable = true)) {
                Column(Modifier.drawBehind {
                    val half = 7.dp.toPx()
                    val edge = 12.dp.toPx()
                    val x = arrowX.floatValue.coerceIn(30.dp.toPx(), size.width - 30.dp.toPx())
                    drawPath(Path().apply {
                        moveTo(x - half, edge + 1f)
                        lineTo(x, edge - half)
                        lineTo(x + half, edge + 1f)
                        close()
                    }, surface)
                }.padding(12.dp).width(width).shadow(12.dp, shape, ambientColor = Color.Black.copy(alpha = 0.08f), spotColor = Color.Black.copy(alpha = 0.08f)).clip(shape).background(Raised).padding(start = 14.dp, end = 10.dp, top = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            if (notice.station != null) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(notice.station, Modifier.weight(1f, fill = false), fontSize = 13.sp, lineHeight = 19.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                notice.label?.let { Text(it, fontSize = 12.sp, lineHeight = 19.sp, color = accent, maxLines = 1) }
                            } else Text(notice.text, fontSize = 13.sp, lineHeight = 19.sp, fontWeight = FontWeight.Medium, color = C.ink)
                            notice.detail?.let { Text(it, fontSize = 12.sp, lineHeight = 17.sp, color = C.muted) }
                        }
                        Box(Modifier.size(32.dp).offset(y = (-6).dp).semantics { contentDescription = if (notice.dismissible == true) "不再提醒此版本" else "收起更新详情" }.clickable(role = Role.Button) { control(if (notice.dismissible == true) "dismiss" else "close") }, contentAlignment = Alignment.Center) { IconIn(Icons.Close, 14.dp, C.muted) }
                    }
                    if (notice.tone == "busy" && notice.station != null) UpdateBar(notice.percent)
                    val versions = listOfNotNull(notice.from, notice.to).joinToString(" → ")
                    if (versions.isNotEmpty() || notice.canUpdate == true) Row(Modifier.fillMaxWidth().padding(end = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(versions, Modifier.weight(1f), fontSize = 11.sp, lineHeight = 16.sp, fontFamily = CodeFont, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        if (notice.canUpdate == true) Row(Modifier.clip(CircleShape).background(C.accentBg).clickable(enabled = !busy, role = Role.Button) { app.act("更新 station") { app.api(station).updateSoftware("station") } }.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            DoingMark(busy, failed, 12.dp)
                            Text(if (busy) "更新中" else if (notice.tone == "trouble") "重试" else "现在更新", fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium, color = C.accentInk)
                        }
                    }
                }
            }
        }
    }
}

/** A thin bar under the words: how far, when the station says; else a sweep (still when motion is reduced). */
@Composable
private fun UpdateBar(percent: Double?) {
    val still = reducedMotion()
    val fill = C.accent
    val sweep = if (percent == null && !still) rememberInfiniteTransition(label = "update-bar")
        .animateFloat(-0.4f, 1f, infiniteRepeatable(tween(1400, easing = FastOutSlowInEasing)), label = "sweep").value else 0f
    Canvas(Modifier.fillMaxWidth().padding(end = 4.dp).height(3.dp).clip(RoundedCornerShape(2.dp)).background(fill.copy(alpha = 0.18f))) {
        when {
            percent != null -> drawRect(fill, size = Size(size.width * (percent / 100).toFloat(), size.height))
            still -> drawRect(fill.copy(alpha = 0.35f))
            else -> drawRect(fill, topLeft = Offset(size.width * sweep, 0f), size = Size(size.width * 0.4f, size.height))
        }
    }
}
