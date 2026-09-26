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
    val Chevron = stroked("chevron", 2.4f, "M9 6l6 6-6 6")
    val ChevronDown = stroked("chevron-down", 2.5f, "M6 9l6 6 6-6")
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
