// What changed in still.fail, as the narrow web has it (web/src/mobile/Changelog.tsx), from the core's `changelog` topic
// (client/core-ts/src/changelog.ts): the settings' 更新日志 page, a tab a part (this app's first), by day on cards, each
// change with where it is and whether this app has it; and at the top of the list, what the last update brought, until
// the page is opened or it is put away (`changelog.seen`).
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.text.InlineTextContent
import androidx.compose.foundation.text.appendInlineContent
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.Placeholder
import androidx.compose.ui.text.PlaceholderVerticalAlign
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChangelogItem
import fail.still.android.data.ChangelogLine
import fail.still.android.data.ChangelogView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.Seg
import fail.still.android.data.t
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject

/** Says the changelog was seen up to this build: what it brought is not news any more. */
private suspend fun seen(app: AppState) {
    try { app.core.call("changelog.seen", buildJsonObject {}) } catch (_: CoreException) {}
}

@Composable
fun ChangelogScreen() {
    val app = LocalApp.current
    val topic by rememberTopic<ChangelogView>(app.core, Topics.changelog)
    val view = topic.value
    // Opened: what the update brought is read.
    val news = view?.news != null
    LaunchedEffect(news) { if (news) seen(app) }
    var part by remember { mutableStateOf<String?>(null) }
    val tabs = view?.tabs.orEmpty()
    val at = tabs.indexOfFirst { it.part == part }.coerceAtLeast(0)
    val tab = tabs.getOrNull(at)
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-settings.title"), app::pop)
        LargeTitle(view?.build?.let { t("android-settings.changelog.build", "build" to it) } ?: "", t("android-settings.changelog.title"))
        if (tab != null) Seg(tabs.map { it.label }, at, { part = tabs[it].part }, Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 2.dp).fillMaxWidth(), height = 34.dp, fill = true)
        when {
            view == null || view.loading == true -> Row(Modifier.padding(horizontal = 24.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Spinner(13.dp)
                Text(t("android-settings.reading"), fontSize = 14.sp, color = C.muted)
            }
            view.error != null -> Text(view.error, fontSize = 14.sp, color = C.red, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            tab == null || tab.days.isEmpty() -> Text(t("android-settings.changelog.empty"), fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            else -> tab.days.forEach { day ->
                SectionHeader(day.label, start = 24.dp)
                ListCard { day.entries.forEach { Change(it) } }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** One change: each line led by its kind on a small tinted label (the accent's for something new), then its version and
 *  what is not out yet (in the accent: an update would bring it). */
@Composable
private fun Change(item: ChangelogItem) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        item.lines.forEach { Line(it) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(item.versionName, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted)
            if (item.note.isNotEmpty()) Text(item.note, fontSize = 13.sp, lineHeight = 18.sp, color = if (item.has == false) C.accentInk else C.muted)
        }
    }
}

/** A line, its kind's label inline before it so the text wraps under it. */
@Composable
private fun Line(line: ChangelogLine) {
    if (line.label.isEmpty()) {
        Text(line.text, fontSize = 15.sp, lineHeight = 21.sp, color = C.ink)
        return
    }
    val labelStyle = TextStyle(fontSize = 13.sp, lineHeight = 19.sp)
    val measurer = rememberTextMeasurer()
    val width = with(LocalDensity.current) { (measurer.measure(line.label, labelStyle).size.width.toDp() + 12.dp + 6.dp).toSp() }
    val new = line.kind == "new"
    val text = buildAnnotatedString {
        appendInlineContent("kind", line.label)
        append(line.text)
    }
    val kind = InlineTextContent(Placeholder(width, 19.sp, PlaceholderVerticalAlign.TextCenter)) {
        Box(Modifier.padding(end = 6.dp).fillMaxSize().clip(RoundedCornerShape(6.dp)).background(if (new) C.accentBg else C.chip), contentAlignment = Alignment.Center) {
            Text(line.label, style = labelStyle, color = if (new) C.accentInk else C.muted, maxLines = 1, softWrap = false)
        }
    }
    Text(text, fontSize = 15.sp, lineHeight = 21.sp, color = C.ink, inlineContent = mapOf("kind" to kind))
}

/** At the top of the list after an update: the build it is now and what it brought; opens the changelog. */
@Composable
fun ChangelogNews() {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val topic by rememberTopic<ChangelogView>(app.core, Topics.changelog)
    // Let go (知道了): gone at once, before the core has it.
    var gone by remember { mutableStateOf<Any?>(null) }
    val news = topic.value?.news ?: return
    if (gone == news) return
    val lines = news.entries.flatMap { it.text }
    Box(Modifier.padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
        Column(Modifier.fillMaxWidth().clickable { app.push(Screen.Changelog) }.padding(start = 16.dp, end = 44.dp, top = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(Modifier.padding(bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                IconIn(Icons.Sparks, 16.dp, C.ink)
                Text(news.build?.let { t("android-settings.changelog.updatedTo", "build" to it) } ?: t("android-settings.changelog.updated"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            }
            lines.take(3).forEach { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            if (lines.size > 3) Text(t("android-settings.changelog.more", "n" to lines.size - 3), fontSize = 13.sp, lineHeight = 18.sp, color = C.muted)
        }
        Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(32.dp).clip(CircleShape).clickable { gone = news; app.scope.launch { seen(app) } }.semantics { contentDescription = t("android-settings.changelog.dismiss") }, contentAlignment = Alignment.Center) {
            IconIn(Icons.Close, 16.dp, C.muted)
        }
    }
}
