// Links to a station's screens in an agent's words (docs/remote-screens.md), as the web draws them: one alone in a
// paragraph is the screen's card, as a file's is (ChatFiles.kt FileCard); a bare one within a sentence reads as the
// screen's title. What the card says is the core's (`screenCard`, client/core-ts/src/screens.ts); a screen its station
// previews is live in its card while the card is on the screen (`screen.view` with `peek`, as remote/ScreenSession.kt
// views one: JPEG only, small, slow).
package fail.still.android.screens

import android.graphics.BitmapFactory
import android.os.SystemClock
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import fail.still.core.CoreException
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.ScreenCard
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.Screens
import fail.still.android.ui.Smooth
import fail.still.android.ui.chatInk
import fail.still.android.ui.adbOfLink
import fail.still.android.ui.screenOfLink

/**
 * The links to screens in a message's words (Markdown.kt): their cards, and a bare one's title (屏幕 until it is known);
 * a station's 共享调试 as its own (AdbLinks.kt).
 */
internal val ScreenLinks = Screens(
    card = { href, words -> if (adbOfLink(href) != null) AdbLinkCard(href, words) else ScreenLinkCard(href, words) },
    title = { href -> if (adbOfLink(href) != null) adbTitle(href) else screenCardOf(href)?.title ?: t("android-misc.screen.title") },
)

@Composable
private fun screenCardOf(href: String): ScreenCard? {
    val (station, screen) = screenOfLink(href) ?: return null
    val card by rememberTopic<ScreenCard>(LocalApp.current.core, Topics.screenCard(station, screen))
    return card.value
}

/**
 * A screen as a card: its kind's mark, its title (the link's own words, when it has them) over what its station says
 * of it; one its station no longer has, its title quieter. Its size is kept while the core has not said, its lines
 * empty. One its station previews (a tab of its browser) is the screen live across the card's top, the words under it.
 * A tap opens it, as the link does (App.kt → AppState.openLink: the viewer).
 */
@Composable
private fun ScreenLinkCard(href: String, words: String?) {
    val card = screenCardOf(href)
    val uris = LocalUriHandler.current
    val gone = card?.gone == true
    val of = screenOfLink(href)
    val lines: @Composable (Modifier) -> Unit = { m ->
        Column(m) {
            Text(words ?: card?.title.orEmpty(), fontSize = 15.sp, lineHeight = 20.sp, color = if (gone) C.muted else C.ink, maxLines = 1, minLines = 1, overflow = TextOverflow.Ellipsis)
            Text(card?.line.orEmpty(), fontSize = 11.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, minLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    val box = Modifier.clip(Smooth(8.dp)).background(chatInk().neutral).clickable { uris.openUri(href) }
    if (card != null && card.peek && !gone && of != null) {
        Column(box.width(280.dp)) {
            Peek(of.first, of.second, card)
            lines(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 8.dp))
        }
        return
    }
    Row(
        box.width(236.dp).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val mark = when (card?.kind) { null -> null; "browser" -> Globe; else -> Monitor }
        if (mark != null) Icon(mark, null, Modifier.size(30.dp, 36.dp), tint = C.muted)
        else Box(Modifier.size(30.dp, 36.dp))
        lines(Modifier.weight(1f))
    }
}

/** A preview's pace: a picture at most this often (the station sends the next once the last is acknowledged). */
private const val PEEK_MS = 500L
/** The picture a preview asks for, in pixels at most: the card's width, twice over. */
private const val PEEK_SIZE = 640

/** The web's --hover, the ground a preview's picture comes onto. */
private val peekGround @Composable get() = if (C.dark) Color.White.copy(alpha = 0.05f) else Color(0xFF322D24).copy(alpha = 0.065f)

/**
 * The screen live in its card (`screen.view` with `peek`: only looking, not among those on it, its tab not brought
 * forward), a picture every PEEK_MS while the card is on the screen and the app in front; its mark until a picture
 * comes (a tab behind another casts none). In its shape as its station lists it, within bounds: the card does not
 * change size as it comes.
 */
@Composable
private fun Peek(station: String, screen: String, card: ScreenCard) {
    val core = LocalApp.current.core
    val started = LocalLifecycleOwner.current.lifecycle.currentStateAsState().value.isAtLeast(Lifecycle.State.STARTED)
    var inView by remember { mutableStateOf(false) }
    var picture by remember(station, screen) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(station, screen, inView && started) {
        if (!inView || !started) return@LaunchedEffect
        val view = "android-peek-" + UUID.randomUUID().toString().take(8)
        val params = buildJsonObject {
            put("station", station); put("screen", screen); put("view", view)
            put("codecs", JsonArray(listOf(JsonPrimitive("jpeg"))))
            put("maxWidth", PEEK_SIZE); put("maxHeight", PEEK_SIZE); put("peek", true)
        }
        // Frames as they come (on the core's thread), decoded and acknowledged off the main thread.
        val frames = Channel<Pair<ByteArray?, Long>>(Channel.UNLIMITED)
        coroutineScope {
            launch(Dispatchers.Default) {
                // Each acknowledgement PEEK_MS after the one before: the station sends no faster.
                var at = 0L
                for ((bytes, ts) in frames) {
                    bytes?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }?.asImageBitmap()?.let { b -> withContext(Dispatchers.Main) { picture = b } }
                    at = maxOf(SystemClock.uptimeMillis(), at + PEEK_MS)
                    val wait = at - SystemClock.uptimeMillis()
                    launch { delay(wait); core.tell("screen.ack", buildJsonObject { put("view", view); put("ts", ts) }) }
                }
            }
            try {
                core.stream("screen.view", params) { value, bytes ->
                    val f = (value as? JsonObject)?.get("frame") as? JsonObject ?: return@stream
                    val ts = (f["ts"] as? JsonPrimitive)?.let { it.longOrNull ?: it.contentOrNull?.toDoubleOrNull()?.toLong() } ?: return@stream
                    frames.trySend(bytes to ts)
                }
            } catch (_: CoreException) {
                // Refused or ended (the station no longer previews it): its mark stays.
            }
            frames.close()
        }
    }
    val ratio = if (card.width > 0u && card.height > 0u) (card.width.toFloat() / card.height.toFloat()).coerceIn(0.75f, 2f) else 16f / 10f
    Box(
        Modifier.fillMaxWidth().aspectRatio(ratio).background(peekGround).onGloballyPositioned { inView = it.isAttached && !it.boundsInWindow().isEmpty },
        contentAlignment = Alignment.Center,
    ) {
        val shown = picture
        if (shown != null) Image(shown, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop, alignment = Alignment.TopCenter)
        else Icon(if (card.kind == "browser") Globe else Monitor, null, Modifier.size(30.dp, 36.dp), tint = C.muted)
    }
}

/** A screen's mark, 30 by 36 as the web's: drawn in strokes, 1.5 wide, tinted. */
internal fun tile(name: String, vararg paths: String) = ImageVector.Builder(name, 30.dp, 36.dp, 30f, 36f).apply {
    for (d in paths) addPath(addPathNodes(d), fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = 1.5f, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round)
}.build()

private val Monitor = tile("screen-desktop", "M6.25 8H23.75A2.5 2.5 0 0 1 26.25 10.5V21A2.5 2.5 0 0 1 23.75 23.5H6.25A2.5 2.5 0 0 1 3.75 21V10.5A2.5 2.5 0 0 1 6.25 8Z", "M15 23.5V28.5M10.5 28.5H19.5")
private val Globe = tile(
    "screen-browser", "M3.75 18A11.25 11.25 0 1 0 26.25 18A11.25 11.25 0 1 0 3.75 18Z",
    "M3.75 18H26.25M15 6.75C11.75 10 10.25 14 10.25 18S11.75 26 15 29.25M15 6.75C18.25 10 19.75 14 19.75 18S18.25 26 15 29.25",
)
