// What the agents spent, from settings, as the narrow web has it (web/src/mobile/Usage.tsx): the core's `usage` view
// (client/core/src/views/usage.rs) for the last 7 or 30 days. A few totals, each day's cost as a bar split by who it was
// for (tapped, the day says its numbers: there is no hover here), and who, which chats, which accounts and which
// models spent the most. Everything shown is the core's; the page only picks the days and the list.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.Topics
import fail.still.android.data.UsageDay
import fail.still.android.data.UsageItem
import fail.still.android.data.UsageList
import fail.still.android.data.UsageSeries
import fail.still.android.data.UsageView
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.Avatar
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.Seg

private val DAYS = listOf(7 to "7 天", 30 to "30 天")

// The people a day's bar is split by, as the web draws them (web/src/Usage.css.ts): checked for colour-blind readers
// on both grounds; the first is ember's accent, stepped down in dark.
private val LIGHT = listOf(Color(0xFFEF6A3C), Color(0xFF2A78D6), Color(0xFF1BAF7A), Color(0xFF4A3AA7))
private val DARK = listOf(Color(0xFFE0602F), Color(0xFF3987E5), Color(0xFF199E70), Color(0xFF9085E9))

@Composable
private fun seriesColor(series: List<UsageSeries>, i: Int): Color =
    if (series.getOrNull(i)?.key == "") C.subtle.copy(alpha = .45f) else (if (C.dark) DARK else LIGHT)[i % 4]

@Composable
fun UsageScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    var days by rememberSaveable { mutableIntStateOf(7) }
    val topic by rememberTopic<UsageView>(app.core, Topics.usage(current.workspace.id, days))
    val view = topic.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("设置", app::pop) {
            Seg(DAYS.map { it.second }, DAYS.indexOfFirst { it.first == days }.coerceAtLeast(0), { days = DAYS[it].first })
        }
        LargeTitle("", "用量")
        PageNote("agent 调用模型用了多少 token，按 API 价折算成钱")
        if (view == null) {
            Text(topic.error?.let { "读不到用量：${it.message}" } ?: "正在读取…", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(24.dp))
        } else {
            Tiles(view) { app.push(Screen.UsagePrices) }
            if (view.empty) {
                Text(if (view.loading) "正在读取…" else "这段时间没有用量", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(28.dp))
            } else {
                Card { Days(view) }
                Lists(view) { item ->
                    val chat = item.chat ?: return@Lists
                    val of = chat.thread?.let { ChatOf.Thread(it) } ?: chat.session?.let { ChatOf.Session(it) } ?: return@Lists
                    app.push(Screen.Chat(chat.station, of))
                }
            }
            Column(Modifier.padding(horizontal = 24.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                (view.notes + view.basis).forEach { Text(it, fontSize = 12.sp, color = C.subtle) }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** The totals, two to a row. */
@Composable
private fun Tiles(view: UsageView, openPrices: () -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        view.tiles.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { t ->
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(18.dp)).background(C.surface).then(if (t == view.tiles.firstOrNull()) Modifier.clickable(onClick = openPrices) else Modifier).padding(horizontal = 16.dp, vertical = 14.dp)) {
                        Text(t.label, fontSize = 12.sp, color = C.muted)
                        Text(t.value, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1)
                        Text(if (t == view.tiles.firstOrNull()) "查看价目表 →" else t.sub, fontSize = 12.sp, color = C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** Each day's cost as a bar, split by who it was for; the day tapped (today at first) says its numbers under them. */
@Composable
private fun Days(view: UsageView) {
    var picked by rememberSaveable(view.days) { mutableStateOf<String?>(null) }
    val day = view.daily.firstOrNull { it.day == picked } ?: view.daily.lastOrNull()
    val several = view.series.size > 1
    val many = view.daily.size > 10
    if (several) Row(Modifier.padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        view.series.forEachIndexed { i, s ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.weight(1f, fill = false)) {
                Box(Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(seriesColor(view.series, i)))
                Text(s.name, fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
    Row(Modifier.fillMaxWidth().height(150.dp), horizontalArrangement = Arrangement.spacedBy(if (many) 3.dp else 6.dp)) {
        view.daily.forEach { d ->
            Column(
                Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                    .background(if (d.day == day?.day) C.chip else Color.Transparent).clickable { picked = d.day },
                verticalArrangement = Arrangement.Bottom, horizontalAlignment = Alignment.CenterHorizontally,
            ) { Bar(d, view) }
        }
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(C.line))
    Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(if (many) 3.dp else 6.dp)) {
        view.daily.forEachIndexed { i, d ->
            val shown = !many || d.today || (view.daily.size - 1 - i) % 7 == 0
            Text(if (!shown) "" else if (d.today) "今天" else d.label, fontSize = 11.sp, color = if (d.today) C.ink else C.subtle, maxLines = 1, softWrap = false,
                textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
        }
    }
    if (day != null) Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Text("${if (day.today) "今天" else day.label} · ${day.costText} · ${day.callsText}", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = C.ink)
        if (several && day.cost > 0) view.series.forEachIndexed { i, s ->
            if ((day.parts.getOrNull(i) ?: 0.0) > 0) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.size(8.dp).clip(RoundedCornerShape(2.dp)).background(seriesColor(view.series, i)))
                Text(s.name, fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Text(day.partsText.getOrNull(i).orEmpty(), fontSize = 12.sp, color = C.muted)
            }
        }
    }
}

@Composable
private fun Bar(d: UsageDay, view: UsageView) {
    if (view.max <= 0 || d.cost <= 0) return
    val share = (d.cost / view.max).toFloat().coerceIn(0f, 1f)
    Column(Modifier.widthIn(max = 28.dp).fillMaxWidth().fillMaxHeight(share).clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp)),
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.Bottom)) {
        // Top first: the column is drawn from the top, the first person at the foot.
        d.parts.withIndex().reversed().filter { it.value > 0 }.forEach { (i, p) ->
            Box(Modifier.fillMaxWidth().weight((p / d.cost).toFloat().coerceAtLeast(.001f)).background(seriesColor(view.series, i)))
        }
    }
}

/** The lists, one at a time, the first few until asked for all. */
@Composable
private fun Lists(view: UsageView, open: (UsageItem) -> Unit) {
    var shown by rememberSaveable { mutableIntStateOf(0) }
    val list: UsageList = view.lists.getOrNull(shown) ?: view.lists.firstOrNull() ?: return
    var all by rememberSaveable(list.key) { mutableStateOf(false) }
    Card {
        Seg(view.lists.map { it.title }, view.lists.indexOf(list).coerceAtLeast(0), { shown = it }, fill = true)
        Spacer(Modifier.height(6.dp))
        val items = if (all) list.items else list.items.take(8)
        items.forEachIndexed { i, item -> ItemRow(item, i + 1, list.key, open) }
        if (list.items.size > 8) Text(if (all) "收起" else "显示全部 ${list.items.size} 个", fontSize = 14.sp, color = C.muted,
            modifier = Modifier.clip(RoundedCornerShape(10.dp)).clickable { all = !all }.padding(horizontal = 4.dp, vertical = 10.dp))
    }
}

@Composable
private fun ItemRow(item: UsageItem, rank: Int, kind: String, open: (UsageItem) -> Unit) {
    val opens = kind == "chats" && item.chat != null
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).let { if (opens) it.clickable { open(item) } else it }.padding(vertical = 10.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            val person = item.person
            if (kind == "people" && person != null) Avatar(person.email ?: person.id, person.shown?.name ?: item.title, 22.dp, picture = person.shown?.picture)
            else Text("$rank", fontSize = 12.sp, color = C.subtle, textAlign = TextAlign.End, modifier = Modifier.width(22.dp))
            Column(Modifier.weight(1f)) {
                Text(item.title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(listOfNotNull(item.sub, item.detail).joinToString(" · "), fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(item.costText, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(item.shareText, fontSize = 12.sp, color = C.muted)
            }
        }
        // Its share of the whole, under its words.
        Box(Modifier.padding(start = 34.dp, top = 6.dp).fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(C.chip)) {
            Box(Modifier.fillMaxWidth(item.share.toFloat().coerceIn(if (item.share > 0) .01f else 0f, 1f)).fillMaxHeight().background(C.subtle.copy(alpha = .5f)))
        }
    }
}

@Composable
fun UsagePricesScreen(current: WorkspaceEntry) {
    val app = LocalApp.current
    val topic by rememberTopic<UsageView>(app.core, Topics.usage(current.workspace.id, 7))
    val view = topic.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack("用量", app::pop)
        LargeTitle("", "价目表")
        PageNote("当前各台 station 用于折算费用的单价")
        if (view == null) PageNote(topic.error?.let { "读不到价目：${it.message}" } ?: "正在读取…")
        else {
            val tables = view.prices.orEmpty()
            if (tables.isEmpty()) PageNote("暂时没有价目表")
            tables.forEach { table ->
                Card {
                    Text(table.station, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Text(table.note, fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp))
                    table.rows.forEach { row ->
                        Text(row.model, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                        Column(Modifier.padding(top = 10.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            row.rates.forEach { rate ->
                                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                                    Text(rate.label, fontSize = 12.sp, color = C.muted)
                                    Text(rate.value, fontSize = 12.sp, color = C.ink)
                                }
                            }
                        }
                    }
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}
