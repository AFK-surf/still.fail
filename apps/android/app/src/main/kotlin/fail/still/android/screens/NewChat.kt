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
import fail.still.android.data.Quota
import fail.still.android.data.RunnableProfile
import fail.still.android.data.WorkspaceEntry
import fail.still.android.ui.Markdown
import androidx.compose.foundation.layout.widthIn
import androidx.compose.ui.text.style.TextOverflow
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
import kotlinx.coroutines.launch

/** What the new chat runs on; kept per station for next time. `profile`: the account kept to ("" for the station's pick). */
private data class Choice(val runtime: String, val model: String, val effort: String, val profile: String = "")

private fun AppState.lastChoice(station: String): Choice? =
    strings("newChat/$station").takeIf { it.size >= 3 }?.let { Choice(it[0], it[1], it[2], it.getOrNull(3)?.takeIf { p -> p != "-" } ?: "") }

private fun AppState.keepChoice(station: String, c: Choice) {
    setStrings("newChat/$station", listOf(c.runtime, c.model, c.effort.ifEmpty { "-" }, c.profile.ifEmpty { "-" }))
}

/** The station a workspace's last chat was started on (or last picked there); `newChat.last` is what the app kept before, for any workspace. */
private fun AppState.lastStation(scope: String): String? =
    strings("newChat.lastIn/$scope").firstOrNull() ?: strings("newChat.last").firstOrNull()

private fun AppState.keepStation(scope: String, station: String) {
    setStrings("newChat.lastIn/$scope", listOf(station))
    setStrings("newChat.last", listOf(station))
}

/**
 * The new chat, above its host's composer (ChatHost.kt). `leaving`: it has become its chat, which is under it now; only
 * its scene is drawn, going (up out of view, its choices fading where they are).
 */
@Composable
fun NewChatScreen(current: WorkspaceEntry, host: Host, leaving: Boolean = false) {
    val app = LocalApp.current
    val scope = current.workspace.id
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(scope))
    val all = stations.value
    // The station last started on (or picked) in this workspace.
    var picked by remember(scope) { mutableStateOf(app.lastStation(scope)) }
    val onStation = { station: String -> picked = station; app.keepStation(scope, station) }
    // What the composer frosts, under it: this page (its own paper) until it leaves.
    Column(if (leaving) Modifier.fillMaxSize() else Modifier.fillMaxSize().hazeSource(host.haze).background(C.bg)) {
        // Gone at once as it leaves (the chat has its own bar), its room kept so the scene leaves from where it was.
        Box(Modifier.alpha(if (leaving) 0f else 1f)) { NavBar("取消", app::pop, "新对话") }
        val online = all?.filter { it.online }.orEmpty()
        val view = online.firstOrNull { it.station == picked } ?: online.firstOrNull()
        when {
            all == null -> Loading(stations.error?.message ?: "正在读取 station…")
            all.isEmpty() -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) { FirstStation(current) }
            view == null -> Column(Modifier.fillMaxSize().padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
                Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 240.dp)
                Text("没有在线的 station", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text("在一台机器上打开 still.fail，它就会连上这个 workspace。", fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
            }
            else -> androidx.compose.runtime.key(view.station) { NewChatOn(scope, view, online, onStation, host, leaving) }
        }
        // No composer without a station to write to.
        if (view == null && !leaving) host.spec = null
    }
}

@Composable
private fun androidx.compose.foundation.layout.ColumnScope.NewChatOn(workspace: String, view: StationView, stations: List<StationView>, onStation: (String) -> Unit, host: Host, leaving: Boolean) {
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
    // Who runs it: kept to an account only while that one still runs the model there; else the station's pick.
    val accounts = runtime?.let { entry?.accounts?.get(it) }.orEmpty()
    val profile = choice?.profile?.takeIf { p -> p.isNotEmpty() && accounts.any { it.id == p } }
    val pick = { next: Choice -> choice = next; app.keepChoice(view.station, next) }
    // The model list is what a profile's check found; profiles not checked since the station started are checked now, once.
    val profiles = view.overview?.profiles.orEmpty()
    val checked = remember(view.station) { mutableSetOf<String>() }
    LaunchedEffect(profiles) {
        for (p in profiles) if (p.check == null && checked.add(p.id)) launch { try { app.api(view.station).checkProfile(p.id) } catch (_: CoreException) {} }
    }
    // The chat, made once with the first message (web/src/NewChat.tsx → useEnsureChat): the core has it at once under
    // the key it answers, its station makes it behind it; the next new chat starts on this station too.
    var made by remember(view.station) { mutableStateOf<String?>(null) }
    // Whether a message went out to it: until then, another choice (model, runtime, depth, account) is made anew.
    var sent by remember(view.station) { mutableStateOf(false) }
    LaunchedEffect(runtime, model, effort, profile) { if (!sent && !draft.starting) made = null }
    val ensure: suspend () -> String = {
        made ?: run {
            val m = model ?: throw CoreException("no_model", "先在 Profile 里启用模型", null)
            app.api(view.station).createChat(runtime!!, m, effort.ifEmpty { null }, profile).also {
                made = it
                app.keepStation(workspace, view.station)
            }
        }
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
            val problem = when {
                view.overview == null -> "正在读取 ${view.name} 的 Profile…"
                profiles.isEmpty() -> null
                view.models.isEmpty() -> "这台 station 的 Profile 都还没有启用模型。点下面的「去勾选」，勾选可以用的模型。"
                else -> null
            }
            if (problem != null) Text(problem, fontSize = 13.sp, color = if (view.overview == null) C.muted else C.red, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
            // No profile yet: adding one is the first step, here (the machine's own logins, when there are any, offered too).
            val overview = view.overview
            if (overview != null && profiles.isEmpty()) {
                Text("给 ${view.name} 添加一个 Profile。agent 用它来跑模型：一份订阅（Claude、ChatGPT），或者一个模型服务的 key。", fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
                Button("添加 Profile", primary = true) { app.push(Screen.NewProfile(view.station)) }
                Column(Modifier.fillMaxWidth().padding(top = 12.dp)) { MachineLoginOffers(view.station, overview, inset = 0.dp) }
            }
            // The machine's own Claude Code and Codex sessions, to go on with one (web/src/MachineSessions.tsx).
            if (overview != null && profiles.isNotEmpty()) MachineSessionsOffer(view)
        }
    }
    // Chosen anyway (it is the person's call), but said: what is sent waits for its quota.
    if (!leaving) entry?.spent?.let { s ->
        Text(
            "${entry.name} 能用的账号额度都用完了" + (s.back?.let { "，$it" } ?: "") + "。现在发的消息要等额度恢复才会有回复；也可以换一个模型。",
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
                val now = Choice(runtime, model, effort, profile ?: "")
                Chooser(haze, { MakerIcon(entry.maker, runtime, 14.dp) }, entry.name) {
                    pickModel(app, view, model) { m -> val rt = m.runtimes.firstOrNull { it == runtime } ?: m.runtimes.first(); pick(now.copy(runtime = rt, model = m.model, effort = if (rt != runtime) "" else effort)) }
                }
                // The runtime only when the model runs on more than one.
                if (entry.runtimes.size > 1) Chooser(haze, { MakerIcon(null, runtime, 14.dp) }, RUNTIME_LABEL[runtime] ?: runtime) {
                    pickRuntime(app, entry.runtimes, runtime) { rt -> pick(now.copy(runtime = rt, effort = "")) }
                }
                Chooser(haze, null, effort.ifEmpty { "默认深度" }) {
                    pickEffort(app, efforts, effort) { e -> pick(now.copy(effort = e)) }
                }
                // Who runs it, only when there is a choice: the station's pick, or one account kept to.
                if (accounts.size > 1) Chooser(haze, null, profile?.let { p -> accounts.firstOrNull { it.id == p }?.name } ?: "自动分配") {
                    pickAccount(app, accounts, profile) { p -> pick(now.copy(profile = p ?: "")) }
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

private fun pickAccount(app: AppState, accounts: List<RunnableProfile>, current: String?, onPick: (String?) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead("账号")
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow("自动分配", "额度用完或登录失效时换一个", checked = current == null) { onPick(null); app.sheet = null }
            accounts.forEach { a -> PickRow(a.name, quotaLine(a.quota), checked = current == a.id) { onPick(a.id); app.sheet = null } }
        }
    }
}

/** What is left of an account's allowance, in a few words (web/src/ModelTriple.tsx → quotaLine). */
private fun quotaLine(quota: Quota?): String? {
    if (quota == null) return null
    if (quota.state != "ok" || quota.windows.isEmpty()) return quota.detail
    val low = quota.windows.filter { it.level != "ok" }.minByOrNull { it.left }
    if (low != null) return "${low.label}只剩 ${low.left}%"
    return quota.windows.joinToString(" · ") { "${it.label} ${it.left}%" }
}

// ── going on with a session the machine kept (web/src/MachineSessions.tsx) ──

/** The directory as people know it: the home directory as ~. */
private fun shortPath(path: String) = path.replace(Regex("^/(Users|home)/[^/]+(?=/|$)"), "~")

private fun sessionMeta(s: MachineSession): String {
    val secs = (System.currentTimeMillis() - s.updatedAt) / 1000
    val ago = when {
        secs < 60 -> "刚刚"
        secs < 3600 -> "${secs / 60} 分钟前"
        secs < 86400 -> "${secs / 3600} 小时前"
        secs < 2 * 86400 -> "昨天"
        else -> "${secs / 86400} 天前"
    }
    return "${RUNTIME_LABEL[s.runtime] ?: s.runtime} · ${shortPath(s.cwd)} · $ago"
}

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
                        Text(sessionMeta(s), fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
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
        Text(sessionMeta(s), fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 18.dp, end = 18.dp, bottom = 8.dp))
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
