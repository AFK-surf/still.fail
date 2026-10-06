// The search at the top of the home lists (web mobile/Home.tsx SearchField, SearchPage): a field there once a list is
// scrolled to its top; tapped, the list goes up and away with the bars, the field comes up from where it was to the
// top (narrowing as 取消 comes in beside it), and under it the chats the words find (the core's `chatSearch`, as ⌘K's on the wide screen), then the messages
// that have them, newest first, each opening its chat at it. 取消 (or back) puts the field back in the list.
package fail.still.android.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatSearchView
import fail.still.android.data.FoundMessage
import fail.still.android.data.Topics
import fail.still.android.data.page
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Ease
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.reducedMotion
import fail.still.android.data.t
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

/** How many of the messages that have the words the search lists, under the chats. */
private const val FOUND_MESSAGES = 50

/** The field's height, and the room over it in the search's bar (as the home bar's: 8dp under the status bar). */
private val FIELD = 38.dp
private val BAR_TOP = 8.dp

/** At a list's top: tapped, the search opens from it (`onOpen`, with its top in the root and its width, px). `hidden`
 *  while the search's field is it (one field at a time, flying from and back to here). */
@Composable
internal fun SearchField(onOpen: (Float, Float) -> Unit, hidden: Boolean) {
    var at by remember { mutableStateOf(Rect.Zero) }
    Row(
        Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, bottom = 6.dp).height(FIELD).onGloballyPositioned { at = it.boundsInRoot() }
            .graphicsLayer { alpha = if (hidden) 0f else 1f }.clip(RoundedCornerShape(FIELD / 2)).background(C.ink.copy(alpha = 0.06f)).clickable { onOpen(at.top, at.width) }.padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        IconIn(Icons.Search, 17.dp, C.muted)
        Text(t("android-chat.search.field"), fontSize = 15.sp, color = C.muted, maxLines = 1)
    }
}

/**
 * The search over the home lists, its field come up from `from` (its top in the list, px) to the bar, from `wide` (its
 * width there, px) to the room 取消 leaves it; `onLeave` as it starts going back, `onClose` once it is back there. The words typed stay while a chat opened from it is read.
 */
@Composable
internal fun SearchPage(scope: String, from: Float, wide: Float, onLeave: () -> Unit = {}, onClose: () -> Unit) {
    val app = LocalApp.current
    val density = LocalDensity.current
    var query by rememberSaveable { mutableStateOf("") }
    val search by rememberTopic<ChatSearchView>(app.core, Topics.chatSearch(scope, query, messages = FOUND_MESSAGES))
    // While the next words are looked up, what the last ones found stays.
    val kept = remember { arrayOfNulls<ChatSearchView>(1) }
    search.value?.let { kept[0] = it }
    val view = search.value ?: kept[0]
    val words = query.isNotBlank()
    val chats = if (words) view?.items.orEmpty() else emptyList()
    val messages = if (words) view?.messages.orEmpty() else emptyList()
    // Where the field is laid out (under the status bar, as the home bar's top), so its move is known before it is drawn.
    val to = WindowInsets.statusBars.getTop(density) + with(density) { BAR_TOP.toPx() }
    val still = reducedMotion()
    val up = remember { Animatable(if (still) 1f else 0f) }
    var leaving by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    val keyboard = LocalSoftwareKeyboardController.current
    val coroutines = rememberCoroutineScope()
    LaunchedEffect(Unit) {
        focus.requestFocus()
        up.animateTo(1f, tween(280, easing = Ease.Arrive))
    }
    val close = {
        if (!leaving) {
            leaving = true
            keyboard?.hide()
            onLeave()
            coroutines.launch {
                if (!still) up.animateTo(0f, tween(240, easing = Ease.Standard))
                onClose()
            }
        }
    }
    BackHandler(enabled = !leaving) { close() }
    // Over the lists (faded away, still there): nothing under it is touched through it.
    Column(Modifier.fillMaxSize().clickable(interactionSource = null, indication = null) {}.imePadding()) {
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.statusBars).padding(start = 16.dp, end = 16.dp, top = BAR_TOP, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            // As wide as the list's while there, narrowing to its room as it comes up (and back as it goes): 取消 comes in
            // with its right edge, not the field jumping between the two widths.
            Row(
                Modifier.weight(1f).layout { measurable, constraints ->
                    val room = constraints.maxWidth
                    val now = if (wide > 0f) (wide + (room - wide) * up.value).roundToInt().coerceAtLeast(0) else room
                    val placeable = measurable.measure(constraints.copy(minWidth = now, maxWidth = now))
                    layout(room, placeable.height) { placeable.place(0, 0) }
                }.height(FIELD).graphicsLayer { translationY = (from - to) * (1f - up.value) }
                    .clip(RoundedCornerShape(FIELD / 2)).background(C.ink.copy(alpha = 0.06f)).padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                IconIn(Icons.Search, 17.dp, C.muted)
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    if (query.isEmpty()) Text(t("android-chat.search.field"), fontSize = 16.sp, color = C.muted, maxLines = 1)
                    BasicTextField(
                        query, { query = it }, singleLine = true, cursorBrush = SolidColor(C.accent),
                        textStyle = TextStyle(fontSize = 16.sp, color = C.ink),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                        modifier = Modifier.fillMaxWidth().focusRequester(focus).semantics { contentDescription = t("android-chat.search.field") },
                    )
                }
            }
            Text(
                t("android-chat.search.cancel"), fontSize = 16.sp, color = C.accent,
                modifier = Modifier.graphicsLayer { alpha = up.value; translationX = (size.width + 12.dp.toPx()) * (1f - up.value) }.clickable(enabled = !leaving) { close() },
            )
        }
        LazyColumn(Modifier.fillMaxWidth().weight(1f).graphicsLayer { alpha = up.value }) {
            if (words && view == null && search.error != null) item(key = "update") { SearchNote(t("android-chat.search.update")) }
            if (words && view != null && chats.isEmpty() && messages.isEmpty()) item(key = "none") { SearchNote(t("android-chat.search.none")) }
            if (chats.isNotEmpty()) {
                item(key = "chats") { SectionHeader(t("android-chat.search.chats")) }
                items(chats, key = { "c/${it.station}/${it.id}" }) { item ->
                    ChatRowBody(item, "agents", held = false, modifier = Modifier.clickable { app.push(Screen.Chat(item.station, item.page)) })
                }
            }
            if (messages.isNotEmpty()) {
                item(key = "messages") { SectionHeader(t("android-chat.search.messages")) }
                items(messages, key = { "m/${it.station}/${it.thread}/${it.seq}" }) { FoundRow(it, view?.words) }
            }
        }
    }
}

@Composable
private fun SearchNote(text: String) {
    Text(text, fontSize = 14.sp, color = C.muted, modifier = Modifier.fillMaxWidth().padding(horizontal = 22.dp, vertical = 16.dp))
}

/** A message the words found: its chat, who said it and when, over the line that has them (in ink, bold); tapped, its
 *  chat opens at it, the words marked there. */
@Composable
private fun FoundRow(found: FoundMessage, words: List<String>?) {
    val app = LocalApp.current
    val ink = C.ink
    val line = remember(found.text, found.marks, ink) {
        buildAnnotatedString {
            var at = 0
            for (m in found.marks) {
                val from = m.from.toInt()
                val to = m.to.toInt()
                if (from < at || to > found.text.length) continue
                append(found.text.substring(at, from))
                withStyle(SpanStyle(color = ink, fontWeight = FontWeight.SemiBold)) { append(found.text.substring(from, to)) }
                at = to
            }
            append(found.text.substring(at))
        }
    }
    Column(
        Modifier.fillMaxWidth().height(66.dp).clickable { app.push(Screen.Chat(found.station, found.chat.page, at = found.seq, words = words)) }
            .padding(start = 22.dp, end = 16.dp),
        verticalArrangement = Arrangement.Center,
    ) {
        Row(Modifier.height(22.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(found.chat.title, fontSize = 15.sp, lineHeight = 22.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            val meta = listOfNotNull(found.by.takeIf { it.isNotEmpty() }, found.time?.get("createdAt")?.ago).joinToString(" · ")
            Text(meta, fontSize = 12.sp, color = C.muted, maxLines = 1)
        }
        Text(line, fontSize = 14.sp, lineHeight = 20.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.height(20.dp))
    }
}
