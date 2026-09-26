// A new chat rises from the bottom: say what to do, having picked where it
// runs (station), on what (model) and how hard it thinks. The first message
// (or file) makes the session on that station; then the page becomes the chat.
package dev.ember.android.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.R
import dev.ember.android.Screen
import dev.ember.android.data.EFFORTS
import dev.ember.android.data.EFFORT_LABEL
import dev.ember.android.data.RUNTIME_LABEL
import dev.ember.android.data.StationView
import dev.ember.android.data.Topics
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.C
import dev.ember.android.ui.Illustration
import dev.ember.android.ui.Loading
import dev.ember.android.ui.MakerIcon
import dev.ember.android.ui.ModelMark
import dev.ember.android.ui.NavBar
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetHead
import dev.ember.android.ui.SheetSpec
import dev.ember.core.CoreException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.launch

/** What the new chat runs on; kept per station for next time. */
private data class Choice(val runtime: String, val model: String, val effort: String)

private fun AppState.lastChoice(station: String): Choice? =
    strings("newChat/$station").takeIf { it.size == 3 }?.let { Choice(it[0], it[1], it[2]) }

private fun AppState.keepChoice(station: String, c: Choice) {
    setStrings("newChat/$station", listOf(c.runtime, c.model, c.effort.ifEmpty { "-" }))
    setStrings("newChat.last", listOf(station))
}

private val COMMON = listOf("跑一下测试，失败的话看看是哪个", "看看这台机器的磁盘和内存", "帮我 review 最近一个 PR")

@Composable
fun NewChatScreen(scope: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(scope))
    val all = stations.value
    Column(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.ime.union(WindowInsets.navigationBars))) {
        NavBar("取消", app::pop, "新对话")
        val online = all?.filter { it.online }.orEmpty()
        when {
            all == null -> Loading(stations.error?.message ?: "正在读取 station…")
            online.isEmpty() -> Column(Modifier.fillMaxSize().padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
                Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 240.dp)
                Text("没有在线的 station", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text("在一台机器上打开 ember，它就会连上这个 workspace。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
                OnComputer("添加 station", app.web("/w/$scope/settings"))
            }
            else -> {
                val remembered = app.strings("newChat.last").firstOrNull()
                var picked by remember { mutableStateOf(online.firstOrNull { it.station == remembered }?.station ?: online.first().station) }
                val view = online.firstOrNull { it.station == picked } ?: online.first()
                NewChatOn(view, online) { picked = it }
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.NewChatOn(view: StationView, stations: List<StationView>, onStation: (String) -> Unit) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val draft = remember(view.station) { Draft() }
    var choice by remember(view.station) { mutableStateOf(app.lastChoice(view.station)) }
    // Runtimes this station has enabled models for; a remembered model no longer enabled gives way to the first that is.
    val runtime = view.runtimes.firstOrNull { it.runtime == choice?.runtime } ?: view.runtimes.firstOrNull()
    val model = runtime?.models?.firstOrNull { it == choice?.model } ?: runtime?.models?.firstOrNull()
    val effort = choice?.effort?.takeIf { it != "-" && runtime != null && it in EFFORTS[runtime.runtime].orEmpty() } ?: ""
    val pick = { next: Choice -> choice = next; app.keepChoice(view.station, next) }
    // The session is made on the first file or message, once.
    var made by remember(view.station) { mutableStateOf<Deferred<String>?>(null) }
    val ensure: suspend () -> String = {
        val m = model ?: throw CoreException("no_model", "先在 Profile 里启用模型", null)
        made ?: CompletableDeferred<String>().also { d ->
            made = d
            try {
                d.complete(app.api(view.station).newSession(runtime!!.runtime, m, effort.ifEmpty { null }))
            } catch (e: CoreException) {
                made = null
                d.completeExceptionally(e)
            }
        }
        made!!.await()
    }
    val launchers = AttachLaunchers { app.upload(draft, view.station, ensure, it, scope) }
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
        Column(Modifier.fillMaxWidth().padding(start = 30.dp, end = 30.dp, top = 30.dp, bottom = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 230.dp)
            Text("想让 agent 做什么？", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, modifier = Modifier.padding(top = 6.dp))
            Text("选好在哪台机器、用什么模型，然后说就行。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
        }
        Column(Modifier.padding(horizontal = 16.dp, vertical = 14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            val recent = app.strings("newChat.recent")
            (recent.map { it to "最近用过" } + COMMON.filter { it !in recent }.map { it to "常用" }).take(3).forEach { (text, sub) ->
                Column(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(C.surface).border(1.dp, C.line, RoundedCornerShape(14.dp))
                        .clickable { draft.text = text }.padding(horizontal = 14.dp, vertical = 11.dp),
                ) {
                    Text(text, fontSize = 14.sp, color = C.ink)
                    Text(sub, fontSize = 12.sp, color = C.muted)
                }
            }
        }
    }
    Column(Modifier.fillMaxWidth().background(C.bg).padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 2.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chooser({ Box(Modifier.size(8.dp).clip(CircleShape).background(C.green)) }, view.name) { pickStation(app, stations, view.station, onStation) }
            if (runtime == null || model == null) {
                // Nothing to choose from: the chooser leads to where models are enabled.
                Chooser(null, "没有可用模型 · 去勾选") { app.push(Screen.Station(view.station)) }
            } else {
                Chooser({ MakerIcon(model, 14.dp) }, model) {
                    pickModel(app, view, model) { rt, m -> pick(Choice(rt, m, if (rt != runtime.runtime) "" else effort)) }
                }
                Chooser(null, "思考 " + (EFFORT_LABEL[effort] ?: "默认")) {
                    pickEffort(app, runtime.runtime, effort) { e -> pick(Choice(runtime.runtime, model, e)) }
                }
            }
        }
        DraftExtras(draft)
        ComposerBar(draft, "做任何事", onPlus = { openAttach(app, launchers) }, onType = {}, onSend = {
            draft.sending = true
            scope.launch {
                try {
                    val key = ensure()
                    val text = draft.text.trim()
                    app.api(view.station).send(key, text, draft.files.mapNotNull { it.done })
                    if (text.isNotEmpty()) app.setStrings("newChat.recent", (listOf(text) + app.strings("newChat.recent").filter { it != text }).take(3))
                    app.replace(Screen.Chat(view.station, key))
                } catch (e: CoreException) {
                    app.toast = "没发出去：${e.message}"
                } finally {
                    draft.sending = false
                }
            }
        })
    }
}

@Composable
private fun Chooser(leading: (@Composable () -> Unit)?, label: String, onClick: () -> Unit) {
    Row(
        Modifier.height(30.dp).clip(RoundedCornerShape(15.dp)).background(C.surface).border(1.dp, C.line, RoundedCornerShape(15.dp)).clickable(onClick = onClick).padding(horizontal = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        leading?.invoke()
        Text(label, fontSize = 13.sp, color = C.ink, maxLines = 1)
    }
}

private fun pickStation(app: AppState, stations: List<StationView>, current: String, onPick: (String) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead("在哪台 station 上跑")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            stations.forEach { s ->
                PickRow(s.name, listOfNotNull(s.host?.os, "在线").joinToString(" · "), checked = s.station == current) { onPick(s.station); app.sheet = null }
            }
        }
    }
}

private fun pickModel(app: AppState, view: StationView, current: String, onPick: (String, String) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead("用哪个模型")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            view.runtimes.forEach { rt ->
                rt.models.forEach { m ->
                    PickRow(m, RUNTIME_LABEL[rt.runtime] ?: rt.runtime, checked = m == current, leading = { ModelMark(m, 36.dp) }) { onPick(rt.runtime, m); app.sheet = null }
                }
            }
            Text("只列出在 Profile 里勾选过的模型；由 station 的账号池挑一个有余量的账号来跑。", fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 30.dp))
        }
    }
}

private fun pickEffort(app: AppState, runtime: String, current: String, onPick: (String) -> Unit) {
    app.sheet = SheetSpec(0.48f) {
        SheetGrab()
        SheetHead("思考深度")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow("运行时默认", checked = current.isEmpty()) { onPick(""); app.sheet = null }
            EFFORTS[runtime].orEmpty().forEach { e ->
                PickRow("${EFFORT_LABEL[e] ?: e}（$e）", checked = current == e) { onPick(e); app.sheet = null }
            }
        }
    }
}
