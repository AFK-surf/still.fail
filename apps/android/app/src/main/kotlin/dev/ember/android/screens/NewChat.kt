// A new chat rises from the bottom: say what to do, having picked where it
// runs (station), on what (model) and how hard it thinks. The first message
// (or file) makes the session on that station; then the page becomes the chat.
package dev.ember.android.screens

import dev.ember.android.ui.ComposerInset
import dev.ember.android.ui.ComposerCorner
import androidx.compose.foundation.interaction.MutableInteractionSource
import dev.ember.android.ui.floating
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.HazeState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import dev.ember.android.data.ChatOf
import dev.ember.android.data.EFFORTS
import dev.ember.android.data.EFFORT_LABEL
import dev.ember.android.data.RUNTIME_LABEL
import dev.ember.android.data.StationView
import dev.ember.android.data.Topics
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.C
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
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
    // The model list is what a profile's check found; profiles not checked since the station started are checked now, once.
    val profiles = view.overview?.profiles.orEmpty()
    val checked = remember(view.station) { mutableSetOf<String>() }
    LaunchedEffect(profiles) {
        for (p in profiles) if (p.check == null && checked.add(p.id)) launch { try { app.api(view.station).checkProfile(p.id) } catch (_: CoreException) {} }
    }
    // The chat and its session are made on the first file or message, once.
    var made by remember(view.station) { mutableStateOf<Deferred<Pair<String, Long>>?>(null) }
    var making by remember(view.station) { mutableStateOf(false) }
    val ensure: suspend () -> Pair<String, Long> = {
        val m = model ?: throw CoreException("no_model", "先在 Profile 里启用模型", null)
        made ?: CompletableDeferred<Pair<String, Long>>().also { d ->
            made = d
            making = true
            try {
                d.complete(app.api(view.station).newChat(runtime!!.runtime, m, effort.ifEmpty { null }))
            } catch (e: CoreException) {
                made = null
                d.completeExceptionally(e)
            } finally {
                making = false
            }
        }
        made!!.await()
    }
    val launchers = AttachLaunchers { app.upload(draft, view.station, { ensure().first }, it, scope) }
    val haze = remember { HazeState() }
    Column(Modifier.weight(1f).hazeSource(haze).verticalScroll(rememberScrollState())) {
        Column(Modifier.fillMaxWidth().padding(start = 30.dp, end = 30.dp, top = 30.dp, bottom = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 230.dp)
            Text("想让 agent 做什么？", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, modifier = Modifier.padding(top = 6.dp))
            Text("说要做什么。它会在 ${view.name} 上用选好的模型开一个新会话。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            val problem = when {
                view.overview == null -> "正在读取 ${view.name} 的 Profile…"
                profiles.isEmpty() -> "这台 station 还没有 Profile，先在电脑上到 设置 → Profile 里加一个。"
                view.runtimes.isEmpty() -> "这台 station 的 Profile 都还没有启用模型。点下面的「去勾选」，勾选可以用的模型。"
                else -> null
            }
            if (problem != null) Text(problem, fontSize = 13.sp, color = if (view.overview == null) C.muted else C.red, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
            if (making) Text("正在 ${view.name} 上创建会话…", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 6.dp))
        }
    }
    // The choices, then the composer as a floating capsule, as in a chat.
    Column(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 2.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chooser({ IconIn(Icons.Server, 13.dp, C.ink) }, view.name) { pickStation(app, stations, view.station, onStation) }
            if (runtime == null || model == null) {
                // Nothing to choose from: the chooser leads to where models are enabled.
                Chooser(null, "没有可用模型 · 去勾选") { app.push(Screen.Station(view.station)) }
            } else {
                Chooser({ MakerIcon(model, runtime.runtime, 14.dp) }, model) {
                    pickModel(app, view, runtime.runtime, model) { rt, m -> pick(Choice(rt, m, if (rt != runtime.runtime) "" else effort)) }
                }
                Chooser(null, "思考 " + (EFFORT_LABEL[effort] ?: "默认")) {
                    pickEffort(app, runtime.runtime, effort) { e -> pick(Choice(runtime.runtime, model, e)) }
                }
            }
        }
        Column(Modifier.fillMaxWidth().floating(haze, RoundedCornerShape(ComposerCorner)).clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { draft.focus++ }.padding(ComposerInset), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            DraftExtras(draft)
            ComposerBar(draft, "做任何事", onPlus = { openAttach(app, launchers) }, onType = {}, onSend = {
                val text = draft.text.trim()
                val files = draft.files.toList()
                draft.text = ""; draft.files.clear(); draft.error = null
                draft.starting = true
                scope.launch {
                    val (key, thread) = try {
                        ensure()
                    } catch (e: CoreException) {
                        // No chat to send into: the draft comes back.
                        draft.text = text; draft.files.addAll(files); draft.error = e.message
                        return@launch
                    } finally {
                        draft.starting = false
                    }
                    app.scope.launch { try { app.api(view.station).send(thread, text, files.mapNotNull { it.done }) } catch (_: CoreException) {} }
                    // The new item's page, by its agent (its address from now on).
                    app.replace(Screen.Chat(view.station, ChatOf.Session(key)))
                }
            })
            draft.error?.let { Text(it, fontSize = 12.sp, color = C.red, modifier = Modifier.padding(horizontal = 6.dp)) }
        }
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
                PickRow(s.name, checked = s.station == current) { onPick(s.station); app.sheet = null }
            }
        }
    }
}

private fun pickModel(app: AppState, view: StationView, currentRuntime: String, current: String, onPick: (String, String) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead("用哪个模型")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            view.runtimes.forEach { rt ->
                rt.models.forEach { m ->
                    PickRow(m, RUNTIME_LABEL[rt.runtime] ?: rt.runtime, checked = rt.runtime == currentRuntime && m == current, leading = { ModelMark(m, rt.runtime, 36.dp) }) { onPick(rt.runtime, m); app.sheet = null }
                }
            }
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
