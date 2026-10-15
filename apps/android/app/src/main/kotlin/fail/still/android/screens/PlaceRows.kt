// The rows of a place's list (PlacePage.kt), as the desktop sidebar's (web SidebarList.tsx NavItem) and laid out as a
// chat's: a mark in a column of its own, the title and what is at that line's end, the lines under them starting where
// the title does; flat, under the chats' section headings. Only what is off is in colour.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.MenuItem
import fail.still.android.ui.MenuSpec

/** What the page is and what it is for, said where its list is empty (the page has no note at its top). */
@Composable
fun PlaceEmpty(text: String, note: String? = null) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 32.dp, vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(text, fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
        if (note != null) Text(note, fontSize = 13.sp, color = C.subtle, textAlign = TextAlign.Center)
    }
}

/**
 * A row of a place's list, as the desktop sidebar's (web SidebarList.tsx NavItem) and laid out as a chat's: its `mark`
 * in a column of its own, its title and what is at that line's `end`, then `lines` under them from where the title
 * starts. `away`: what it is is not there now (its title faint). Pressed, the chats' pressed ground.
 */
@Composable
fun PlaceRow(
    title: String,
    mark: @Composable () -> Unit,
    onClick: (() -> Unit)?,
    away: Boolean = false,
    end: (@Composable RowScope.() -> Unit)? = null,
    lines: @Composable ColumnScope.() -> Unit = {},
) {
    val press = remember { MutableInteractionSource() }
    val pressed by press.collectIsPressedAsState()
    Column(
        Modifier.fillMaxWidth().background(if (pressed) C.ink.copy(alpha = 0.05f) else Color.Transparent)
            .then(if (onClick != null) Modifier.clickable(press, indication = null, onClick = onClick) else Modifier)
            .padding(start = 22.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
    ) {
        Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.width(MARK), contentAlignment = Alignment.Center) { mark() }
            Spacer(Modifier.width(GAP))
            Text(title, fontSize = 16.sp, lineHeight = 22.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).alpha(if (away) 0.5f else 1f))
            if (end != null) Row(Modifier.padding(start = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) { end() }
        }
        Column(Modifier.padding(start = MARK + GAP)) { lines() }
    }
}

private val MARK = 16.dp
private val GAP = 8.dp

/** A line under a row's title: muted, one line; `color` only for what is off. */
@Composable
fun PlaceLine(text: String, color: Color = C.muted) {
    Text(text, fontSize = 14.sp, lineHeight = 20.sp, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

/** What is at the end of a row's first line: small and muted; `color` only for what is off. */
@Composable
fun PlaceEnd(text: String, color: Color = C.muted) {
    Text(text, fontSize = 13.sp, lineHeight = 18.sp, color = color, maxLines = 1)
}

/** A station's dot at a row's end: green while up, grey while away. */
@Composable
fun OnlineDot(online: Boolean) {
    Box(Modifier.size(7.dp).clip(CircleShape).background(if (online) C.green else C.subtle))
}

/**
 * A filter in a place's top bar, as the chats' (Home.kt): its menu under it, the chosen one ticked; the accent on the
 * icon while it narrows the list (anything but the first).
 */
@Composable
fun BandFilter(label: String, options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val app = LocalApp.current
    val density = LocalDensity.current
    var at by remember { mutableStateOf(Rect.Zero) }
    Box(
        Modifier.size(34.dp).onGloballyPositioned { at = it.boundsInRoot() }.clip(CircleShape).clickable {
            // The menu is 180 wide (Sheet.kt MenuHost): its right edge under the button's.
            val left = at.right - with(density) { 180.dp.toPx() }
            app.menu = MenuSpec(Rect(left, at.top, left, at.bottom), options.mapIndexed { i, o -> MenuItem(o, if (i == selected) Icons.Check else null) { onSelect(i) } })
        }.semantics { contentDescription = "$label: ${options.getOrNull(selected).orEmpty()}" },
        contentAlignment = Alignment.Center,
    ) { IconIn(Icons.Filter, 20.dp, if (selected != 0) C.accent else C.ink) }
}
