// A new chat rises from the bottom: say what to do, having picked where it
// runs (station), on what (model) and how hard it thinks. The first message
// (or file) makes the session on that station; then the page becomes the chat.
package fail.still.android.screens

import fail.still.android.data.t
import fail.still.android.BuildConfig
import fail.still.android.ui.ComposerInset
import fail.still.android.ui.ComposerCorner
import androidx.compose.foundation.interaction.MutableInteractionSource
import fail.still.android.ui.floating
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.graphics.compositeOver
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
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.selected
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
import fail.still.android.data.PickView
import androidx.compose.foundation.layout.fillMaxHeight
import fail.still.android.ui.ProviderMark
import fail.still.android.data.NewChatView
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.data.errorText
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.StationMark
import fail.still.android.ui.hasStationMark
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

/** Picks for a new chat in a scope (`station`: its id; the core keeps them, client/core-ts/src/choose.ts): each given changes only that. */
private fun AppState.pickNew(scope: String, fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit) {
    this.scope.launch { try { core.call("newChat.pick", buildJsonObject { put("scope", scope); fill() }) } catch (e: CoreException) { toast = t("android-chat.pick.failed", "error" to errorText(e)) } }
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
    Column(Modifier.fillMaxSize().then(if (leaving) Modifier else Modifier.background(C.bg))) {
        // Gone at once as it leaves (the chat has its own bar), its room kept so the scene leaves from where it was.
        Box(Modifier.alpha(if (leaving) 0f else 1f)) { NavBar(t("common.cancel"), app::pop, t("android-chat.new.title")) }
        val view = choice?.station
        val online = choice?.stations
        when {
            choice == null || online == null -> Loading(choice?.error ?: chat.error?.message ?: t("android-chat.new.loading"))
            !choice.any -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) { FirstStation(current) }
            view == null -> Column(Modifier.fillMaxSize().padding(30.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp, Alignment.CenterVertically)) {
                Illustration(R.drawable.illus_station_offline, R.drawable.illus_station_offline_dark, 240.dp)
                Text(t("android-chat.new.offline.title"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                Text(t("android-chat.new.offline.text", "app" to BuildConfig.APP_NAME), fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
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
    val profile = choice.profile
    // The chat, made once with the first message (web/src/NewChat.tsx → useEnsureChat), with what is picked here: the
    // core has it at once under the key it answers, its station makes it behind it; the next new chat starts here too.
    var made by remember(view.station) { mutableStateOf<String?>(null) }
    // Whether a message went out to it: until then, another choice (model, runtime, depth, account) is made anew.
    var sent by remember(view.station) { mutableStateOf(false) }
    LaunchedEffect(runtime, model, effort, profile, choice.fast) { if (!sent && !draft.starting) made = null }
    val ensure: suspend () -> String = {
        made ?: app.api(view.station).createNewChat().also { made = it }
    }
    val launchers = AttachLaunchers { app.upload(draft, view.station, it, scope) }
    val haze = host.haze
    // Leaving: the scene up out of view as it fades (140 ms, Ease.Arrive), the choices fading where they are (80 ms).
    val lift = with(androidx.compose.ui.platform.LocalDensity.current) { 32.dp.toPx() }
    val up = { if (leaving) Ease.Arrive.transform((host.leave.value / SCENE_LEAVE_MS).coerceIn(0f, 1f)) else 0f }
    val fade = { if (leaving) Ease.LeaveFade.transform((host.leave.value / 80f).coerceIn(0f, 1f)) else 0f }
    // What stands at the foot (the choices, the composer's room) is over the scene, which runs on under them: they frost it.
    var foot by remember { mutableStateOf(0) }
    Box(Modifier.weight(1f).fillMaxWidth()) {
        // What the composer and the choices frost: the scene (its own paper) until it leaves.
        // Keep the source attached through the hand-off: the chat's source is only ready after layout.
        // Removing it here leaves the composer's glass without a recorded source for one frame.
        Box(Modifier.matchParentSize().hazeSource(host.haze).then(if (leaving) Modifier else Modifier.background(C.bg))) {
            Column(Modifier.fillMaxSize().graphicsLayer { val a = up(); translationY = -lift * a; scaleX = 1f - 0.04f * a; scaleY = scaleX; alpha = 1f - a }.verticalScroll(rememberScrollState())) {
                Column(Modifier.fillMaxWidth().padding(start = 30.dp, end = 30.dp, top = 30.dp, bottom = 10.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Illustration(R.drawable.illus_new_chat, R.drawable.illus_new_chat_dark, 230.dp)
                    Text(t("android-chat.new.heading"), fontSize = 22.sp, fontWeight = FontWeight.Bold, color = C.ink, modifier = Modifier.padding(top = 6.dp))
                    Text(t("android-chat.new.sub", "station" to view.name), fontSize = 14.sp, color = C.muted, textAlign = TextAlign.Center)
                    choice.frequent?.takeIf { it.isNotEmpty() }?.let { combos ->
                        Column(Modifier.fillMaxWidth().padding(vertical = 12.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(t("android-chat.new.frequent"), fontSize = 12.sp, color = C.muted)
                            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                combos.forEach { combo ->
                                    Text(combo.label, fontSize = 13.sp, lineHeight = 18.sp, color = if (combo.selected) C.ink else C.muted,
                                        modifier = Modifier.semantics { selected = combo.selected }.clip(RoundedCornerShape(18.dp))
                                            .background(C.ink.copy(alpha = if (combo.selected) 0.10f else 0.04f))
                                            .clickable(enabled = !leaving) { app.pickNew(workspace) {
                                                put("model", combo.model); put("runtime", combo.runtime); put("effort", combo.effort)
                                            } }.padding(horizontal = 10.dp, vertical = 8.dp))
                                }
                            }
                        }
                    }
                    choice.problem?.let { Text(it, fontSize = 13.sp, color = if (choice.waiting) C.muted else C.red, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp)) }
                    // No profile yet: adding one is the first step, here (the machine's own logins, when there are any, offered too).
                    val overview = view.overview
                    if (overview != null && choice.blocked == "profile") {
                        Text(t("android-chat.new.profile.text", "station" to view.name), fontSize = 13.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp))
                        Button(t("android-chat.new.profile.add"), primary = true) { app.push(Screen.NewProfile(view.station)) }
                        Column(Modifier.fillMaxWidth().padding(top = 12.dp)) { MachineLoginOffers(view.station, overview, inset = 0.dp) }
                    }
                    // The machine's own Claude Code and Codex sessions, to go on with one (web/src/MachineSessions.tsx).
                    if (overview != null && choice.blocked != "profile") MachineSessionsOffer(view)
                }
                // Its end clear of what stands at the foot.
                Spacer(Modifier.height(with(androidx.compose.ui.platform.LocalDensity.current) { foot.toDp() }))
            }
        }
        Column(Modifier.align(Alignment.BottomCenter).fillMaxWidth().onSizeChanged { foot = it.height }) {
            // Chosen anyway (it is the person's call), but said: what is sent waits for its quota.
            if (!leaving) choice.spent?.let { spent ->
                Text(
                    spent,
                    fontSize = 13.sp, color = C.ink,
                    modifier = Modifier.padding(horizontal = 12.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.warn.copy(alpha = 0.12f).compositeOver(C.bg)).padding(horizontal = 12.dp, vertical = 8.dp),
                )
            }
            // The choices, over the composer (the host's, a floating capsule as in a chat), with room for it below.
            Column(Modifier.fillMaxWidth().graphicsLayer { alpha = 1f - fade() }.padding(start = 10.dp, end = 10.dp, top = 8.dp)) {
                // One line that fits the width, no scrolling: where it runs, and what it runs on as one control (web/src/ModelTriple.tsx),
                // cut short rather than pushed off the edge. Room above and below for the chips' shadows.
                Row(Modifier.fillMaxWidth().padding(horizontal = 2.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Chooser(haze, { StationMark(view.emoji, view.icon, 14.dp, C.ink, none = Icons.Server) }, view.name, Modifier.widthIn(max = 128.dp)) { pickStation(app, stations, view.station, onStation) }
                    val p = choice.pick
                    if (runtime == null || model == null || p == null || p.options.isEmpty()) {
                        // Nothing to choose from: the chooser leads to where models are enabled.
                        Chooser(haze, null, t("android-chat.new.noModels"), Modifier.weight(1f, fill = false)) { app.push(Screen.Profiles()) }
                    } else {
                        Chooser(haze, { MakerIcon(p.valueOption?.maker ?: entry.maker, runtime, 14.dp) }, tripleLabel(p), Modifier.weight(1f, fill = false), chevron = true) {
                            openRunPicker(app, view.station)
                        }
                    }
                }
            }
            // The composer's room: as tall as it was when the page began to leave (it changes shape under what leaves).
            val room = remember { mutableStateOf(0) }
            if (!leaving) room.value = host.composerHeight
            Spacer(Modifier.height(with(androidx.compose.ui.platform.LocalDensity.current) { room.value.toDp() }))
        }
    }
    if (leaving) return
    host.spec = ComposerSpec(
        station = view.station, here = null, draft = draft, placeholder = t("android-chat.new.placeholder"),
        onPlus = { openAttach(app, launchers) },
        onSend = {
            // Its words stay where they were in the composer until the chat's page takes them (ChatHost.kt).
            host.sending(draft.text.trim(), carried = true, files = draft.files.toList())
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
private fun Chooser(haze: HazeState, leading: (@Composable () -> Unit)?, label: String, modifier: Modifier = Modifier, chevron: Boolean = false, onClick: () -> Unit) {
    // The same glass as the composer's capsule under it, over the scene running on under both.
    Row(
        modifier.height(30.dp).floating(haze, RoundedCornerShape(15.dp)).clickable(onClick = onClick).padding(horizontal = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        leading?.invoke()
        Text(label, fontSize = 13.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
        if (chevron) IconIn(Icons.ChevronDown, 12.dp, C.muted)
    }
}

private fun pickStation(app: AppState, stations: List<StationView>, current: String, onPick: (String) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead(t("android-chat.new.station.pick"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            stations.forEach { s ->
                PickRow(s.name, s.summary, checked = s.station == current, leading = { Buddy(s, 36) }, mark = if (hasStationMark(s.emoji, s.icon)) ({ StationMark(s.emoji, s.icon, 15.dp, C.ink) }) else null) { onPick(s.id); app.sheet = null }
            }
        }
    }
}

/** What the control says: the model, the runtime where there is a choice, how hard it thinks, and who runs it when that matters. */
private fun tripleLabel(p: PickView): String {
    val v = p.value
    return listOfNotNull(
        p.valueOption?.name ?: v.model ?: t("android-chat.pick.model"),
        if (!p.runtimeFixed && (p.valueOption?.runtimes?.size ?: 0) > 1) RUNTIME_LABEL[v.runtime] ?: v.runtime else null,
        v.effort ?: t("android-chat.pick.effort.default"),
        p.fastText,
        p.account?.text,
    ).joinToString(" · ")
}

/**
 * What a new chat runs on, as the PC's panel picks it (web/src/ModelTriple.tsx), in a sheet: the models in a column,
 * the runtime and how hard it thinks beside them, who runs it in the foot (a list of its own, and back). Picks are a
 * draft (`pick.set`) until 确定 (`pick.save`); closed otherwise, nothing changes.
 */
private fun openRunPicker(app: AppState, station: String) {
    app.sheet = SheetSpec(0.66f) {
        val scope = rememberCoroutineScope()
        val topic by rememberTopic<PickView>(app.core, Topics.pick(station, "new"))
        val set = { fill: kotlinx.serialization.json.JsonObjectBuilder.() -> Unit -> scope.launch { try { app.api(station).pickSet("new", fill) } catch (e: CoreException) { app.toast = t("android-chat.pick.failed", "error" to errorText(e)) } }; Unit }
        // Picked from what it runs on now, each time it is opened.
        LaunchedEffect(Unit) { set { put("open", true) } }
        var accounts by remember { mutableStateOf(false) }
        androidx.activity.compose.BackHandler(enabled = accounts) { accounts = false }
        val v = topic.value
        SheetGrab()
        if (accounts) {
            Row(Modifier.fillMaxWidth().padding(start = 8.dp, end = 18.dp, top = 4.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp).clip(RoundedCornerShape(18.dp)).clickable { accounts = false }, contentAlignment = Alignment.Center) { IconIn(Icons.ChevronLeft, 20.dp, C.ink) }
                Text(t("android-chat.new.account"), fontSize = 17.sp, fontWeight = FontWeight.Bold, color = C.ink)
            }
        } else SheetHead(t("android-chat.new.model"))
        if (v == null) return@SheetSpec Loading(topic.error?.message ?: t("android-chat.reading"))
        val draft = v.draft
        if (accounts) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 12.dp).windowInsetsPadding(WindowInsets.navigationBars)) {
                v.dropped?.let { Text(it, fontSize = 12.sp, color = C.warn, modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp)) }
                CascadeOption(t("android-chat.new.auto"), v.autoNote, draft.profile == null) { set { put("profile", null as String?) }; accounts = false }
                v.accounts.forEach { a ->
                    CascadeOption(a.name, a.quotaLine?.text, draft.profile == a.id, subColor = if (a.quotaLine?.level != null) C.warn else C.muted,
                        leading = { ProviderMark(a.runtime ?: draft.runtime, a.kind, 16.dp, a.mark) }) { set { put("profile", a.id) }; accounts = false }
                }
            }
            return@SheetSpec
        }
        // Side by side, each scrolling on its own: the models (by series, in the core's order), and what goes with the one picked.
        Row(Modifier.weight(1f).fillMaxWidth().padding(horizontal = 10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val groups = v.options.groupBy { it.family ?: t("android-chat.pick.family.other") }
            Column(Modifier.weight(1.35f).fillMaxHeight().verticalScroll(rememberScrollState())) {
                groups.forEach { (who, list) ->
                    if (groups.size > 1) CascadeLabel(who)
                    list.forEach { o ->
                        CascadeOption(o.name, o.spent?.text, v.option == o.model, leading = { MakerIcon(o.maker, o.runtimes.firstOrNull() ?: draft.runtime, 16.dp) }) { set { put("model", o.model) } }
                    }
                }
                Spacer(Modifier.height(12.dp))
            }
            Column(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(14.dp)).background(C.surface).verticalScroll(rememberScrollState()).padding(4.dp)) {
                if (v.runtimes.isNotEmpty()) {
                    CascadeLabel(t("android-chat.new.runtime"))
                    v.runtimes.forEach { r -> CascadeOption(RUNTIME_LABEL[r] ?: r, null, draft.runtime == r, leading = { MakerIcon(null, r, 16.dp) }) { set { put("runtime", r) } } }
                }
                CascadeLabel(t("android-chat.new.effort"))
                (listOf<String?>(null) + v.efforts).forEach { e -> CascadeOption(e ?: t("android-chat.pick.default"), null, draft.effort == e) { set { put("effort", e) } } }
                if (v.fastAvailable == true) {
                    CascadeLabel(t("android-chat.new.speed"))
                    listOf<Boolean?>(null, false, true).forEach { fast ->
                        CascadeOption(when (fast) { true -> "Fast"; false -> t("android-chat.pick.speed.standard"); null -> t("android-chat.pick.speed.follow") }, if (fast == true) t("android-chat.new.fast.note") else null, draft.fast == fast) { set { put("fast", fast) } }
                    }
                }
            }
        }
        // The foot: who runs it (the station's pick, most of the time), and 确定.
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).padding(start = 10.dp, end = 14.dp, top = 10.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Row(
                Modifier.weight(1f).clip(RoundedCornerShape(12.dp)).clickable { accounts = true }.padding(horizontal = 10.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(t("android-chat.new.account"), fontSize = 14.sp, color = C.muted)
                Text(v.who, fontSize = 14.sp, color = if (v.whoLevel != null) C.warn else C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                IconIn(Icons.ChevronRight, 14.dp, C.muted)
            }
            // Saving: a spinner in it, the sheet open until the core has it (closed then, unless another took its place).
            val saving = app.isDoing("pick.save", "station" to station, "of" to "new")
            Row(
                Modifier.clip(RoundedCornerShape(19.dp)).background(if (v.changed) C.ink else C.chip).clickable(enabled = v.option != null && !saving) {
                    if (!v.changed) { app.sheet = null; return@clickable }
                    val sheet = app.sheet
                    app.scope.launch {
                        try { app.api(station).pickSave("new"); if (app.sheet === sheet) app.sheet = null }
                        catch (err: CoreException) { app.toast = t("android-chat.save.failed", "error" to errorText(err)) }
                    }
                }.padding(horizontal = 22.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (saving) androidx.compose.material3.CircularProgressIndicator(Modifier.size(14.dp), color = C.bg, strokeWidth = 1.5.dp)
                Text(if (v.changed) t("android-chat.new.confirm") else t("android-chat.new.unchanged"), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (v.changed) C.bg else C.ink)
            }
        }
    }
}

@Composable
private fun CascadeLabel(text: String) = Text(text, fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(start = 10.dp, top = 10.dp, bottom = 2.dp))

/** A choice in a column of the picker: the chosen one on the accent's pale ground, its words in the accent and bold. */
@Composable
private fun CascadeOption(label: String, sub: String?, checked: Boolean, subColor: androidx.compose.ui.graphics.Color = C.muted, leading: (@Composable () -> Unit)? = null, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(if (checked) C.accentBg else androidx.compose.ui.graphics.Color.Transparent).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        leading?.invoke()
        Column(Modifier.weight(1f)) {
            Text(label, fontSize = 15.sp, color = if (checked) C.accentInk else C.ink, fontWeight = if (checked) FontWeight.SemiBold else FontWeight.Normal, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (sub != null) Text(sub, fontSize = 12.sp, color = subColor, maxLines = 2, overflow = TextOverflow.Ellipsis)
        }
        if (checked) IconIn(Icons.Check, 14.dp, C.accent)
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
        Text(t("android-chat.new.machine.offer", "station" to view.name.ifEmpty { t("android-chat.new.machine.here") }), fontSize = 14.sp, color = C.muted)
    }
}

private fun openMachineSessions(app: AppState, view: StationView, sessions: List<MachineSession>) {
    app.sheet = SheetSpec(0.7f) {
        SheetGrab()
        SheetHead(t("android-chat.new.machine.title", "station" to view.name.ifEmpty { t("android-chat.new.machine.here") }))
        Text(
            t("android-chat.new.machine.text"),
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
                    if (s.session != null) Text(t("android-chat.new.machine.inApp", "app" to BuildConfig.APP_NAME), fontSize = 12.sp, color = C.muted, maxLines = 1)
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
        val busy = app.isDoing("machineSessions.continue", "station" to view.station, "id" to s.id)
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
                got == null && error == null -> Text(t("android-chat.reading"), fontSize = 13.sp, color = C.muted, modifier = Modifier.fillMaxWidth().padding(top = 40.dp), textAlign = TextAlign.Center)
                got != null -> {
                    val left = got.second - got.first.size
                    if (left > 0) Text(t("android-chat.new.machine.more", "n" to left), fontSize = 12.sp, color = C.muted, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
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
            Button(t("common.back"), primary = false) { openMachineSessions(app, view, sessions) }
            Button(if (s.session != null) t("android-chat.new.machine.open") else t("android-chat.new.machine.continue"), primary = true, busy = busy) {
                error = null
                scope.launch {
                    try {
                        val key = app.api(view.station).continueMachineSession(s.runtime, s.id)
                        app.replace(Screen.Chat(view.station, ChatOf.Session(key)))
                    } catch (e: CoreException) { error = e.message }
                }
            }
        }
    }
}
