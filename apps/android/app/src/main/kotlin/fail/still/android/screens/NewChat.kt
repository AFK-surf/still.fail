// A new chat rises from the bottom: say what to do, having picked where it
// runs (station), on what (model) and how hard it thinks. The first message
// (or file) makes the session on that station; then the page becomes the chat.
package fail.still.android.screens

import fail.still.android.ui.ComposerInset
import fail.still.android.ui.ComposerCorner
import androidx.compose.foundation.interaction.MutableInteractionSource
import fail.still.android.ui.floatingStill
import fail.still.android.ui.Ease
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.graphicsLayer
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
import fail.still.android.data.MachineSaid
import fail.still.android.data.MachineSession
import fail.still.android.data.RunnableProfile
import fail.still.android.data.WorkspaceEntry
import fail.still.android.ui.Markdown
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.text.style.TextOverflow
import fail.still.android.data.RUNTIME_LABEL
import fail.still.android.data.ModelOption
import fail.still.android.data.NewChatView
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
import kotlinx.coroutines.launch
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Picks for a new chat in a scope (`station`: its id; the core keeps them, client/core/src/choose.rs): each given changes only that. */
private fun AppState.pickNew(scope: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit) {
    this.scope.launch { try { core.call("newChat.pick", buildJsonObject { put("scope", scope); fill() }) } catch (_: CoreException) {} }
}

/**
 * The new chat, above its host's composer (ChatHost.kt). `leaving`: it has become its chat, which is under it now; only
 * its scene is drawn, going (up out of view, its choices fading where they are).
 */
@Composable
fun NewChatScreen(current: WorkspaceEntry, host: Host, leaving: Boolean = false) {
    val app = LocalApp.current
    val scope = current.workspace.id
    // The station last started on (or picked) in this workspace and what it runs there, as the core keeps them (web/src/pick.ts).
    val chat by rememberTopic<NewChatView>(app.core, Topics.newChat(scope))
    val choice = chat.value
    val onStation = { id: String -> app.pickNew(scope) { put("station", id) } }
    // What the composer frosts, under it: this page (its own paper) until it leaves.
    Column(if (leaving) Modifier.fillMaxSize() else Modifier.fillMaxSize().hazeSource(host.haze).background(C.bg)) {
        // Gone at once as it leaves (the chat has its own bar), its room kept so the scene leaves from where it was.
        Box(Modifier.alpha(if (leaving) 0f else 1f)) { NavBar("取消", app::pop, "新对话") }
        val view = choice?.station
        val online = choice?.stations
        when {
            choice == null || online == null -> Loading(choice?.error ?: chat.error?.message ?: "正在读取 station…")
            !choice.any -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) { FirstStation(current) }
            view == null -> Column(Modifier.fillMaxSize().padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
                Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 240.dp)
                Text("没有在线的 station", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text("在一台机器上打开 still.fail，它就会连上这个 workspace。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            }
            else -> androidx.compose.runtime.key(view.station) { NewChatOn(scope, choice, view, online, onStation, host, leaving) }
        }
        // No composer without a station to write to.
        if (view == null && !leaving) host.spec = null
    }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.NewChatOn(workspace: String, choice: NewChatView, view: StationView, stations: List<StationView>, onStation: (String) -> Unit, host: Host, leaving: Boolean) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    // Kept on the device like a chat's, by its station (web/src/NewChat.tsx: `new:<address>`).
    val draft = rememberDraft("new:${view.station}")
    // What it runs on, as the core resolved it against what the station has now (the same as the web's).
    val entry = choice.model
    val model = entry?.model
    val runtime = choice.runtime
    val effort = choice.effort ?: ""
    val accounts = choice.accounts
    val profile = choice.profile
    val pick = { fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit -> app.pickNew(workspace, fill) }
    // The chat, made once with the first message (web/src/NewChat.tsx → useEnsureChat), with what is picked here: the
    // core has it at once under the key it answers, its station makes it behind it; the next new chat starts here too.
    var made by remember(view.station) { mutableStateOf<String?>(null) }
    // Whether a message went out to it: until then, another choice (model, runtime, depth, account) is made anew.
    var sent by remember(view.station) { mutableStateOf(false) }
    LaunchedEffect(runtime, model, effort, profile) { if (!sent && !draft.starting) made = null }
    val ensure: suspend () -> String = {
        made ?: app.api(view.station).createNewChat().also { made = it }
    }
    val launchers = AttachLaunchers { app.upload(draft, view.station, it, scope) }
    val haze = host.haze
    // Leaving: the scene up out of view as it fades (140 ms, Ease.Arrive), the choices fading where they are (80 ms).
    val lift = with(androidx.compose.ui.platform.LocalDensity.current) { 32.dp.toPx() }
    val up = { if (leaving) Ease.Arrive.transform((host.leave.value / SCENE_LEAVE_MS).coerceIn(0f, 1f)) else 0f }
    val fade = { if (leaving) Ease.LeaveFade.transform((host.leave.value / 80f).coerceIn(0f, 1f)) else 0f }
    Column(Modifier.weight(1f).graphicsLayer { val a = up(); translationY = -lift * a; scaleX = 1f - 0.04f * a; scaleY = scaleX; alpha = 1f - a }.verticalScroll(rememberScrollState())) {
        Column(Modifier.fillMaxWidth().padding(start = 30.dp, end = 30.dp, top = 30.dp, bottom = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 230.dp)
            Text("想让 agent 做什么？", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, modifier = Modifier.padding(top = 6.dp))
            Text("说要做什么。它会在 ${view.name} 上用选好的模型开一个新会话。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            choice.problem?.let { Text(it, fontSize = 13.sp, color = if (choice.waiting) C.muted else C.red, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp)) }
            // No profile yet: adding one is the first step, here (the machine's own logins, when there are any, offered too).
            val overview = view.overview
            if (overview != null && choice.blocked == "profile") {
                Text("给 ${view.name} 添加一个 Profile。agent 用它来跑模型：一份订阅（Claude、ChatGPT），或者一个模型服务的 key。", fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
                Button("添加 Profile", primary = true) { app.push(Screen.NewProfile(view.station)) }
                Column(Modifier.fillMaxWidth().padding(top = 12.dp)) { MachineLoginOffers(view.station, overview, inset = 0.dp) }
            }
            // The machine's own Claude Code and Codex sessions, to go on with one (web/src/MachineSessions.tsx).
            if (overview != null && choice.blocked != "profile") MachineSessionsOffer(view)
        }
    }
    // Chosen anyway (it is the person's call), but said: what is sent waits for its quota.
    if (!leaving) choice.spent?.let { spent ->
        Text(
            spent,
            fontSize = 13.sp, color = C.ink,
            modifier = Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f)).padding(horizontal = 12.dp, vertical = 8.dp),
        )
    }
    // The choices, over the composer (the host's, a floating capsule as in a chat), with room for it below.
    Column(Modifier.fillMaxWidth().graphicsLayer { alpha = 1f - fade() }.padding(start = 10.dp, end = 10.dp, top = 8.dp)) {
        // Room above and below for the chips' shadows, which the scroll would cut.
        Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 2.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chooser(haze, { IconIn(Icons.Server, 14.dp, C.ink) }, view.name) { pickStation(app, stations, view.station, onStation) }
            if (runtime == null || model == null) {
                // Nothing to choose from: the chooser leads to where models are enabled.
                Chooser(haze, null, "没有可用模型 · 去勾选") { app.push(Screen.Station(view.station)) }
            } else {
                Chooser(haze, { MakerIcon(entry.maker, runtime, 14.dp) }, entry.name) {
                    pickModel(app, view, model) { m -> pick { put("model", m.model) } }
                }
                // The runtime only when the model runs on more than one.
                if (entry.runtimes.size > 1) Chooser(haze, { MakerIcon(null, runtime, 14.dp) }, RUNTIME_LABEL[runtime] ?: runtime) {
                    pickRuntime(app, entry.runtimes, runtime) { rt -> pick { put("runtime", rt) } }
                }
                Chooser(haze, null, effort.ifEmpty { "默认深度" }) {
                    pickEffort(app, choice.efforts, effort) { e -> pick { put("effort", e.ifEmpty { null }) } }
                }
                // Who runs it, only when there is a choice: the station's pick, or one account kept to.
                if (choice.pickAccount) Chooser(haze, null, profile?.let { p -> accounts.firstOrNull { it.id == p }?.name } ?: "自动分配") {
                    pickAccount(app, accounts, profile) { p -> pick { put("profile", p) } }
                }
            }
        }
    }
    // The composer's room: as tall as it was when the page began to leave (it changes shape under what leaves).
    val room = remember { mutableStateOf(0) }
    if (!leaving) room.value = host.composerHeight
    Spacer(Modifier.height(with(androidx.compose.ui.platform.LocalDensity.current) { room.value.toDp() }))
    if (leaving) return
    host.spec = ComposerSpec(
        station = view.station, here = null, draft = draft, placeholder = "做任何事",
        onPlus = { openAttach(app, launchers) },
        onSend = {
            // Its words stay where they were in the composer until the chat's page takes them (ChatHost.kt).
            host.sending(draft.text.trim(), carried = true)
            val taken = draft.take()
            draft.starting = true
            scope.launch {
                try {
                    val key = ensure()
                    // The message waits in the new chat (its outbox) until its station has made it; then it goes.
                    app.api(view.station).sendIn(key, taken.text, taken.files.mapNotNull { it.done }, taken.quotes.map { it.sent() })
                    sent = true
                    // The new item's page, by the key the core gave it: this page becomes it, its composer kept.
                    host.madeChat()
                    app.made(Screen.Chat(view.station, ChatOf.Session(key)))
                } catch (e: CoreException) {
                    // Nothing sent: the draft comes back.
                    host.notSent()
                    draft.restore(taken); draft.error = e.message
                } finally {
                    draft.starting = false
                }
            }
        },
    )
}

@Composable
private fun Chooser(haze: HazeState, leading: (@Composable () -> Unit)?, label: String, onClick: () -> Unit) {
    // The same glass as the composer's capsule under it.
    Row(
        Modifier.height(30.dp).floatingStill(RoundedCornerShape(15.dp)).clickable(onClick = onClick).padding(horizontal = 11.dp),
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
                PickRow(s.name, s.summary, checked = s.station == current, leading = { Buddy(s, 36) }) { onPick(s.id); app.sheet = null }
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

private fun pickAccount(app: AppState, accounts: List<RunnableProfile>, current: String?, onPick: (String?) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead("账号")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow("自动分配", "额度用完或登录失效时换一个", checked = current == null) { onPick(null); app.sheet = null }
            accounts.forEach { a -> PickRow(a.name, a.quotaLine?.text, checked = current == a.id) { onPick(a.id); app.sheet = null } }
        }
    }
}

// ── going on with a session the machine kept (web/src/MachineSessions.tsx) ──

/**
 * The offer, when the station's machine kept any sessions of its own Claude Code or Codex (a station from before them
 * offers none): a quiet line under the page's words; its list and a look at one before going on with it are sheets.
 */
@Composable
private fun MachineSessionsOffer(view: StationView) {
    val app = LocalApp.current
    var sessions by remember(view.station) { mutableStateOf<List<MachineSession>>(emptyList()) }
    LaunchedEffect(view.station) {
        sessions = try { app.api(view.station).machineSessions() } catch (_: CoreException) { emptyList() }
    }
    if (sessions.isEmpty()) return
    Row(
        Modifier.padding(top = 8.dp).clip(RoundedCornerShape(10.dp)).clickable { openMachineSessions(app, view, sessions) }.padding(horizontal = 10.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        IconIn(Icons.Monitor, 14.dp, C.muted)
        Text("接着本机终端里的会话", fontSize = 14.sp, color = C.muted)
    }
}

private fun openMachineSessions(app: AppState, view: StationView, sessions: List<MachineSession>) {
    app.sheet = SheetSpec(0.7f) {
        SheetGrab()
        SheetHead("接着本机的会话")
        Text(
            "这台机器上的 Claude Code 和 Codex 在终端里跑过的会话。点一个先看看内容，再决定要不要在它原来的目录里接着聊；终端里的那个不受影响。",
            fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp),
        )
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            sessions.forEach { s ->
                Row(
                    Modifier.fillMaxWidth().clickable { lookAtMachineSession(app, view, sessions, s) }.padding(horizontal = 20.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    MakerIcon(null, s.runtime, 18.dp)
                    Column(Modifier.weight(1f)) {
                        Text(s.title ?: s.first ?: "", fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(s.meta ?: "", fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (s.session != null) Text("已在 still.fail 里", fontSize = 12.sp, color = C.muted, maxLines = 1)
                }
            }
        }
    }
}

/** One of them looked at before going on with it: what was said in it, the latest at the bottom. */
private fun lookAtMachineSession(app: AppState, view: StationView, sessions: List<MachineSession>, s: MachineSession) {
    app.sheet = SheetSpec(0.85f) {
        val scope = rememberCoroutineScope()
        var shown by remember { mutableStateOf<Pair<List<MachineSaid>, Long>?>(null) }
        var error by remember { mutableStateOf<String?>(null) }
        var busy by remember { mutableStateOf(false) }
        LaunchedEffect(s.id) {
            try { shown = app.api(view.station).machineSession(s.runtime, s.id) } catch (e: CoreException) { error = e.message }
        }
        SheetGrab()
        SheetHead(s.title ?: s.first ?: "")
        Text(s.meta ?: "", fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 18.dp, end = 18.dp, bottom = 8.dp))
        val scroll = rememberScrollState()
        LaunchedEffect(shown) { if (shown != null) scroll.scrollTo(scroll.maxValue) }
        Column(Modifier.weight(1f).verticalScroll(scroll).padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            val got = shown
            when {
                got == null && error == null -> Text("正在读取…", fontSize = 13.sp, color = C.muted, modifier = Modifier.fillMaxWidth().padding(top = 40.dp), textAlign = TextAlign.Center)
                got != null -> {
                    val left = got.second - got.first.size
                    if (left > 0) Text("更早的 $left 条没有列出", fontSize = 12.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
                    val option = view.models.optionOf(s.model)
                    val name = option?.name ?: s.model ?: (RUNTIME_LABEL[s.runtime] ?: s.runtime)
                    got.first.forEach { m ->
                        if (m.person) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                            Text(m.text, fontSize = 15.sp, color = C.ink, modifier = Modifier.widthIn(max = 300.dp).clip(RoundedCornerShape(18.dp)).background(C.bubble).padding(horizontal = 14.dp, vertical = 9.dp))
                        } else Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                MakerIcon(option?.maker, s.runtime, 16.dp)
                                Text(name, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                            }
                            Markdown(m.text)
                        }
                    }
                }
            }
        }
        error?.let { Text(it, fontSize = 13.sp, color = C.red, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp)) }
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 10.dp, bottom = 24.dp), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button("返回", primary = false) { openMachineSessions(app, view, sessions) }
            Button(if (s.session != null) "打开它的对话" else "接着这个会话", primary = true, busy = busy) {
                busy = true; error = null
                scope.launch {
                    try {
                        val key = app.api(view.station).continueMachineSession(s.runtime, s.id)
                        app.replace(Screen.Chat(view.station, ChatOf.Session(key)))
                    } catch (e: CoreException) { error = e.message } finally { busy = false }
                }
            }
        }
    }
}
