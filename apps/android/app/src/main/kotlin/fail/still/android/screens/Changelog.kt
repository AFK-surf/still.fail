// What changed in still.fail, as the narrow web has it (web/src/mobile/Changelog.tsx), from the core's `changelog` topic
// (client/core/src/changelog.rs): the settings' 更新日志 page, by day on cards, each change with where it is and whether
// this app has it; and at the top of the list, what the last update brought, until the page is opened or it is put
// away (`changelog.seen`).
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
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChangelogItem
import fail.still.android.data.ChangelogView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.SectionHeader
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
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("设置", app::pop)
        LargeTitle(view?.build?.let { "这个 app 是 0.1.$it" } ?: "", "更新日志")
        when {
            view == null || view.loading == true -> Row(Modifier.padding(horizontal = 24.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Spinner(13.dp)
                Text("正在读取…", fontSize = 14.sp, color = C.muted)
            }
            view.error != null -> Text(view.error, fontSize = 14.sp, color = C.red, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            view.days.isEmpty() -> Text("还没有更新记录", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp, vertical = 8.dp))
            else -> view.days.forEach { day ->
                SectionHeader(day.label, start = 24.dp)
                ListCard { day.entries.forEach { Change(it) } }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** One change: its lines, then where it is and whether this app has it (in the accent: an update would bring it). */
@Composable
private fun Change(item: ChangelogItem) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        item.text.forEach { Text(it, fontSize = 15.sp, lineHeight = 21.sp, color = C.ink) }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            if (item.place.isNotEmpty()) Text(item.place, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted)
            Text(item.note, fontSize = 13.sp, lineHeight = 18.sp, color = if (item.has == false) C.accentInk else C.muted)
        }
    }
}

/** At the top of the list after an update: the build it is now and what it brought; opens the changelog. */
@Composable
fun ChangelogNews() {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val topic by rememberTopic<ChangelogView>(app.core, Topics.changelog)
    val news = topic.value?.news ?: return
    val lines = news.entries.flatMap { it.text }
    Box(Modifier.padding(start = 12.dp, end = 12.dp, top = 4.dp, bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
        Column(Modifier.fillMaxWidth().clickable { app.push(Screen.Changelog) }.padding(start = 16.dp, end = 44.dp, top = 12.dp, bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(Modifier.padding(bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                IconIn(Icons.Sparks, 16.dp, C.ink)
                Text("已更新" + (news.build?.let { "到 $it" } ?: ""), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            }
            lines.take(3).forEach { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            if (lines.size > 3) Text("还有 ${lines.size - 3} 项", fontSize = 13.sp, lineHeight = 18.sp, color = C.muted)
        }
        Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(32.dp).clip(CircleShape).clickable { scope.launch { seen(app) } }.semantics { contentDescription = "知道了" }, contentAlignment = Alignment.Center) {
            IconIn(Icons.Close, 16.dp, C.muted)
        }
    }
}
