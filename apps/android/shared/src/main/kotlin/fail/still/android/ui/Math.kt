// The local core has already read and laid out TeX. Draw the shared font's outlines on Canvas, with native text for
// characters outside its alphabet. There is no browser, formula parser, network request or per-message font here.
package fail.still.android.ui

import android.content.Context
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import androidx.core.graphics.PathParser
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.unit.sp
import kotlinx.serialization.json.*

internal data class MathGlyph(val id: String, val sx: Float, val sy: Float, val x: Float, val y: Float)
internal data class MathWord(val text: String, val sx: Float, val sy: Float, val x: Float, val y: Float)
internal data class MathRect(val x: Float, val y: Float, val w: Float, val h: Float)
internal data class MathDrawing(val width: Float, val height: Float, val baseline: Float, val draw: List<MathGlyph>, val rects: List<MathRect>, val text: List<MathWord>)

internal fun mathDrawing(value: JsonElement?): MathDrawing? = runCatching {
    val o = value as? JsonObject ?: return null
    if (o["font"]?.jsonPrimitive?.content != "tex-4.1.3") return null
    fun num(v: JsonElement?) = (v as JsonPrimitive).float.also { require(it.isFinite()) }
    val width = num(o["width"]); val height = num(o["height"]); val baseline = num(o["baseline"])
    require(width in 0f..1_000_000f && height > 0f && height <= 100_000f)
    val draw = o["draw"]!!.jsonArray.map { e -> val a = e.jsonArray; MathGlyph(a[0].jsonPrimitive.content, num(a[1]), num(a[2]), num(a[3]), num(a[4])) }
    val rects = o["rects"]!!.jsonArray.map { e -> val a = e.jsonArray; MathRect(num(a[0]), num(a[1]), num(a[2]), num(a[3])) }
    val text = o["text"]!!.jsonArray.map { e -> val a = e.jsonArray; MathWord(a[0].jsonPrimitive.content, num(a[1]), num(a[2]), num(a[3]), num(a[4])) }
    MathDrawing(width, height, baseline, draw, rects, text)
}.getOrNull()

private object MathFont {
    private var outlines: JsonObject? = null
    private val paths = android.util.LruCache<String, Path>(512)
    @Synchronized fun path(context: Context, id: String): Path? {
        paths.get(id)?.let { return it }
        val all = outlines ?: runCatching { context.assets.open("font.json").bufferedReader().use {
            Json.parseToJsonElement(it.readText()).jsonObject["glyphs"]!!.jsonObject
        } }.getOrNull()?.also { outlines = it } ?: return null
        val d = all[id]?.jsonPrimitive?.content ?: return null
        return runCatching { PathParser.createPathFromPathData(d) }.getOrNull()?.also { paths.put(id, it) }
    }
}

internal fun mathAvailable(context: Context, d: MathDrawing) = d.draw.all { MathFont.path(context, it.id) != null }

@Composable
internal fun MathCanvas(d: MathDrawing, color: Color, modifier: Modifier, top: Float = 0f) {
    val context = LocalContext.current
    val paths = remember(d, context) { d.draw.map { MathFont.path(context, it.id) } }
    val paint = remember { Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL; typeface = Typeface.SERIF; textSize = 1000f } }
    Canvas(modifier) {
        val canvas = drawContext.canvas.nativeCanvas
        val saved = canvas.save()
        // Width is always the formula's intrinsic width: a display formula scrolls instead of shrinking its letters.
        val unit = if (d.width > 0) size.width / d.width else 1f
        canvas.translate(0f, top)
        canvas.scale(unit, unit)
        paint.color = color.toArgb()
        d.draw.forEachIndexed { i, g -> paths[i]?.let { path ->
            val k = canvas.save(); canvas.translate(g.x, g.y); canvas.scale(g.sx, g.sy); canvas.drawPath(path, paint); canvas.restoreToCount(k)
        } }
        d.rects.forEach { r -> canvas.drawRect(r.x, r.y, r.x + r.w, r.y + r.h, paint) }
        d.text.forEach { w -> val k = canvas.save(); canvas.translate(w.x, w.y); canvas.scale(w.sx, w.sy); canvas.drawText(w.text, 0f, 0f, paint); canvas.restoreToCount(k) }
        canvas.restoreToCount(saved)
    }
}

@Composable
internal fun MathBlock(source: String, d: MathDrawing, size: Float) {
    val context = LocalContext.current
    if (!remember(context, d) { mathAvailable(context, d) }) {
        MdText(AnnotatedString(source), size.sp, (size * 1.5f).sp)
        return
    }
    val w = (size * d.width / 1000f).sp
    val h = (size * d.height / 1000f).sp
    val color = LocalMdInk.current ?: C.ink
    val text = remember(source) { buildAnnotatedString { appendInlineContent("math", source) } }
    // A displayed formula participates in the same passage selection as prose; its alternative is the whole TeX.
    Box(Modifier.horizontalScroll(rememberScrollState())) {
        MdText(text, size.sp, h, inline = mapOf("math" to InlineTextContent(Placeholder(w, h, PlaceholderVerticalAlign.Top)) {
            MathCanvas(d, color, Modifier.fillMaxSize())
        }))
    }
}
