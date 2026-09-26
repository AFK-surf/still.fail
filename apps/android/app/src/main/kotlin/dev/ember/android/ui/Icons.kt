// The concept's line icons (the data URLs in design/mobile/app.css), drawn in
// the color of the text around them.
package dev.ember.android.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

private fun circle(cx: Float, cy: Float, r: Float) = "M${cx - r} ${cy}a$r $r 0 1 0 ${2 * r} 0a$r $r 0 1 0 ${-2 * r} 0Z"

private fun roundRect(x: Float, y: Float, w: Float, h: Float, r: Float) =
    "M${x + r} ${y}h${w - 2 * r}a$r $r 0 0 1 $r ${r}v${h - 2 * r}a$r $r 0 0 1 ${-r} ${r}h${-(w - 2 * r)}a$r $r 0 0 1 ${-r} ${-r}v${-(h - 2 * r)}a$r $r 0 0 1 $r ${-r}Z"

private fun stroked(name: String, width: Float, vararg paths: String) = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
    for (d in paths) {
        addPath(addPathNodes(d), fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = width, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round)
    }
}.build()

private fun filled(name: String, vararg paths: String) = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
    for (d in paths) addPath(addPathNodes(d), fill = SolidColor(Color.Black))
}.build()

object Icons {
    val Pen = stroked("pen", 2.2f, "M12 20h9", "M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z")
    val Search = stroked("search", 2.4f, circle(11f, 11f, 7f), "M20 20l-3.5-3.5")
    val Plus = stroked("plus", 2.4f, "M12 5v14M5 12h14")
    val Up = stroked("up", 2.6f, "M12 19V5M5 12l7-7 7 7")
    val More = filled("more", circle(5f, 12f, 2f), circle(12f, 12f, 2f), circle(19f, 12f, 2f))
    val Quote = filled("quote", "M4 17h5l2-4V7H5v6h3zm9 0h5l2-4V7h-6v6h3z")
    val Copy = stroked("copy", 2f, roundRect(9f, 9f, 12f, 12f, 3f), "M5 15V5a2 2 0 0 1 2-2h8")
    val Camera = stroked("camera", 2f, "M4 8h3l2-3h6l2 3h3v11H4z", circle(12f, 13f, 3.5f))
    val Photo = stroked("photo", 2f, roundRect(3f, 4f, 18f, 16f, 3f), "M3 16l5-5 5 5 3-3 5 5", circle(15f, 9f, 1.6f))
    val File = stroked("file", 2f, "M6 3h8l4 4v14H6z", "M14 3v4h4")
    val Check = stroked("check", 3f, "M5 12l5 5 9-10")
    // What an agent does, in its activity's rows.
    val Terminal = stroked("terminal", 2f, "M4 17l6-5-6-5", "M12 19h8")
    val Globe = stroked("globe", 2f, circle(12f, 12f, 9f), "M3 12h18", "M12 3a14 14 0 0 1 0 18a14 14 0 0 1 0-18")
    val Spark = stroked("spark", 2f, "M12 3l1.8 5.4L19 10l-5.2 1.6L12 17l-1.8-5.4L5 10l5.2-1.6z")
    val Wrench = stroked("wrench", 2f, "M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.1-.6-.6-2.1z")
    val Chevron = stroked("chevron", 2.4f, "M9 6l6 6-6 6")
    val ChevronDown = stroked("chevron-down", 2.5f, "M6 9l6 6 6-6")
    val ChevronUp = stroked("chevron-up", 2.5f, "M6 15l6-6 6 6")
    val ChevronRight = stroked("chevron-right", 2.5f, "M9 6l6 6-6 6")
    val ArrowRight = stroked("arrow-right", 2.5f, "M5 12h14M13 6l6 6-6 6")
    val Down = stroked("down", 2.4f, "M12 5v14M5 12l7 7 7-7")
    val Received = stroked("received", 2f, "M12 3v12M7 10l5 5 5-5", "M5 21h14")
    val Send = stroked("send", 2f, "M22 2L11 13", "M22 2l-7 20-4-9-9-4z")
    val Said = stroked("said", 2f, "M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z")
    val Stop = stroked("stop", 2f, roundRect(6f, 6f, 12f, 12f, 2f))
    val Unplug = stroked("unplug", 2f, "M19 5l3-3", "M2 22l3-3", "M6.3 20.3a2.4 2.4 0 0 0 3.4 0L12 18l-6-6-2.3 2.3a2.4 2.4 0 0 0 0 3.4z", "M7.5 13.5L10 11", "M10.5 16.5L13 14", "M12 6l6 6 2.3-2.3a2.4 2.4 0 0 0 0-3.4l-2.6-2.6a2.4 2.4 0 0 0-3.4 0z")
    val Back = stroked("back", 2.5f, "M15 5l-7 7 7 7")
    val Close = stroked("close", 2.2f, "M6 6l12 12M18 6L6 18")
    val Server = ImageVector.Builder("server", 24.dp, 24.dp, 24f, 24f).apply {
        for ((d, width) in listOf(roundRect(4f, 4f, 16f, 7f, 2.5f) to 1.9f, roundRect(4f, 13f, 16f, 7f, 2.5f) to 1.9f, "M8 7.5h.01M8 16.5h.01" to 3f)) {
            addPath(addPathNodes(d), fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = width, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round)
        }
    }.build()
    val Link = stroked("link", 2f, "M10 14a4 4 0 0 0 5.7 0l3-3a4 4 0 0 0-5.7-5.7l-1 1", "M14 10a4 4 0 0 0-5.7 0l-3 3a4 4 0 0 0 5.7 5.7l1-1")
    val External = stroked("external", 2f, "M14 4h6v6", "M20 4l-9 9", "M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5")
}
