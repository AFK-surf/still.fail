// Links to a station's screens in an agent's words (docs/remote-screens.md), as the web draws them: one alone in a
// paragraph is the screen's card, as a file's is (ChatFiles.kt FileCard); a bare one within a sentence reads as the
// screen's title. What the card says is the core's (`screenCard`, client/core-ts/src/screens.ts).
package fail.still.android.screens

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
import fail.still.android.ui.screenOfLink

/** The links to screens in a message's words (Markdown.kt): their cards, and a bare one's title (屏幕 until it is known). */
internal val ScreenLinks = Screens(
    card = { href, words -> ScreenLinkCard(href, words) },
    title = { href -> screenCardOf(href)?.title ?: t("android-misc.screen.title") },
)

@Composable
private fun screenCardOf(href: String): ScreenCard? {
    val (station, screen) = screenOfLink(href) ?: return null
    val card by rememberTopic<ScreenCard>(LocalApp.current.core, Topics.screenCard(station, screen))
    return card.value
}

/**
 * A screen as a card: its kind's mark, its title (the link's own words, when it has them) over what its station says
 * of it; one its station no longer has, its title quieter. Its size is kept while the core has not said, its lines empty. A tap
 * opens it, as the link does (App.kt → AppState.openLink: the viewer).
 */
@Composable
private fun ScreenLinkCard(href: String, words: String?) {
    val card = screenCardOf(href)
    val uris = LocalUriHandler.current
    val gone = card?.gone == true
    Row(
        Modifier.width(236.dp).clip(Smooth(8.dp)).background(chatInk().neutral).clickable { uris.openUri(href) }.padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val mark = when (card?.kind) { null -> null; "browser" -> Globe; else -> Monitor }
        if (mark != null) Icon(mark, null, Modifier.size(30.dp, 36.dp), tint = C.muted)
        else Box(Modifier.size(30.dp, 36.dp))
        Column(Modifier.weight(1f)) {
            Text(words ?: card?.title.orEmpty(), fontSize = 15.sp, lineHeight = 20.sp, color = if (gone) C.muted else C.ink, maxLines = 1, minLines = 1, overflow = TextOverflow.Ellipsis)
            Text(card?.line.orEmpty(), fontSize = 11.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, minLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A screen's mark, 30 by 36 as the web's: drawn in strokes, 1.5 wide, tinted. */
private fun tile(name: String, vararg paths: String) = ImageVector.Builder(name, 30.dp, 36.dp, 30f, 36f).apply {
    for (d in paths) addPath(addPathNodes(d), fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = 1.5f, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round)
}.build()

private val Monitor = tile("screen-desktop", "M6.25 8H23.75A2.5 2.5 0 0 1 26.25 10.5V21A2.5 2.5 0 0 1 23.75 23.5H6.25A2.5 2.5 0 0 1 3.75 21V10.5A2.5 2.5 0 0 1 6.25 8Z", "M15 23.5V28.5M10.5 28.5H19.5")
private val Globe = tile(
    "screen-browser", "M3.75 18A11.25 11.25 0 1 0 26.25 18A11.25 11.25 0 1 0 3.75 18Z",
    "M3.75 18H26.25M15 6.75C11.75 10 10.25 14 10.25 18S11.75 26 15 29.25M15 6.75C18.25 10 19.75 14 19.75 18S18.25 26 15 29.25",
)
