// What the agents spent, from settings, as the narrow web has it (web/src/mobile/Usage.tsx): the core's `usage` view
// (client/core-ts/src/views/usage.ts) for the last 7 or 30 days. A few totals, each day's cost as a bar split by who it was
// for (tapped, the day says its numbers: there is no hover here), and who, which chats, which accounts and which
// models spent the most. Everything shown is the core's; the page only picks the days and the list.
package fail.still.android.screens

import fail.still.android.data.t
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
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
import fail.still.android.ui.Markdown
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.Seg
import fail.still.android.ui.Smooth
import fail.still.android.ui.LIST_ROW_CORNER
import fail.still.android.ui.LIST_PAD
import fail.still.android.ui.bleed
import fail.still.android.ui.pressText
import fail.still.android.ui.CARD_PAD
import fail.still.android.ui.concentricOut
import fail.still.android.ui.WaitShape
import fail.still.android.ui.Waiting

private val DAYS get() = listOf(7 to t("android-misc.usage.days", "n" to 7), 30 to t("android-misc.usage.days", "n" to 30))

// The people a day's bar is split by, as the web draws them (web/src/Usage.css.ts): checked for colour-blind readers
// on both grounds; the first is still.fail's accent, stepped down in dark.
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
    // Its days are its own action, at the top bar's right; nothing to add.
    PlacePage(current, "usage", null, actions = {
        Seg(DAYS.map { it.second }, DAYS.indexOfFirst { it.first == days }.coerceAtLeast(0), { days = DAYS[it].first })
    }) { top ->
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = top)) {
        if (view == null) {
            Waiting(WaitShape.Cards, text = t("common.reading"), error = topic.error?.let { t("android-misc.usage.loadFailed", "error" to it.message) })
        } else {
            Tiles(view) { app.push(Screen.UsagePrices(days)) }
            // None counted yet: the stations not read yet, or those that could not be; else none at all, what the page
            // counts said with it.
            if (view.empty && (view.wait.reading || view.wait.failing.isNotEmpty())) Waiting(WaitShape.Cards, count = 2, note = view.wait)
            else if (view.empty) PlaceEmpty(t("android-misc.usage.none"), t("android-misc.usage.note"))
            else {
                Card { Days(view) }
                Lists(view) { item ->
                    val chat = item.chat ?: return@Lists
                    val of = chat.thread?.let { ChatOf.Thread(it) } ?: chat.session?.let { ChatOf.Session(it) } ?: return@Lists
                    app.push(Screen.Chat(chat.station, of))
                }
            }
            Column(Modifier.padding(horizontal = 24.dp, vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                // How it is counted, under what was counted (nothing counted: the empty place says it already).
                (if (view.empty) view.notes else view.notes + view.basis).forEach { Text(it, fontSize = 12.sp, color = C.subtle) }
            }
        }
        Spacer(Modifier.height(30.dp))
        BarRoom()
    }
    }
}

/** The totals, two to a row. */
@Composable
private fun Tiles(view: UsageView, openPrices: () -> Unit) {
    Column(Modifier.padding(horizontal = 12.dp).padding(bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        view.tiles.chunked(2).forEach { pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEach { tile ->
                    Column(Modifier.weight(1f).clip(Smooth(18.dp)).background(C.surface).then(if (tile == view.tiles.firstOrNull()) Modifier.clickable(onClick = openPrices) else Modifier).padding(horizontal = 16.dp, vertical = 14.dp)) {
                        Text(tile.label, fontSize = 12.sp, color = C.muted)
                        Text(tile.value, fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, maxLines = 1)
                        Text(if (tile == view.tiles.firstOrNull()) t("android-misc.usage.seePrices") else tile.sub, fontSize = 12.sp, color = C.subtle, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

/** The plot's height, a day's bar's width (with many days, as wide as its day), and the room at the right the scale says its lines in. */
private val PLOT = 150.dp
private val BAR = 16.dp
private val SCALE_ROOM = 24.dp

/**
 * Each day's cost as a bar on the scale's lines, split by who it was for; the day tapped (today at first) says its
 * numbers over them, and with several people what each of them spent that day under them.
 */
@Composable
private fun Days(view: UsageView) {
    var picked by rememberSaveable(view.days) { mutableStateOf<String?>(null) }
    val day = view.daily.firstOrNull { it.day == picked } ?: view.daily.lastOrNull()
    val several = view.series.size > 1
    val many = view.daily.size > 10
    val gap = if (many) 2.dp else 6.dp
    if (day != null) {
        Text(if (day.today) t("android-misc.usage.today") else day.label, fontSize = 12.sp, color = C.muted)
        Row(Modifier.padding(top = 2.dp, bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(day.costText, fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = C.ink, modifier = Modifier.alignByBaseline())
            Text(day.callsText, fontSize = 13.sp, color = C.muted, modifier = Modifier.alignByBaseline())
        }
    }
    Box(Modifier.fillMaxWidth().height(PLOT)) {
        // the scale's lines across, each said at the right just over it, where no bar is
        if (view.top > 0) view.ticks.forEach { tick ->
            val y = PLOT * (1f - (tick.value / view.top).toFloat())
            Box(Modifier.fillMaxWidth().offset(y = y).height(1.dp).background(C.line))
            Text(tick.label, fontSize = 10.sp, color = C.subtle, maxLines = 1, softWrap = false, modifier = Modifier.align(Alignment.TopEnd).offset(y = y).above(2.dp))
        }
        Row(Modifier.fillMaxSize().padding(end = SCALE_ROOM), horizontalArrangement = Arrangement.spacedBy(gap)) {
            view.daily.forEach { d ->
                Column(Modifier.weight(1f).fillMaxHeight().testTag("usage-day-${d.day}").clickable { picked = d.day }, verticalArrangement = Arrangement.Bottom, horizontalAlignment = Alignment.CenterHorizontally) {
                    Bar(d, view, many)
                }
            }
        }
    }
    Box(Modifier.fillMaxWidth().height(1.dp).background(C.line))
    Row(Modifier.fillMaxWidth().padding(top = 6.dp, end = SCALE_ROOM), horizontalArrangement = Arrangement.spacedBy(gap)) {
        view.daily.forEachIndexed { i, d ->
            val shown = !many || d.today || (view.daily.size - 1 - i) % 7 == 0
            Text(if (!shown) "" else if (d.today) t("android-misc.usage.today") else d.label, fontSize = 11.sp, color = if (d == day) C.ink else C.subtle,
                fontWeight = if (d == day) FontWeight.Medium else null, maxLines = 1, softWrap = false, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
        }
    }
    // with several people: each of them (the rest too), what they spent that day and its share of the day's
    if (several && day != null) Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        view.series.forEachIndexed { i, s ->
            val part = day.parts.getOrNull(i) ?: 0.0
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(8.dp).clip(CircleShape).background(seriesColor(view.series, i)))
                    Text(s.name, fontSize = 13.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Text(day.partsText.getOrNull(i).orEmpty(), fontSize = 13.sp, color = C.ink)
                }
                Box(Modifier.padding(start = 16.dp).fillMaxWidth().height(4.dp).clip(Smooth(2.dp)).background(C.chip)) {
                    if (part > 0 && day.cost > 0) Box(Modifier.fillMaxWidth((part / day.cost).toFloat().coerceIn(.01f, 1f)).fillMaxHeight().clip(Smooth(2.dp)).background(seriesColor(view.series, i)))
                }
            }
        }
    }
}

/** Laid out `gap` over where it is put: its foot there. */
private fun Modifier.above(gap: Dp) = layout { m, c ->
    val p = m.measure(c)
    layout(p.width, p.height) { p.place(0, -p.height - gap.roundToPx()) }
}

/**
 * A day's bar, as high as its share of the scale's top: its people's parts one over another, the first at the foot,
 * 1 apart, each round at its ends but the foot's, which stands square on the line.
 */
@Composable
private fun Bar(d: UsageDay, view: UsageView, many: Boolean) {
    if (view.top <= 0 || d.cost <= 0) return
    val share = (d.cost / view.top).toFloat().coerceIn(0f, 1f)
    val r = if (many) 2.dp else 4.dp
    val parts = d.parts.withIndex().filter { it.value > 0 }
    val foot = parts.firstOrNull()?.index
    Column(Modifier.then(if (many) Modifier.fillMaxWidth() else Modifier.width(BAR)).fillMaxHeight(share), verticalArrangement = Arrangement.spacedBy(1.dp, Alignment.Bottom)) {
        // top first: the column is laid out from the top, the first person at the foot
        parts.reversed().forEach { (i, p) ->
            Box(Modifier.fillMaxWidth().weight((p / d.cost).toFloat().coerceAtLeast(.001f)).clip(if (i == foot) Smooth(topStart = r, topEnd = r) else Smooth(r)).background(seriesColor(view.series, i)))
        }
    }
}

/** The lists, one at a time, the first few until asked for all. */
@Composable
private fun Lists(view: UsageView, open: (UsageItem) -> Unit) {
    var shown by rememberSaveable { mutableIntStateOf(0) }
    val list: UsageList = view.lists.getOrNull(shown) ?: view.lists.firstOrNull() ?: return
    var all by rememberSaveable(list.key) { mutableStateOf(false) }
    // Its switch (a Seg, rounded 10) in its top corners: the card's corner taken from it, concentric.
    Card(corner = concentricOut(10.dp, CARD_PAD)) {
        Seg(view.lists.map { it.title }, view.lists.indexOf(list).coerceAtLeast(0), { shown = it }, fill = true)
        Spacer(Modifier.height(6.dp))
        val items = if (all) list.items else list.items.take(8)
        items.forEachIndexed { i, item -> ItemRow(item, i + 1, list.key, open) }
        if (list.items.size > 8) Text(if (all) t("android-misc.usage.collapse") else t("android-misc.usage.showAll", "n" to list.items.size), fontSize = 14.sp, color = C.muted,
            modifier = Modifier.padding(vertical = 8.dp).pressText { all = !all })
    }
}

@Composable
private fun ItemRow(item: UsageItem, rank: Int, kind: String, open: (UsageItem) -> Unit) {
    val opens = kind == "chats" && item.chat != null
    // Its ground under the finger out to LIST_PAD from the card's edge, its words where the card's are, as a list card's rows.
    Column(Modifier.fillMaxWidth().bleed(CARD_PAD - LIST_PAD).clip(Smooth(LIST_ROW_CORNER)).let { if (opens) it.clickable { open(item) } else it }.padding(horizontal = CARD_PAD - LIST_PAD, vertical = 10.dp)) {
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
fun UsagePricesScreen(current: WorkspaceEntry, days: Int) {
    val app = LocalApp.current
    val topic by rememberTopic<UsageView>(app.core, Topics.usage(current.workspace.id, days))
    val view = topic.value
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(t("android-misc.usage.title"), app::pop)
        LargeTitle("", t("android-misc.usage.prices"))
        PageNote(t("android-misc.usage.prices.note"))
        if (view == null) Waiting(WaitShape.Cards, text = t("common.reading"), error = topic.error?.let { t("android-misc.usage.prices.loadFailed", "error" to it.message) })
        else {
            val tables = view.prices.orEmpty()
            // None yet while the stations are still read (or could not be): waited on, not said to be none.
            if (tables.isEmpty() && (view.wait.reading || view.wait.failing.isNotEmpty())) Waiting(WaitShape.Cards, count = 2, note = view.wait)
            else if (tables.isEmpty()) PageNote(t("android-misc.usage.prices.none"))
            tables.forEach { table ->
                Card {
                    Text(table.station, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Text(table.note, fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp))
                    if (table.rows.isEmpty()) Text(t("android-misc.usage.prices.noModels"), fontSize = 12.sp, color = C.muted)
                    else {
                        // Serialize already-formatted cells for the app's existing Markdown table renderer.
                        fun cell(value: String) = buildString {
                            value.forEach { c ->
                                if (c == '\n' || c == '\r') append(' ')
                                else { if (c in "\\`*_[]<>|") append('\\'); append(c) }
                            }
                        }
                        fun line(cells: List<String>) = cells.joinToString(" | ", "| ", " |", transform = ::cell)
                        val header = listOf(t("android-misc.usage.prices.model")) + table.rows.first().rates.map { it.label }
                        val markdown = (listOf(line(header), line(header.map { "---" })) +
                            table.rows.map { row -> line(listOf(row.model) + row.rates.map { it.value }) }).joinToString("\n")
                        Markdown(markdown, modifier = Modifier.padding(top = 8.dp), fillTables = true)
                    }
                }
            }
        }
        Spacer(Modifier.height(30.dp))
    }
}
