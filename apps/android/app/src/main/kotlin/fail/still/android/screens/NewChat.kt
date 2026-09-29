// A new chat rises from the bottom: say what to do, having picked where it
// runs (station), on what (model) and how hard it thinks. The first message
// (or file) makes the session on that station; then the page becomes the chat.
package fail.still.android.screens

import fail.still.android.ui.ComposerInset
import fail.still.android.ui.ComposerCorner
import androidx.compose.foundation.interaction.MutableInteractionSource
import fail.still.android.ui.floating
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
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.R
import fail.still.android.Screen
import fail.still.android.data.ChatOf
import fail.still.android.data.RUNTIME_LABEL
import fail.still.android.data.ModelOption
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.Illustration
import fail.still.android.ui.Loading
import fail.still.android.ui.MakerIcon
import fail.still.android.ui.ModelMark
import fail.still.android.ui.NavBar
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.core.CoreException
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
                if (all.isEmpty()) {
                    // No station at all: the first step is adding one, on the stations page.
                    Text("还没有 station", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Text("station 是一台运行 still.fail 的机器：agent 在那里干活。在要用的机器上执行一条命令，它就会加入这个 workspace。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
                    Button("添加 station", primary = true) { app.replace(Screen.Stations) }
                } else {
                    Text("没有在线的 station", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    Text("在一台机器上打开 still.fail，它就会连上这个 workspace。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
                }
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
    // The model first, from what the station's profiles have enabled; the runtime only when it runs on more than one. A
    // remembered model or runtime no longer there gives way to the first that is.
    val entry = view.models.optionOf(choice?.model) ?: view.models.firstOrNull()
    val model = entry?.model
    val runtime = entry?.runtimes?.firstOrNull { it == choice?.runtime } ?: entry?.runtimes?.firstOrNull()
    val efforts = runtime?.let { entry?.efforts?.get(it) }.orEmpty()
    val effort = choice?.effort?.takeIf { it != "-" && it in efforts } ?: ""
    val pick = { next: Choice -> choice = next; app.keepChoice(view.station, next) }
    // The model list is what a profile's check found; profiles not checked since the station started are checked now, once.
    val profiles = view.overview?.profiles.orEmpty()
    val checked = remember(view.station) { mutableSetOf<String>() }
    LaunchedEffect(profiles) {
        for (p in profiles) if (p.check == null && checked.add(p.id)) launch { try { app.api(view.station).checkProfile(p.id) } catch (_: CoreException) {} }
    }
    // The chat and its session are made with the first message, once.
    var made by remember(view.station) { mutableStateOf<Deferred<Pair<String, Long>>?>(null) }
    var making by remember(view.station) { mutableStateOf(false) }
    val ensure: suspend () -> Pair<String, Long> = {
        val m = model ?: throw CoreException("no_model", "先在 Profile 里启用模型", null)
        made ?: CompletableDeferred<Pair<String, Long>>().also { d ->
            made = d
            making = true
            try {
                d.complete(app.api(view.station).newChat(runtime!!, m, effort.ifEmpty { null }))
            } catch (e: CoreException) {
                made = null
                d.completeExceptionally(e)
            } finally {
                making = false
            }
        }
        made!!.await()
    }
    val launchers = AttachLaunchers { app.upload(draft, view.station, it, scope) }
    val haze = remember { HazeState() }
    // Nothing to run a chat with yet: its first step is the page (the composer comes once it can send).
    val blocked = if (view.overview != null && made == null) (if (profiles.isEmpty()) "profile" else if (view.models.isEmpty()) "models" else null) else null
    if (blocked != null) {
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 18.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 200.dp)
            Text(if (blocked == "profile") "给 ${view.name} 添加一个 Profile" else "勾选要用的模型", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = C.ink, textAlign = TextAlign.Center)
            Text(
                if (blocked == "profile") "agent 用它来跑模型：一份订阅（Claude、ChatGPT），或者一个模型服务的 key。" else "${view.name} 的 Profile 还没有启用模型，勾选之后就能开始对话。",
                fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center,
            )
            if (blocked == "profile") Button("添加 Profile", primary = true) { app.push(Screen.NewProfile(view.station)) }
            else Button("去勾选模型", primary = true) { app.push(Screen.Station(view.station)) }
            if (stations.size > 1) Text("换一台 station", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { pickStation(app, stations, view.station, onStation) })
            if (blocked == "profile") view.overview?.let { o -> Column(Modifier.fillMaxWidth().padding(top = 6.dp)) { MachineLoginOffers(view.station, o, inset = 0.dp) } }
        }
        return
    }
    Column(Modifier.weight(1f).hazeSource(haze).verticalScroll(rememberScrollState())) {
        Column(Modifier.fillMaxWidth().padding(start = 30.dp, end = 30.dp, top = 30.dp, bottom = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 230.dp)
            Text("想让 agent 做什么？", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, modifier = Modifier.padding(top = 6.dp))
            Text("说要做什么。它会在 ${view.name} 上用选好的模型开一个新会话。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            val problem = when {
                view.overview == null -> "正在读取 ${view.name} 的 Profile…"
                profiles.isEmpty() -> "这台 station 还没有 Profile，先添加一个。"
                view.models.isEmpty() -> "这台 station 的 Profile 都还没有启用模型。点下面的「去勾选」，勾选可以用的模型。"
                else -> null
            }
            if (problem != null) Text(problem, fontSize = 13.sp, color = if (view.overview == null) C.muted else C.red, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
            if (making) Text("正在 ${view.name} 上创建会话…", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 6.dp))
        }
    }
    // Chosen anyway (it is the person's call), but said: what is sent waits for its quota.
    entry?.spent?.let { s ->
        Text(
            "${entry.model} 能用的账号额度都用完了" + (s.back?.let { "，$it" } ?: "") + "。现在发的消息要等额度恢复才会有回复；也可以换一个模型。",
            fontSize = 13.sp, color = C.ink,
            modifier = Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f)).padding(horizontal = 12.dp, vertical = 8.dp),
        )
    }
    // The choices, then the composer as a floating capsule, as in a chat.
    Column(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 8.dp, bottom = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        // Room above and below for the chips' shadows, which the scroll would cut.
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 2.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chooser(haze, { IconIn(Icons.Server, 13.dp, C.ink) }, view.name) { pickStation(app, stations, view.station, onStation) }
            if (runtime == null || model == null) {
                // Nothing to choose from: the chooser leads to where models are enabled.
                Chooser(haze, null, "没有可用模型 · 去勾选") { app.push(Screen.Station(view.station)) }
            } else {
                Chooser(haze, { MakerIcon(entry.maker, runtime, 14.dp) }, entry.name) {
                    pickModel(app, view, model) { m -> val rt = m.runtimes.firstOrNull { it == runtime } ?: m.runtimes.first(); pick(Choice(rt, m.model, if (rt != runtime) "" else effort)) }
                }
                // The runtime only when the model runs on more than one.
                if ((entry?.runtimes?.size ?: 0) > 1) Chooser(haze, { MakerIcon(null, runtime, 13.dp) }, RUNTIME_LABEL[runtime] ?: runtime) {
                    pickRuntime(app, entry!!.runtimes, runtime) { rt -> pick(Choice(rt, model, "")) }
                }
                Chooser(haze, null, effort.ifEmpty { "默认深度" }) {
                    pickEffort(app, efforts, effort) { e -> pick(Choice(runtime, model, e)) }
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
private fun Chooser(haze: HazeState, leading: (@Composable () -> Unit)?, label: String, onClick: () -> Unit) {
    // The same glass as the composer's capsule under it.
    Row(
        Modifier.height(30.dp).floating(haze, RoundedCornerShape(15.dp)).clickable(onClick = onClick).padding(horizontal = 11.dp),
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
                PickRow(s.name, s.summary, checked = s.station == current, leading = { Buddy(s, 36) }) { onPick(s.station); app.sheet = null }
            }
        }
    }
}

private fun pickModel(app: AppState, view: StationView, current: String, onPick: (ModelOption) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead("用哪个模型")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            view.models.forEach { m ->
                PickRow(m.name, listOfNotNull(m.runtimes.joinToString(" · ") { RUNTIME_LABEL[it] ?: it }, m.spent?.text).joinToString(" · "), checked = m.model == current, leading = { ModelMark(m.maker, m.runtimes.first(), 36.dp) }) { onPick(m); app.sheet = null }
            }
        }
    }
}

private fun pickRuntime(app: AppState, runtimes: List<String>, current: String, onPick: (String) -> Unit) {
    app.sheet = SheetSpec(0.36f) {
        SheetGrab()
        SheetHead("用哪个运行时")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            runtimes.forEach { rt -> PickRow(RUNTIME_LABEL[rt] ?: rt, checked = rt == current, leading = { ModelMark(null, rt, 36.dp) }) { onPick(rt); app.sheet = null } }
        }
    }
}

private fun pickEffort(app: AppState, efforts: List<String>, current: String, onPick: (String) -> Unit) {
    app.sheet = SheetSpec(0.48f) {
        SheetGrab()
        SheetHead("思考深度")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow("默认", checked = current.isEmpty()) { onPick(""); app.sheet = null }
            efforts.forEach { e ->
                PickRow(e, checked = current == e) { onPick(e); app.sheet = null }
            }
        }
    }
}
