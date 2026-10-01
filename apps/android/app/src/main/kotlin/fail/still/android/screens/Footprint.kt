// How much a station takes of its machine, from the station's page, as the narrow web's mobile/Usage.tsx has it (the
// core's `footprint` topic, client/core/src/footprint.rs): what it takes and its bar, what can be cleaned, the disk by part,
// the chats on a page of their own, and its memory. Each clean-up is a sheet: its choice, then each question in turn
// (deleting is asked twice), then its call.
package fail.still.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.FootprintAction
import fail.still.android.data.FootprintChoice
import fail.still.android.data.FootprintView
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.errorText
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.NavBar
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.core.CoreException
import kotlinx.coroutines.launch

/** The parts' colours, by the tone the core gives each (as ../Footprint.css.ts). */
@Composable
private fun tone(name: String): Color = when (name) {
    "chart-1" -> C.accent
    "chart-2" -> C.blue
    "chart-3" -> C.green
    "chart-4" -> C.warn
    "chart-5" -> lerp(C.blue, C.red, 0.45f)
    "chart-6" -> C.subtle
    "rest" -> C.subtle.copy(alpha = 0.55f)
    else -> C.line
}

@Composable
private fun Dot(name: String) {
    if (name.isNotEmpty()) Box(Modifier.size(8.dp).clip(CircleShape).background(tone(name)))
}

@Composable
private fun RowScope.Lines(title: String, note: String?, tag: String? = null, nested: Boolean = false) {
    Column(Modifier.weight(1f).padding(start = if (nested) 14.dp else 0.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
            if (tag != null) Text(tag, fontSize = 11.sp, color = C.muted, modifier = Modifier.padding(start = 6.dp).clip(RoundedCornerShape(4.dp)).background(C.chip).padding(horizontal = 5.dp))
        }
        if (!note.isNullOrEmpty()) Text(note, fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

@Composable
private fun Size(text: String) = Text(text, fontSize = 14.sp, color = C.muted, maxLines = 1)

@Composable
private fun Note(text: String) = Text(text, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp))

@Composable
fun FootprintScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val name = stations.value?.firstOrNull { it.station == address }?.name ?: stationName(address)
    val topic by rememberTopic<FootprintView>(app.core, Topics.footprint(address))
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize()) {
        val view = topic.value
        NavBar(name, app::pop, "占用", sub = view?.let { v -> { Text(v.checkedText, fontSize = 11.sp, color = C.muted, maxLines = 1) } })
        if (view == null) return Loading(topic.error?.message?.let { "读不到：$it" } ?: "正在读取…")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 4.dp)) {
            Card {
                Text(view.lead, fontSize = 13.sp, color = C.muted)
                Text(view.totalText, fontSize = 26.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                if (view.bar.isNotEmpty()) {
                    Row(Modifier.padding(top = 10.dp, bottom = 8.dp).fillMaxWidth().height(10.dp).clip(RoundedCornerShape(5.dp)).background(C.line)) {
                        view.bar.filter { it.percent > 0 }.forEach { Box(Modifier.weight(it.percent.toFloat()).fillMaxHeight().background(tone(it.tone))) }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        view.legend.forEach { l ->
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                Dot(l.tone)
                                Text(l.text, fontSize = 12.sp, color = when (l.level) { "red" -> C.red; "amber" -> C.warn; else -> C.muted }, maxLines = 1)
                            }
                        }
                    }
                }
                if (view.measured && !view.scanning) {
                    Text("重新统计", fontSize = 13.sp, color = C.accent, modifier = Modifier.padding(top = 10.dp).clickable {
                        scope.launch { try { app.api(address).scanFootprint() } catch (e: CoreException) { app.toast = errorText(e) } }
                    })
                }
            }
            if (view.measured) {
                SectionHeader("可以清理", start = 24.dp)
                view.actionsNote?.let { Note(it) }
                if (view.actions.isNotEmpty()) ListCard {
                    view.actions.forEach { a ->
                        ListRow({ clean(app, address, a, null) }) {
                            Lines(a.title, a.note)
                            Text(a.action, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = if (a.danger) C.red else C.accent)
                        }
                    }
                }
            }
            if (view.parts.isNotEmpty()) {
                SectionHeader("磁盘 · 按用途", start = 24.dp)
                ListCard {
                    view.parts.forEach { p ->
                        ListRow(if (p.opens) ({ app.push(Screen.FootprintChats(address)) }) else null) {
                            Dot(p.tone)
                            Lines(p.label, p.note)
                            Size(if (p.opens) "${p.text} ›" else p.text)
                        }
                    }
                }
            }
            if (view.elsewhere.isNotEmpty()) {
                SectionHeader("这台机器上的其它", start = 24.dp)
                Note(view.elsewhereNote)
                ListCard { view.elsewhere.forEach { p -> ListRow { Lines(p.label, p.note); Size(p.text) } } }
            }
            SectionHeader(view.memoryTitle, start = 24.dp)
            ListCard {
                view.memory.forEach { r ->
                    val open = if (r.chat != null || r.choice != null) ({ chatSheet(app, address, r.label, r.chat, listOfNotNull(r.choice)) }) else null
                    ListRow(open) { Lines(r.label, r.note, nested = r.nested); Size(r.text) }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** Every chat's directory, largest first; a chat opens its sheet (open it, clean it, delete it). */
@Composable
fun FootprintChatsScreen(address: String) {
    val app = LocalApp.current
    val topic by rememberTopic<FootprintView>(app.core, Topics.footprint(address))
    Column(Modifier.fillMaxSize()) {
        val view = topic.value
        NavBar("占用", app::pop, "chat 工作区", sub = view?.let { v -> { Text(v.chatsText, fontSize = 11.sp, color = C.muted, maxLines = 1) } })
        if (view == null) return Loading("正在读取…")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 4.dp)) {
            ListCard {
                view.chats.forEach { c ->
                    ListRow({ chatSheet(app, address, c.title, c.chat, c.choices) }) {
                        Lines(c.title, c.note, tag = if (c.archived) "已归档" else null)
                        Size(c.text)
                    }
                }
            }
            view.unseenText?.let { Note(it) }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** A chat's sheet: open it, or one of the clean-ups it has. */
private fun chatSheet(app: AppState, address: String, title: String, chat: String?, choices: List<FootprintChoice>) {
    app.sheet = SheetSpec(0.4f) {
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            if (chat != null) PickRow("打开 chat") { app.sheet = null; app.push(Screen.Chat(address, ChatOf.Session(chat))) }
            choices.forEach { c -> PickRow(c.label, color = if (c.call == "footprint.delete") C.red else C.ink) { clean(app, address, null, c) } }
        }
    }
}

/** A clean-up: which choice when it has several, then each question in turn; the sheet stays, with what went wrong,
 * until it is done. */
private fun clean(app: AppState, address: String, action: FootprintAction?, given: FootprintChoice?) {
    app.sheet = SheetSpec(0.42f) {
        val scope = rememberCoroutineScope()
        var choice by remember { mutableStateOf(given ?: action?.choices?.singleOrNull()) }
        var step by remember { mutableIntStateOf(0) }
        var busy by remember { mutableStateOf(false) }
        var error by remember { mutableStateOf<String?>(null) }
        val picked = choice
        SheetGrab()
        if (picked == null) {
            SheetHead(action?.pick.orEmpty())
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
                action?.choices?.forEach { c -> PickRow(c.label) { choice = c } }
            }
        } else {
        val confirm = picked.confirms[step]
        SheetHead(confirm.title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(confirm.text, fontSize = 14.sp, color = C.muted)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button("取消", primary = false) { app.sheet = null }
                Button(confirm.action, primary = true, busy = busy, danger = confirm.danger) {
                    if (step + 1 < picked.confirms.size) { step += 1; return@Button }
                    busy = true; error = null
                    scope.launch {
                        try {
                            app.api(address).cleanUp(picked.call, picked.keys)
                            app.sheet = null; app.toast = picked.done
                        } catch (e: CoreException) { error = errorText(e) } finally { busy = false }
                    }
                }
            }
        }
        }
    }
}
