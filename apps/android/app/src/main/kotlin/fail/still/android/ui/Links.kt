// Web addresses in what people and agents write: found where they are written bare, as the web finds them
// (web/src/bareLinks.ts), and held for a menu of their own (open, copy) rather than the message's.
package fail.still.android.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import fail.still.android.data.t

/**
 * A bare address: http(s):// and the characters addresses are made of, ending at a space or at a letter outside ASCII
 * (Chinese words, full-width marks such as `）` `，` `。`); the marks closing a sentence after it (`.` `,` `:` …) and a
 * closing bracket it did not open are not its. GFM's own finding ends only at a space: `（https://…/2854）已改到` was
 * one link, its words with it.
 */
private val ADDRESS = Regex("(?<![A-Za-z0-9])https?://[A-Za-z0-9\\-._~:/?#\\[\\]@!$&'()*+,;=%]+", RegexOption.IGNORE_CASE)
private val HOST = Regex("^https?://[A-Za-z0-9]", RegexOption.IGNORE_CASE)

/** Where the bare addresses in `text` are. */
fun bareLinks(text: String): List<IntRange> = ADDRESS.findAll(text).mapNotNull { m ->
    val url = trimmed(m.value)
    // A host, not the scheme alone; one cut short (`https://github.com/…`) is no address to open.
    if (!HOST.containsMatchIn(url) || text.getOrNull(m.range.last + 1) == '…') null else m.range.first until m.range.first + url.length
}.toList()

/** An address without what closes the sentence or the bracket it is written in. */
private fun trimmed(address: String): String {
    var url = address
    while (true) {
        val last = url.last()
        url = when {
            last in ".,:;!?'*_~" -> url.dropLast(1)
            last == ')' && url.count { it == '(' } < url.count { it == ')' } -> url.dropLast(1)
            last == ']' && url.count { it == '[' } < url.count { it == ']' } -> url.dropLast(1)
            else -> return url
        }
    }
}

/** `text`, its bare addresses as links drawn in `style`. */
fun AnnotatedString.Builder.appendLinked(text: String, style: TextLinkStyles) {
    var at = 0
    for (r in bareLinks(text)) {
        append(text, at, r.first)
        withLink(LinkAnnotation.Url(text.substring(r), style)) { append(text, r.first, r.last + 1) }
        at = r.last + 1
    }
    append(text, at, text.length)
}

private val WEB_ADDRESS = Regex("^https?://(?:localhost|[\\w-]+(?:\\.[\\w-]+)+)(?::\\d+)?(?:[/?#]\\S*)?$", RegexOption.IGNORE_CASE)

/** A web address alone in inline code, which is a link too (as the web's Prose.tsx has it). */
fun isWebAddress(code: String): Boolean = '…' !in code && WEB_ADDRESS.matches(code.trim())

/**
 * The words with their links drawn as links but none to tap: where a finger picks words from them (the annotate page,
 * Pick.kt; the web's links there take no touches either).
 */
fun AnnotatedString.inert(): AnnotatedString {
    val links = getLinkAnnotations(0, length)
    if (links.isEmpty()) return this
    return buildAnnotatedString {
        append(AnnotatedString(text, spanStyles, paragraphStyles))
        for (a in getStringAnnotations(0, length)) addStringAnnotation(a.tag, a.item, a.start, a.end)
        for (l in links) l.item.styles?.style?.let { addStyle(it, l.start, l.end) }
    }
}

/**
 * The hook for words with links in them: a long press on one is its menu (open it, copy it), as the app's other long-
 * press menus are (Sheet.kt MenuHost), not the message's own (its page) and not the link opening as the finger lifts;
 * a tap stays the link's. A modifier to put on the text (inside its padding) and what to give its onTextLayout.
 * Nothing where words are picked from (the annotate page: a hold there picks words).
 */
@Composable
fun linkHold(text: AnnotatedString): Pair<Modifier, (TextLayoutResult) -> Unit> {
    val links = remember(text) { text.getLinkAnnotations(0, text.length).filter { it.item is LinkAnnotation.Url } }
    if (links.isEmpty() || LocalPickedWords.current != null) return Modifier to {}
    val ui = LocalUi.current
    val uris = LocalUriHandler.current
    val haptics = LocalHapticFeedback.current
    val context = LocalContext.current
    val laid = remember { arrayOfNulls<TextLayoutResult>(1) }
    val place = remember { arrayOfNulls<LayoutCoordinates>(1) }
    val modifier = Modifier.onGloballyPositioned { place[0] = it }.pointerInput(links) {
        awaitEachGesture {
            // Read before the link's own tap (inside the text), so as to call it off once the press is a hold.
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            val layout = laid[0] ?: return@awaitEachGesture
            val link = links.firstOrNull { l -> lineRects(layout, l.start, l.end).any { it.contains(down.position) } } ?: return@awaitEachGesture
            // Let go, moved or taken by something else before a long press's time: a tap or a scroll, not this.
            val ended = withTimeoutOrNull(viewConfiguration.longPressTimeoutMillis) {
                while (true) {
                    val c = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id }
                    if (c == null || !c.pressed || c.isConsumed || (c.position - down.position).getDistance() > viewConfiguration.touchSlop) break
                }
                true
            }
            if (ended != null) return@awaitEachGesture
            val url = (link.item as LinkAnnotation.Url).url
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            place[0]?.takeIf { it.isAttached }?.let { at ->
                // Under the line held (over it when there is no room below), centred on the finger: the menu is 180 wide.
                val line = layout.getLineForVerticalPosition(down.position.y)
                val x = at.localToRoot(down.position).x - 90.dp.toPx()
                val top = at.localToRoot(Offset(0f, layout.getLineTop(line))).y
                val bottom = at.localToRoot(Offset(0f, layout.getLineBottom(line))).y
                ui.menu = MenuSpec(Rect(x, top, x, bottom), listOf(
                    // As a tap on it: still.fail's own open in the app, any other in the browser (App.kt's UriHandler).
                    MenuItem(t("common.link.open"), Icons.External) { uris.openUri(url) },
                    MenuItem(t("common.link.copy"), Icons.Copy) {
                        (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", url))
                        ui.note(t("common.link.copied"))
                    },
                ))
            }
            // The finger lifts over the menu: no tap on the link (it would open it), nor on anything under it.
            while (true) {
                val event = awaitPointerEvent(PointerEventPass.Initial)
                event.changes.forEach { it.consume() }
                if (event.changes.none { it.pressed }) break
            }
        }
    }
    return modifier to { laid[0] = it }
}
