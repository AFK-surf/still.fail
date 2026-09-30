// Marking an image opened in a preview (web/src/annotate/ImageMarks.tsx): boxes, arrows, lines drawn by hand and
// words, drawn on the image where it is shown (zoomed and panned with it); picked again to move, stretch, recolour or
// remove; undo and redo. Done, the image with its marks, drawn again at its own size, goes into the chat's draft as a
// new file, or is downloaded.
package fail.still.android.screens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Typeface
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Strokes
import fail.still.android.ui.ZoomState
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

enum class MarkTool(val label: String) { Select("选择"), Rect("框"), Arrow("箭头"), Pen("画笔"), Text("文字") }

/** still.fail's accent, what is drawn on an image by default (literal: the viewer is dark whatever the theme). */
val INK = Color(0xFFE5704A)

/** The colours to draw in; words get an edge of `halo` to stand out on any picture. */
private val COLORS = listOf(
    INK to Color.White, Color(0xFFE5484D) to Color.White, Color(0xFFF5C518) to Color(0xFF111111), Color(0xFF30A46C) to Color.White,
    Color(0xFF3E7BFA) to Color.White, Color.White to Color(0xFF111111), Color(0xFF111111) to Color.White,
)
private fun haloOf(color: Color) = COLORS.firstOrNull { it.first == color }?.second ?: Color.White

/** On the screen, whatever the zoom (dp): a line's width, a text's size, how near a finger picks a mark. */
private const val LINE = 3f
private const val TEXT = 18f
private const val REACH = 12f
private const val LINE_HEIGHT = 1.3f
private const val BASELINE = 0.98f

/** A mark, in the image's own pixels. `w`: its line (a text's size), set by the zoom when drawn, so it looks the same on the screen. */
sealed class ImageMark(val id: Int, val color: Color, val w: Float) {
    class Box(id: Int, color: Color, w: Float, val a: Offset, val b: Offset) : ImageMark(id, color, w)
    class Arrow(id: Int, color: Color, w: Float, val a: Offset, val b: Offset) : ImageMark(id, color, w)
    class Pen(id: Int, color: Color, w: Float, val points: List<Offset>) : ImageMark(id, color, w)
    class Words(id: Int, color: Color, w: Float, val at: Offset, val text: String) : ImageMark(id, color, w)

    fun recolored(c: Color): ImageMark = when (this) {
        is Box -> Box(id, c, w, a, b); is Arrow -> Arrow(id, c, w, a, b); is Pen -> Pen(id, c, w, points); is Words -> Words(id, c, w, at, text)
    }
}

private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = Typeface.create(Typeface.DEFAULT, 600, false) }

/** How wide words are in the size `w`. */
private fun measure(text: String, w: Float): Float { textPaint.textSize = w; return textPaint.measureText(text) }

private class MarkBox(val x: Float, val y: Float, val w: Float, val h: Float)

private fun boxOf(s: ImageMark): MarkBox = when (s) {
    is ImageMark.Words -> MarkBox(s.at.x, s.at.y, measure(s.text, s.w), s.w * LINE_HEIGHT)
    else -> {
        val pts = when (s) { is ImageMark.Pen -> s.points; is ImageMark.Box -> listOf(s.a, s.b); is ImageMark.Arrow -> listOf(s.a, s.b); else -> emptyList() }
        val x = pts.minOf { it.x }; val y = pts.minOf { it.y }
        MarkBox(x, y, pts.maxOf { it.x } - x, pts.maxOf { it.y } - y)
    }
}

/** An arrow's head: its two barbs, back from its point. */
private fun barbs(a: Offset, b: Offset, w: Float): Pair<Offset, Offset> {
    val dx = b.x - a.x; val dy = b.y - a.y; val len = hypot(dx, dy).takeIf { it > 0 } ?: 1f
    val ux = dx / len; val uy = dy / len; val size = min(w * 5, len * 0.6f); val spread = 0.5f
    val back = Offset(b.x - ux * size, b.y - uy * size)
    return Offset(back.x - uy * size * spread, back.y + ux * size * spread) to Offset(back.x + uy * size * spread, back.y - ux * size * spread)
}

private fun pathOf(s: ImageMark): Path = Path().apply {
    when (s) {
        is ImageMark.Box -> {
            val b = boxOf(s); val r = min(s.w * 1.5f, min(b.w / 2, b.h / 2))
            addRoundRect(b.x, b.y, b.x + b.w, b.y + b.h, r, r, Path.Direction.CW)
        }
        is ImageMark.Arrow -> {
            val (l, r) = barbs(s.a, s.b, s.w)
            moveTo(s.a.x, s.a.y); lineTo(s.b.x, s.b.y); moveTo(l.x, l.y); lineTo(s.b.x, s.b.y); lineTo(r.x, r.y)
        }
        is ImageMark.Pen -> {
            val p = s.points
            moveTo(p[0].x, p[0].y)
            if (p.size < 3) p.drop(1).forEach { lineTo(it.x, it.y) }
            else {
                // Through the midpoints, each point bending the line: smooth, however jerky the finger.
                for (i in 1 until p.size - 1) quadTo(p[i].x, p[i].y, (p[i].x + p[i + 1].x) / 2, (p[i].y + p[i + 1].y) / 2)
                lineTo(p.last().x, p.last().y)
            }
        }
        is ImageMark.Words -> {}
    }
}

private val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }

/** The marks drawn on `canvas`, in the image's pixels. */
fun drawMarks(canvas: android.graphics.Canvas, marks: List<ImageMark>) {
    for (s in marks) {
        if (s is ImageMark.Words) {
            textPaint.textSize = s.w
            textPaint.style = Paint.Style.STROKE; textPaint.strokeWidth = s.w * 0.22f; textPaint.strokeJoin = Paint.Join.ROUND
            textPaint.color = haloOf(s.color).toArgb()
            canvas.drawText(s.text, s.at.x, s.at.y + s.w * BASELINE, textPaint)
            textPaint.style = Paint.Style.FILL; textPaint.color = s.color.toArgb()
            canvas.drawText(s.text, s.at.x, s.at.y + s.w * BASELINE, textPaint)
        } else {
            linePaint.color = s.color.toArgb(); linePaint.strokeWidth = s.w
            canvas.drawPath(pathOf(s), linePaint)
        }
    }
}

private fun moved(s: ImageMark, dx: Float, dy: Float): ImageMark {
    val d = Offset(dx, dy)
    return when (s) {
        is ImageMark.Words -> ImageMark.Words(s.id, s.color, s.w, s.at + d, s.text)
        is ImageMark.Pen -> ImageMark.Pen(s.id, s.color, s.w, s.points.map { it + d })
        is ImageMark.Box -> ImageMark.Box(s.id, s.color, s.w, s.a + d, s.b + d)
        is ImageMark.Arrow -> ImageMark.Arrow(s.id, s.color, s.w, s.a + d, s.b + d)
    }
}

/** Stretched from `anchor` by (sx, sy) (words: evenly, by sx). */
private fun scaled(s: ImageMark, anchor: Offset, sx: Float, sy: Float): ImageMark {
    fun m(p: Offset) = Offset(anchor.x + (p.x - anchor.x) * sx, anchor.y + (p.y - anchor.y) * sy)
    return when (s) {
        is ImageMark.Words -> { val k = max(0.2f, abs(sx)); ImageMark.Words(s.id, s.color, s.w * k, Offset(anchor.x + (s.at.x - anchor.x) * k, anchor.y + (s.at.y - anchor.y) * k), s.text) }
        is ImageMark.Pen -> ImageMark.Pen(s.id, s.color, s.w, s.points.map(::m))
        is ImageMark.Box -> ImageMark.Box(s.id, s.color, s.w, m(s.a), m(s.b))
        is ImageMark.Arrow -> ImageMark.Arrow(s.id, s.color, s.w, m(s.a), m(s.b))
    }
}

/** A handle of a picked mark: a corner of its box (the opposite one stays), or an end of an arrow. */
private sealed interface MarkHandle {
    data class Corner(val cx: Int, val cy: Int) : MarkHandle
    data class End(val b: Boolean) : MarkHandle
}

private fun handles(s: ImageMark): List<Pair<MarkHandle, Offset>> {
    if (s is ImageMark.Arrow) return listOf(MarkHandle.End(false) to s.a, MarkHandle.End(true) to s.b)
    val b = boxOf(s)
    val corners = if (s is ImageMark.Words) listOf(1 to 1) else listOf(0 to 0, 1 to 0, 0 to 1, 1 to 1)
    return corners.map { (cx, cy) -> MarkHandle.Corner(cx, cy) to Offset(b.x + cx * b.w, b.y + cy * b.h) }
}

private fun segment(p: Offset, a: Offset, b: Offset): Float {
    val dx = b.x - a.x; val dy = b.y - a.y; val l2 = dx * dx + dy * dy
    val t = if (l2 == 0f) 0f else (((p.x - a.x) * dx + (p.y - a.y) * dy) / l2).coerceIn(0f, 1f)
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

/** How far `p` is from the mark's line (words: 0 inside their box). */
private fun distance(s: ImageMark, p: Offset): Float = when (s) {
    is ImageMark.Words -> { val b = boxOf(s); if (p.x in b.x..b.x + b.w && p.y in b.y..b.y + b.h) 0f else Float.MAX_VALUE }
    is ImageMark.Arrow -> { val (l, r) = barbs(s.a, s.b, s.w); minOf(segment(p, s.a, s.b), segment(p, l, s.b), segment(p, r, s.b)) }
    is ImageMark.Pen -> if (s.points.size == 1) hypot(p.x - s.points[0].x, p.y - s.points[0].y) else s.points.zipWithNext().minOf { (a, b) -> segment(p, a, b) }
    is ImageMark.Box -> {
        val b = boxOf(s)
        val c = listOf(Offset(b.x, b.y), Offset(b.x + b.w, b.y), Offset(b.x + b.w, b.y + b.h), Offset(b.x, b.y + b.h))
        (c + c.first()).zipWithNext().minOf { (a, q) -> segment(p, a, q) }
    }
}

/** Words being written: new ones, or those of the text `id` again. */
private class MarkWriting(val id: Int?, val at: Offset, val text: String, val w: Float, val color: Color) {
    fun with(text: String = this.text, color: Color = this.color) = MarkWriting(id, at, text, w, color)
}

private sealed interface MarkDrag {
    class Draw(val shape: ImageMark) : MarkDrag
    class Move(val id: Int, val from: Offset, val orig: ImageMark, val handle: MarkHandle?, val before: List<ImageMark>, val changed: Boolean) : MarkDrag
}

private class MarkDoc(val shapes: List<ImageMark>, val past: List<List<ImageMark>>, val future: List<List<ImageMark>>)

/**
 * Marking one image, zoomed by `zoom`. `canDraft`: there is a chat's draft to put the marked image into.
 */
class ImageMarks(private val zoom: ZoomState, private val density: Float) : Strokes {
    var on by mutableStateOf(false)
        private set
    var tool by mutableStateOf(MarkTool.Rect)
        private set
    var color by mutableStateOf(INK)
        private set
    var palette by mutableStateOf(false)
    private var doc by mutableStateOf(MarkDoc(emptyList(), emptyList(), emptyList()))
    val shapes get() = doc.shapes
    val canUndo get() = doc.past.isNotEmpty()
    val canRedo get() = doc.future.isNotEmpty()
    var picked by mutableStateOf<Int?>(null)
        private set
    private var drag by mutableStateOf<MarkDrag?>(null)
    private var writing by mutableStateOf<MarkWriting?>(null)
    var busy by mutableStateOf(false)
    var error by mutableStateOf<String?>(null)
    private var nextId = 1
    private var lastDown = 0 to 0L

    val any get() = shapes.isNotEmpty() || writing?.text?.isNotBlank() == true
    val pickedShape get() = picked?.let { id -> shapes.firstOrNull { it.id == id } }
    val shownColor get() = writing?.color ?: pickedShape?.color ?: color

    fun start() { on = true; error = null }

    fun leave() {
        on = false; doc = MarkDoc(emptyList(), emptyList(), emptyList()); picked = null; drag = null; writing = null; error = null; palette = false
        made?.delete(); made = null
    }

    /** Back: puts down the words being written, closes the colours, lets go of the picked mark, else stops marking. */
    fun back() {
        when {
            writing != null -> putDown()
            palette -> palette = false
            picked != null -> picked = null
            else -> leave()
        }
    }

    private fun commit(next: List<ImageMark>, before: List<ImageMark>? = null) {
        val d = doc
        doc = MarkDoc(next, d.past + listOf(before ?: d.shapes), emptyList())
    }

    fun undo() {
        val d = doc
        if (d.past.isNotEmpty()) doc = MarkDoc(d.past.last(), d.past.dropLast(1), listOf(d.shapes) + d.future)
        picked = null
    }

    fun redo() {
        val d = doc
        if (d.future.isNotEmpty()) doc = MarkDoc(d.future.first(), d.past + listOf(d.shapes), d.future.drop(1))
        picked = null
    }

    fun remove(id: Int) { commit(shapes.filter { it.id != id }); picked = null }

    /** The words being written, put down (all of them gone: the text they were, removed). */
    fun putDown() {
        val w = writing ?: return
        writing = null
        val text = w.text.trim()
        if (w.id != null) {
            val was = shapes.firstOrNull { it.id == w.id } as? ImageMark.Words ?: return
            if (was.text == text && was.color == w.color) return
            commit(if (text.isNotEmpty()) shapes.map { if (it.id == w.id) ImageMark.Words(was.id, w.color, was.w, was.at, text) else it } else shapes.filter { it.id != w.id })
        } else if (text.isNotEmpty()) commit(shapes + ImageMark.Words(nextId++, w.color, w.w, w.at, text))
    }

    fun pickTool(t: MarkTool) { putDown(); tool = t; if (t != MarkTool.Select) picked = null }

    /** A colour to draw in next; the picked mark (or the words being written) takes it at once. */
    fun pickColor(c: Color) {
        color = c
        palette = false
        val w = writing
        val id = picked
        if (w != null) writing = w.with(color = c)
        else if (id != null) commit(shapes.map { if (it.id == id) it.recolored(c) else it })
    }

    private fun edit(s: ImageMark.Words) { picked = null; writing = MarkWriting(s.id, s.at, s.text, s.w, s.color) }

    // ── a finger on the image (ui/Zoom.kt's Strokes) ──

    override fun down(at: Offset) {
        if (zoom.natural == null) return
        palette = false
        if (writing != null) { putDown(); return }
        val p = zoom.toPicture(at)
        val reach = REACH / zoom.scale
        if (tool == MarkTool.Select || tool == MarkTool.Text) {
            // The picked mark's handles first, then the marks, the topmost first.
            val ps = pickedShape
            if (tool == MarkTool.Select && ps != null) {
                handles(ps).firstOrNull { (_, h) -> hypot(h.x - p.x, h.y - p.y) < reach * 1.4f }?.let { (handle, _) -> markDown(ps, p, handle); return }
            }
            val hit = shapes.lastOrNull { s -> s.id != writing?.id && (tool == MarkTool.Select || s is ImageMark.Words) && distance(s, p) <= s.w / 2 + reach }
            if (hit != null) { markDown(hit, p, null); return }
            if (tool == MarkTool.Select) { picked = null; return }
            val w = TEXT / zoom.scale
            writing = MarkWriting(null, Offset(p.x, p.y - w * 0.65f), "", w, color)
            return
        }
        val w = LINE / zoom.scale
        val id = nextId++
        drag = MarkDrag.Draw(when (tool) {
            MarkTool.Pen -> ImageMark.Pen(id, color, w, listOf(p))
            MarkTool.Arrow -> ImageMark.Arrow(id, color, w, p, p)
            else -> ImageMark.Box(id, color, w, p, p)
        })
    }

    private fun markDown(s: ImageMark, p: Offset, handle: MarkHandle?) {
        // Words pressed twice are written again.
        val now = System.currentTimeMillis()
        val again = lastDown.first == s.id && now - lastDown.second < 400
        lastDown = s.id to now
        if (s is ImageMark.Words && (tool == MarkTool.Text || (again && handle == null))) { putDown(); edit(s); return }
        picked = s.id
        drag = MarkDrag.Move(s.id, p, s, handle, shapes, false)
    }

    override fun move(at: Offset) {
        val d = drag ?: return
        val p = zoom.toPicture(at)
        if (d is MarkDrag.Draw) {
            drag = MarkDrag.Draw(when (val s = d.shape) {
                is ImageMark.Pen -> ImageMark.Pen(s.id, s.color, s.w, s.points + p)
                is ImageMark.Box -> ImageMark.Box(s.id, s.color, s.w, s.a, p)
                is ImageMark.Arrow -> ImageMark.Arrow(s.id, s.color, s.w, s.a, p)
                else -> s
            })
            return
        }
        d as MarkDrag.Move
        val o = d.orig
        val next = when (val h = d.handle) {
            null -> moved(o, p.x - d.from.x, p.y - d.from.y)
            is MarkHandle.End -> if (o is ImageMark.Arrow) (if (h.b) ImageMark.Arrow(o.id, o.color, o.w, o.a, p) else ImageMark.Arrow(o.id, o.color, o.w, p, o.b)) else o
            is MarkHandle.Corner -> {
                val b = boxOf(o)
                val anchor = Offset(b.x + (1 - h.cx) * b.w, b.y + (1 - h.cy) * b.h)
                val corner = Offset(b.x + h.cx * b.w, b.y + h.cy * b.h)
                fun ratio(to: Float, from: Float, a: Float) = if (abs(from - a) < 1e-6f) 1f else (to - a) / (from - a)
                scaled(o, anchor, ratio(p.x, corner.x, anchor.x), ratio(p.y, corner.y, anchor.y))
            }
        }
        val cur = doc
        doc = MarkDoc(cur.shapes.map { if (it.id == d.id) next else it }, cur.past, cur.future)
        if (!d.changed) drag = MarkDrag.Move(d.id, d.from, d.orig, d.handle, d.before, true)
    }

    override fun up() {
        val d = drag ?: return
        drag = null
        if (d is MarkDrag.Draw) {
            // A tap, not a drag: nothing drawn.
            val s = d.shape
            val first = when (s) { is ImageMark.Pen -> s.points.first(); is ImageMark.Box -> s.a; is ImageMark.Arrow -> s.a; else -> return }
            val rest = when (s) { is ImageMark.Pen -> s.points; is ImageMark.Box -> listOf(s.b); is ImageMark.Arrow -> listOf(s.b); else -> emptyList() }
            if (rest.any { hypot(it.x - first.x, it.y - first.y) > 4 / zoom.scale }) commit(shapes + s)
        } else if (d is MarkDrag.Move && d.changed) {
            val cur = doc
            doc = MarkDoc(cur.shapes, cur.past + listOf(d.before), emptyList())
        }
    }

    override fun cancel() {
        val d = drag
        if (d is MarkDrag.Move && d.changed) { val cur = doc; doc = MarkDoc(d.before, cur.past, cur.future) }
        drag = null
    }

    /** All the marks as they show, the words still being written included. */
    fun all(): List<ImageMark> {
        val w = writing
        val text = w?.text?.trim().orEmpty()
        var all = shapes
        if (w != null && text.isNotEmpty()) {
            all = if (w.id != null) all.map { if (it.id == w.id && it is ImageMark.Words) ImageMark.Words(it.id, w.color, it.w, it.at, text) else it }
            else all + ImageMark.Words(-1, w.color, w.w, w.at, text)
        }
        return all
    }

    /** What is drawn now over the image: the marks, the one being drawn, not the words being written. */
    fun drawn(): List<ImageMark> {
        val d = drag
        val list = if (d is MarkDrag.Draw) shapes + d.shape else shapes
        return list.filter { it.id != writing?.id }
    }

    /** The picked mark's dashed box and handles, over the marks (`k`: screen px per image px). */
    fun drawPicked(canvas: android.graphics.Canvas, k: Float) {
        val s = pickedShape ?: return
        if (tool != MarkTool.Select) return
        val reach = REACH / 2 * density / k
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = android.graphics.Color.WHITE; alpha = 217; strokeWidth = density / k }
        if (s !is ImageMark.Arrow) {
            val b = boxOf(s)
            paint.pathEffect = DashPathEffect(floatArrayOf(4 * density / k, 3 * density / k), 0f)
            canvas.drawRect(b.x - reach, b.y - reach, b.x + b.w + reach, b.y + b.h + reach, paint)
        }
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = android.graphics.Color.WHITE }
        val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; color = INK.toArgb(); strokeWidth = 1.5f * density / k }
        for ((h, at) in handles(s)) {
            val c = if (h is MarkHandle.Corner) Offset(at.x + (if (h.cx == 1) 1 else -1) * reach, at.y + (if (h.cy == 1) 1 else -1) * reach) else at
            canvas.drawCircle(c.x, c.y, 6 * density / k, fill)
            canvas.drawCircle(c.x, c.y, 6 * density / k, ring)
        }
    }

    /** Where the words being written end on the stage (px), to keep them clear of the keyboard; null when none are. */
    fun writingBottom(): Float? {
        val w = writing ?: return null
        val r = zoom.rect() ?: return null
        return r.top + (w.at.y + w.w * LINE_HEIGHT) * zoom.k
    }

    /** The words being written, where they go on the screen, in their size and colour. */
    @Composable
    fun WritingField() {
        val w = writing ?: return
        val r = zoom.rect() ?: return
        val k = zoom.k
        val focus = remember { FocusRequester() }
        val d = LocalDensity.current
        val size = with(d) { (w.w * k).toSp() }
        val width = max(measure(w.text, w.w) + w.w * 2, w.w * 6) * k
        val halo = haloOf(w.color)
        LaunchedEffect(w.id, w.at) { focus.requestFocus() }
        Box(Modifier.layout { m, _ ->
            val p = m.measure(androidx.compose.ui.unit.Constraints.fixed(width.roundToInt(), (w.w * LINE_HEIGHT * k).roundToInt()))
            layout(0, 0) { p.place(IntOffset((r.left + w.at.x * k).roundToInt(), (r.top + w.at.y * k).roundToInt())) }
        }) {
            BasicTextField(
                w.text, { t -> writing = writing?.with(text = t) },
                textStyle = TextStyle(color = w.color, fontSize = size, lineHeight = size * LINE_HEIGHT, fontWeight = FontWeight.SemiBold, shadow = Shadow(halo, blurRadius = w.w * k * 0.2f)),
                cursorBrush = SolidColor(w.color), singleLine = true,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { putDown() }),
                modifier = Modifier.focusRequester(focus),
                decorationBox = { inner ->
                    Box { if (w.text.isEmpty()) Text("写点什么", style = TextStyle(color = w.color.copy(alpha = 0.55f), fontSize = size, fontWeight = FontWeight.SemiBold)); inner() }
                },
            )
        }
    }

    /** The last marked image made, on disk (it may be bigger than is kept in memory). */
    private var made: java.io.File? = null

    /**
     * The image (its whole bytes) with the marks drawn on it, as a PNG at its own size, as web's (a canvas of the
     * image's size, `toBlob("image/png")`), with its size and a small picture. Never held whole: read in bands
     * ([BitmapRegionDecoder]), each band's marks drawn on it, its rows written out as they come ([PngRows]) into a
     * file. Its bytes come in memory only if it can be sent (at most [MAX_MARKED]); a bigger one is handed on empty
     * with its size, so the draft says it is too big, as web's does, and [save] still puts it in Downloads.
     */
    suspend fun render(bytes: ByteArray, natural: androidx.compose.ui.unit.IntSize): Picked? = withContext(Dispatchers.Default) {
        val all = all()
        made?.delete(); made = null
        val region = try {
            if (android.os.Build.VERSION.SDK_INT >= 31) BitmapRegionDecoder.newInstance(bytes, 0, bytes.size)
            else @Suppress("DEPRECATION") BitmapRegionDecoder.newInstance(bytes, 0, bytes.size, false)
        } catch (_: java.io.IOException) { null }
        // What the region reader cannot read (a GIF, a BMP) is small enough to read whole.
        val whole = if (region == null) BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@withContext null else null
        val w = region?.width ?: whole!!.width
        val h = region?.height ?: whole!!.height
        val file = java.io.File.createTempFile("marked-", ".png")
        var band: Bitmap? = null
        var small: Bitmap? = null
        try {
            val rows = max(1, min(h, BAND_PIXELS / max(1, w)))
            band = Bitmap.createBitmap(w, rows, Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(band)
            val side = max(1, max(w, h) / 160)
            small = Bitmap.createBitmap(max(1, w / side), max(1, h / side), Bitmap.Config.ARGB_8888)
            val smallCanvas = android.graphics.Canvas(small)
            val filter = Paint(Paint.FILTER_BITMAP_FLAG)
            val opts = BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 }
            val line = IntArray(w)
            var png: PngRows? = null
            java.io.BufferedOutputStream(java.io.FileOutputStream(file), 1 shl 16).use { out ->
                var y0 = 0
                while (y0 < h) {
                    val n = min(rows, h - y0)
                    band.eraseColor(android.graphics.Color.TRANSPARENT)
                    if (region != null) {
                        val piece = region.decodeRegion(android.graphics.Rect(0, y0, w, y0 + n), opts) ?: return@withContext null
                        canvas.drawBitmap(piece, 0f, 0f, null)
                        // Whether it has any see-through at all, known from the first band (as the image's).
                        if (png == null) png = PngRows(out, w, h, piece.hasAlpha())
                        piece.recycle()
                    } else {
                        canvas.drawBitmap(whole!!, 0f, -y0.toFloat(), null)
                        if (png == null) png = PngRows(out, w, h, whole.hasAlpha())
                    }
                    // The marks are in the image's own pixels (as shown: `natural`), this band from y0 down.
                    canvas.save()
                    canvas.translate(0f, -y0.toFloat())
                    canvas.scale(w.toFloat() / max(1, natural.width), h.toFloat() / max(1, natural.height))
                    drawMarks(canvas, all)
                    canvas.restore()
                    for (r in 0 until n) { band.getPixels(line, 0, w, 0, r, w, 1); png!!.row(line) }
                    val k = small.height.toFloat() / h
                    smallCanvas.drawBitmap(band, android.graphics.Rect(0, 0, w, n), android.graphics.RectF(0f, y0 * k, small.width.toFloat(), (y0 + n) * k), filter)
                    y0 += n
                }
                png!!.end()
            }
            made = file
            val size = file.length()
            val picture = small.asImageBitmap()
            small = null
            if (size > MAX_MARKED) Picked("", ByteArray(0), w, h, picture, size) else Picked("", file.readBytes(), w, h, picture)
        } catch (_: OutOfMemoryError) {
            file.delete()
            throw IllegalStateException("图片太大，没能画出来")
        } catch (e: java.io.IOException) {
            file.delete()
            throw IllegalStateException("没能画出图片", e)
        } finally {
            region?.recycle()
            whole?.recycle()
            band?.recycle()
            small?.recycle()
        }
    }

    /** The marked image last made ([render]) put in the phone's Downloads, streamed from its file. */
    suspend fun save(context: android.content.Context, name: String): Boolean = withContext(Dispatchers.IO) {
        val file = made ?: return@withContext false
        val values = android.content.ContentValues().apply {
            put(android.provider.MediaStore.Downloads.DISPLAY_NAME, name)
            put(android.provider.MediaStore.Downloads.MIME_TYPE, "image/png")
        }
        val uri = context.contentResolver.insert(android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: return@withContext false
        context.contentResolver.openOutputStream(uri)?.use { o -> file.inputStream().use { it.copyTo(o, 1 shl 16) } } != null
    }
}

/** How many pixels a band of the image read at a time has (4 bytes each): a few MB, whatever the image. */
private const val BAND_PIXELS = 2 shl 20
/** What can be sent (Composer.kt MAX_FILE, the station's MAX_UPLOAD): bigger is not read into memory. */
private const val MAX_MARKED = 50L * 1024 * 1024

/**
 * A PNG written a row at a time into `out`: 8-bit RGB (RGBA if `alpha`), each row filtered the way that leaves the
 * least to squeeze (libpng's heuristic: the smallest sum of the filtered bytes as signed), deflated as it comes, in
 * IDAT chunks of up to 256 KB.
 */
private class PngRows(private val out: java.io.OutputStream, private val width: Int, height: Int, alpha: Boolean) {
    private val bpp = if (alpha) 4 else 3
    private val n = width * bpp
    private var prev = ByteArray(n)
    private var cur = ByteArray(n)
    /** The row filtered each way (None, Sub, Up, Average, Paeth), its filter's number first. */
    private val ways = Array(5) { ByteArray(n + 1).also { b -> b[0] = it.toByte() } }
    private val idat = Chunks(out)
    private val deflater = java.util.zip.Deflater(6)
    private val z = java.util.zip.DeflaterOutputStream(idat, deflater, 1 shl 16)

    init {
        out.write(byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte(), 13, 10, 26, 10))
        val ihdr = java.nio.ByteBuffer.allocate(13).putInt(width).putInt(height)
            .put(8).put(if (alpha) 6 else 2).put(0).put(0).put(0).array()
        chunk(out, "IHDR", ihdr, ihdr.size)
    }

    /** One row, as the non-premultiplied ARGB of [Bitmap.getPixels]. */
    fun row(argb: IntArray) {
        val c = cur
        var j = 0
        for (i in 0 until width) {
            val p = argb[i]
            c[j] = (p shr 16).toByte(); c[j + 1] = (p shr 8).toByte(); c[j + 2] = p.toByte()
            if (bpp == 4) c[j + 3] = (p ushr 24).toByte()
            j += bpp
        }
        val none = ways[0]; val sub = ways[1]; val up = ways[2]; val avg = ways[3]; val paeth = ways[4]
        var s0 = 0L; var s1 = 0L; var s2 = 0L; var s3 = 0L; var s4 = 0L
        val u = prev
        for (i in 0 until n) {
            val x = c[i].toInt() and 0xff
            val a = if (i >= bpp) c[i - bpp].toInt() and 0xff else 0
            val b = u[i].toInt() and 0xff
            val cc = if (i >= bpp) u[i - bpp].toInt() and 0xff else 0
            val pa = abs(b - cc); val pb = abs(a - cc); val pc = abs(a + b - 2 * cc)
            val pred = if (pa <= pb && pa <= pc) a else if (pb <= pc) b else cc
            val v0 = x.toByte(); val v1 = (x - a).toByte(); val v2 = (x - b).toByte(); val v3 = (x - ((a + b) shr 1)).toByte(); val v4 = (x - pred).toByte()
            none[i + 1] = v0; sub[i + 1] = v1; up[i + 1] = v2; avg[i + 1] = v3; paeth[i + 1] = v4
            s0 += abs(v0.toInt()); s1 += abs(v1.toInt()); s2 += abs(v2.toInt()); s3 += abs(v3.toInt()); s4 += abs(v4.toInt())
        }
        var best = 0; var least = s0
        if (s1 < least) { best = 1; least = s1 }
        if (s2 < least) { best = 2; least = s2 }
        if (s3 < least) { best = 3; least = s3 }
        if (s4 < least) { best = 4 }
        z.write(ways[best], 0, n + 1)
        prev = c; cur = u
    }

    fun end() {
        z.finish()
        deflater.end()
        idat.flush()
        chunk(out, "IEND", ByteArray(0), 0)
    }

    /** What the deflater gives, as IDAT chunks. */
    private class Chunks(private val out: java.io.OutputStream) : java.io.OutputStream() {
        private val buf = ByteArray(1 shl 18)
        private var at = 0
        override fun write(b: Int) { if (at == buf.size) flush(); buf[at++] = b.toByte() }
        override fun write(b: ByteArray, off: Int, len: Int) {
            var o = off; var left = len
            while (left > 0) {
                if (at == buf.size) flush()
                val k = min(left, buf.size - at)
                System.arraycopy(b, o, buf, at, k); at += k; o += k; left -= k
            }
        }
        override fun flush() { if (at > 0) { chunk(out, "IDAT", buf, at); at = 0 } }
    }

    companion object {
        fun chunk(out: java.io.OutputStream, type: String, data: ByteArray, len: Int) {
            val t = type.toByteArray(Charsets.US_ASCII)
            val crc = java.util.zip.CRC32().apply { update(t); update(data, 0, len) }
            out.write(java.nio.ByteBuffer.allocate(4).putInt(len).array())
            out.write(t)
            out.write(data, 0, len)
            out.write(java.nio.ByteBuffer.allocate(4).putInt(crc.value.toInt()).array())
        }
    }
}

// ── the bars ───────────────────────────────────────────────────────────

/** In the top bar while marking: what to do with the marks. */
@Composable
fun MarksActions(marks: ImageMarks, canDraft: Boolean, onDownload: () -> Unit, onDraft: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        marks.error?.let { Text(it, fontSize = 13.sp, color = Color(0xFFFF7B6B), maxLines = 1, modifier = Modifier.padding(horizontal = 6.dp)) }
        Box(Modifier.height(30.dp).clip(RoundedCornerShape(15.dp)).clickable { marks.leave() }.padding(horizontal = 10.dp), contentAlignment = Alignment.Center) {
            Text("取消", fontSize = 13.sp, color = Color.White.copy(alpha = 0.6f))
        }
        PictureButton(Icons.Download, "下载标注后的图片", enabled = !marks.busy && marks.any, onClick = onDownload)
        if (canDraft) Row(
            Modifier.padding(start = 4.dp).height(30.dp).clip(RoundedCornerShape(15.dp)).background(INK).alpha(if (!marks.busy && marks.any) 1f else 0.4f)
                .clickable(enabled = !marks.busy && marks.any, onClick = onDraft).padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            IconIn(Icons.Send, 12.dp, Color.White)
            Text(if (marks.busy) "正在生成…" else "放进对话", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        }
    }
}

/** The tools, at the bottom over the image, frosted as the top bar; the colours in a row above them. */
@Composable
fun MarksTools(marks: ImageMarks, glass: Modifier) {
    androidx.compose.foundation.layout.Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (marks.palette) Row(glass.then(Modifier.clip(CircleShape)).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            COLORS.forEach { (c, _) ->
                Box(
                    Modifier.size(32.dp).clip(CircleShape).background(if (c == marks.shownColor) Color.White.copy(alpha = 0.16f) else Color.Transparent).clickable { marks.pickColor(c) },
                    contentAlignment = Alignment.Center,
                ) { Swatch(c) }
            }
        }
        Row(glass.then(Modifier.height(44.dp)).padding(horizontal = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            listOf(MarkTool.Select to Icons.Cursor, MarkTool.Rect to Icons.Square, MarkTool.Arrow to Icons.ArrowUpRight, MarkTool.Pen to Icons.Scribble, MarkTool.Text to Icons.Text).forEach { (t, icon) ->
                PictureButton(icon, t.label, pressed = marks.tool == t) { marks.pickTool(t) }
            }
            Gap()
            Box(Modifier.size(32.dp).clip(RoundedCornerShape(12.dp)).clickable { marks.palette = !marks.palette }.semantics { contentDescription = "颜色" }, contentAlignment = Alignment.Center) { Swatch(marks.shownColor) }
            marks.pickedShape?.let { s -> PictureButton(Icons.Trash, "删除") { marks.remove(s.id) } }
            Gap()
            PictureButton(Icons.Retry, "撤销", enabled = marks.canUndo) { marks.undo() }
            PictureButton(Icons.Redo, "重做", enabled = marks.canRedo) { marks.redo() }
        }
    }
}

@Composable
private fun Swatch(c: Color) {
    Box(Modifier.size(16.dp).clip(CircleShape).background(c).background(Color.Transparent)) {
        androidx.compose.foundation.Canvas(Modifier.size(16.dp)) { drawCircle(Color.White.copy(alpha = 0.5f), radius = size.minDimension / 2 - 0.75.dp.toPx(), style = androidx.compose.ui.graphics.drawscope.Stroke(1.5.dp.toPx())) }
    }
}

@Composable
private fun Gap() = Box(Modifier.padding(horizontal = 4.dp).width(1.dp).height(18.dp).background(Color.White.copy(alpha = 0.1f)))

/** A 32dp icon button (named `label`) on a picture's bars (web's iconBtn in the dark viewer). */
@Composable
fun PictureButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean = true, pressed: Boolean = false, tint: Color = Color.White.copy(alpha = 0.6f), onClick: () -> Unit) {
    Box(
        Modifier.size(32.dp).clip(RoundedCornerShape(12.dp)).background(if (pressed) Color.White.copy(alpha = 0.16f) else Color.Transparent)
            .alpha(if (enabled) 1f else 0.35f).clickable(enabled = enabled, onClick = onClick).semantics { contentDescription = label },
        contentAlignment = Alignment.Center,
    ) { IconIn(icon, 18.dp, if (pressed) Color(0xFFF4F4F5) else tint) }
}
