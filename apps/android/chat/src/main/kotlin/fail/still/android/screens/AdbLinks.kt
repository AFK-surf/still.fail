// A link to a station's 共享调试 in an agent's words (docs/adb-share.md; an agent asking for a person's phone), as the
// web draws it (web/src/AdbLink.tsx): alone in a paragraph, a card as a screen's is (ScreenLinks.kt), a phone for its
// mark over how this phone's sharing with that station stands; a bare one within a sentence reads as 共享调试. What
// the card says is the core's (`adbCard`, client/core-ts/src/adb.ts).
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.data.AdbCard
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.t
import fail.still.android.ui.C
import fail.still.android.ui.Smooth
import fail.still.android.ui.adbOfLink
import fail.still.android.ui.chatInk

@Composable
private fun adbCardOf(href: String): AdbCard? {
    val station = adbOfLink(href) ?: return null
    val card by rememberTopic<AdbCard>(LocalApp.current.core, Topics.adbCard(station))
    return card.value
}

/** A bare link to a station's 共享调试: what it reads as within a sentence. */
@Composable
internal fun adbTitle(href: String): String = adbCardOf(href)?.title ?: t("android-misc.adb.title")

/**
 * A station's 共享调试 as a card: a phone, its title (the link's own words, when it has them) over how this phone's
 * sharing with that station stands, in the accent while it is shared there. Its size kept while the core has not
 * said. A tap opens the page, as the link does (AppState.openLink).
 */
@Composable
internal fun AdbLinkCard(href: String, words: String?) {
    val card = adbCardOf(href)
    val uris = LocalUriHandler.current
    Row(
        Modifier.width(236.dp).clip(Smooth(8.dp)).background(chatInk().neutral).clickable { uris.openUri(href) }.padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Phone, null, Modifier.size(30.dp, 36.dp), tint = if (card?.sharing == true) C.accent else C.muted)
        Column(Modifier.weight(1f)) {
            Text(words ?: card?.title ?: t("android-misc.adb.title"), fontSize = 15.sp, lineHeight = 20.sp, color = C.ink, maxLines = 1, minLines = 1, overflow = TextOverflow.Ellipsis)
            Text(card?.line.orEmpty(), fontSize = 11.sp, lineHeight = 16.sp, color = C.muted, maxLines = 1, minLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

/** A phone, 30 by 36 as the web's mark. */
private val Phone = tile("adb-phone", "M11 5.25H19A2.75 2.75 0 0 1 21.75 8V28A2.75 2.75 0 0 1 19 30.75H11A2.75 2.75 0 0 1 8.25 28V8A2.75 2.75 0 0 1 11 5.25Z", "M13 27H17")
