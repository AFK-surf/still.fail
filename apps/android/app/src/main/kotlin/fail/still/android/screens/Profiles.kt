// Profiles (as the narrow web's web/src/mobile/Profiles.tsx, from the desktop's pages/Accounts.tsx): every station's in
// one list, a profile's page
// (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its key or
// variables; renaming, checking and deleting under "…"), and a new one.
package fail.still.android.screens

import fail.still.android.BuildConfig
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.ACCESS_LABEL
import fail.still.android.data.KEYED
import fail.still.android.data.LoginJob
import fail.still.android.data.MachineLogin
import fail.still.android.data.Overview
import fail.still.android.data.PROFILE_CHOICES
import fail.still.android.data.Profile
import fail.still.android.data.Quota
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.data.errorText
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.LargeTitle
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.NavBar
import fail.still.android.ui.NavButton
import fail.still.android.ui.ProviderMark
import fail.still.android.ui.QuotaDials
import fail.still.android.ui.QuotaRings
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

private val SIGNING_IN = setOf("starting", "needs_code", "needs_approval", "verifying")

/** A check's tone as a colour (the core's: accent | green | blue | red | neutral). */
@Composable
internal fun toneColor(tone: String): Color = when (tone) { "green" -> C.green; "red" -> C.red; "blue" -> C.blue; "accent" -> C.accent; else -> C.muted }

/** A state as the pages say it: a small dot in its colour, then its words. */
@Composable
internal fun StateDot(color: Color, size: androidx.compose.ui.unit.Dp = 7.dp) = Box(Modifier.size(size).clip(CircleShape).background(color))

/** Why an allowance could not be read (an account its provider refuses, a sign-in gone stale), in the provider's words. */
internal fun quotaTrouble(quota: Quota?): String? = quota?.takeIf { it.state == "blocked" || it.state == "unavailable" }?.detail?.ifBlank { null }

/** The runtime a machine login is of, by name. */
private val MACHINE_RUNTIME = mapOf("claude" to "Claude Code", "codex" to "Codex")

/**
 * Every station's profiles on one page, from settings (SettingsHome.kt), as the narrow web's ProfilesScreen: each station
 * under its name, what can be added there (a profile, the machine's own logins) with it; one offline says so.
 */
@Composable
fun ProfilesScreen(current: WorkspaceEntry, only: String? = null) {
    val app = LocalApp.current
    val topic by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    // From a station's page: that station's only, back to it.
    val stations = topic.value?.let { all -> if (only == null) all else all.filter { it.station == only } }
    val one = if (only != null) stations?.firstOrNull() else null
    val online = stations.orEmpty().filter { it.online }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars)) {
        TopBack(one?.name ?: "设置", app::pop, trailing = if (online.isNotEmpty()) ({
            NavButton(Icons.Plus, {
                if (online.size == 1) app.push(Screen.NewProfile(online[0].station))
                else openPickStation(app, "添加 Profile", online) { app.push(Screen.NewProfile(it.station)) }
            }, 20.dp)
        }) else null)
        LargeTitle(one?.let { "${it.name} 上的" } ?: "", "Profile")
        PageNote("agent 跑模型用的账号。需查看的账号排在各 station 前面，点进去查看原因和处理办法。")
        if (stations == null) Text(topic.error?.message ?: "正在读取 station…", fontSize = 14.sp, color = C.muted, modifier = Modifier.padding(20.dp))
        else stations.forEach { s ->
            if (one == null) SectionHeader(if (s.online) s.name else "${s.name} · 离线", start = 24.dp)
            val overview = s.overview
            ListCard {
                if (overview == null) ListRow { Text(if (s.online) "正在读取…" else "station 离线，读不到它的 Profile", fontSize = 15.sp, color = C.muted) }
                else if (overview.profiles.isEmpty()) ListRow { Text("这台机器还没有 Profile", fontSize = 15.sp, color = C.muted) }
                else overview.profiles.forEach { ProfileRow(s.station, it) }
            }
            // The machine's own logins not used yet, each offered as a profile.
            if (s.online && overview != null) MachineLoginOffers(s.station, overview)
        }
        Spacer(Modifier.height(30.dp))
    }
}

/** Where something is added: one of the stations online, picked in a sheet. */
fun openPickStation(app: AppState, title: String, stations: List<StationView>, go: (StationView) -> Unit) {
    app.sheet = SheetSpec(0.5f) {
        SheetGrab()
        SheetHead(title)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            Text("加在哪台 station 上", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
            stations.forEach { s -> PickRow(s.name) { app.sheet = null; go(s) } }
        }
    }
}

/**
 * A profile in the list of profiles: whether it works (a dot before its name, its state in words, why when its provider
 * refuses it), what it is, how many of its models are enabled, and its allowance; its page picks them.
 */
@Composable
internal fun ProfileRow(station: String, p: Profile) {
    val app = LocalApp.current
    val trouble = quotaTrouble(p.quota)
    ListRow(onClick = { app.push(Screen.Profile(station, p.id)) }) {
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                PresenceDot(toneDot(p.checkTone))
                Text(p.name, fontSize = 15.sp, color = C.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(listOf(p.checkText, if (p.machine == true) "本机登录" else ACCESS_LABEL[p.access.kind] ?: p.access.kind, p.modelsText).joinToString(" · "),
                fontSize = 13.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (p.trouble != null) {
                Text("${p.trouble.title} · ${p.trouble.detail}", fontSize = 13.sp, color = C.muted)
                Text("查看处理办法", fontSize = 13.sp, color = C.accent)
            } else trouble?.let { Text(it, fontSize = 13.sp, color = C.muted) }
        }
        val calls = setOf("profile.check", "profile.quota")
        DoingMark(app.isDoing(calls, "station" to station, "id" to p.id), app.failedOf(calls, "station" to station, "id" to p.id))
        QuotaRings(p.quota)
        IconIn(Icons.ChevronRight, 14.dp, C.subtle)
    }
}

@Composable
fun ProfileScreen(current: WorkspaceEntry, address: String, id: String) {
    val app = LocalApp.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    val p = s?.overview?.profiles?.firstOrNull { it.id == id }
    if (s == null || p == null) return Column(Modifier.fillMaxSize()) {
        NavBar(s?.name ?: "Station", app::pop, "Profile")
        Loading(stations.error?.message ?: if (s?.overview != null) "没有这个 Profile。" else "正在读取…")
    }
    val api = app.api(address)
    val setModels = { models: List<String> ->
        app.act("保存模型") { api.setModels(p.id, models) }
    }
    // The switch flipped and not answered yet: shown flipped, with a spinner.
    var flipping by remember { mutableStateOf<Boolean?>(null) }
    val users = p.usedBy.mapNotNull { u -> s.overview?.connects?.firstOrNull { it.id == u } }
    val kind = p.access.kind
    Column(Modifier.fillMaxSize()) {
        NavBar(s.name, app::pop, p.name, sub = { Text(if (p.machine == true) "本机登录" else ACCESS_LABEL[kind] ?: kind, fontSize = 11.sp, color = C.muted) },
            trailing = { NavButton(Icons.More, { openProfileMenu(app, address, p) }) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            Card {
                Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ProviderMark(p.runtime, kind, 26.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            TonePill(p.checkText, p.checkTone)
                            // Its check or allowance refresh (asked from its menu, gone) failed a moment ago: a red mark, a tap says why.
                            if (app.isDoing("profile.check", "station" to address, "id" to p.id)) { Spinner(12.dp); Text("正在检查…", fontSize = 12.sp, color = C.muted) }
                            else DoingMark(false, app.failedOf(setOf("profile.check", "profile.quota"), "station" to address, "id" to p.id), 12.dp)
                        }
                        Text(
                            (p.check?.detail?.replace(Regex("^可用[，,]\\s*"), "") ?: "还没检查过") + (p.check?.time?.get("checkedAt")?.let { " · ${it.ago}检查" } ?: ""),
                            fontSize = 13.sp, color = C.muted,
                        )
                    }
                }
            }
            if (p.trouble != null) ProfileRecovery(s, p)
            if (kind == "subscription" && p.machine != true) SignIn(address, p, needed = p.check?.state == "login" || p.login?.state in SIGNING_IN)
            if (p.trouble?.action != "quota") QuotaSection(address, p)
            if (p.fast != null) {
                val busy = app.isDoing("profile.put", "station" to address, "id" to p.id)
                SectionHeader("运行", start = 24.dp)
                ListCard {
                    ListRow(onClick = if (busy) null else ({ app.act("保存 Fast", if (p.fast) "已关闭 Fast" else "已打开 Fast") { api.putProfile(p.id, buildJsonObject { put("fast", !p.fast) }) } })) {
                        Column(Modifier.weight(1f)) {
                            Text("Fast", fontSize = 15.sp, color = C.ink)
                            Text("更快响应，消耗更多额度或积分 · 下一轮生效", fontSize = 13.sp, color = C.muted)
                        }
                        DoingMark(busy, app.failedOf("profile.put", "station" to address, "id" to p.id), 14.dp)
                        Switch(p.fast)
                    }
                }
            }
            ModelsSection(address, p, p.models, p.modelsSaving != null) { models -> setModels(models) }
            // A station older than the setting says nothing of it.
            val background = flipping ?: p.backgroundOnMessage
            if ("claude" in p.runtimes && background != null) {
                SectionHeader("运行", start = 24.dp)
                ListCard {
                    ListRow(onClick = if (flipping != null) null else ({
                        flipping = !background
                        app.scope.launch {
                            try { api.putProfile(p.id, buildJsonObject { put("backgroundOnMessage", !background) }); app.toast = if (background) "已关闭" else "已打开" }
                            catch (e: CoreException) { app.toast = "没能保存：${errorText(e)}" }
                            finally { flipping = null }
                        }
                    })) {
                        Column(Modifier.weight(1f)) {
                            Text("新消息到来时，把正在执行的命令转到后台", fontSize = 15.sp, color = C.ink)
                            Text(if (background) "命令和 subagent 转到后台继续跑，agent 马上读到消息。" else "新消息要等正在执行的命令或 subagent 结束后才会读到。", fontSize = 13.sp, color = C.muted)
                        }
                        if (flipping != null) Spinner(14.dp)
                        Switch(background)
                    }
                }
            }
            SectionHeader("使用它的连接", start = 24.dp)
            ListCard {
                if (users.isEmpty()) ListRow { Text("还没有连接使用这个 Profile。", fontSize = 15.sp, color = C.muted) }
                users.forEach { c ->
                    ListRow(onClick = { app.push(Screen.Connect(address, c.id)) }) {
                        SlackMark(15.dp)
                        Text(c.name, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(c.modelName ?: p.model?.let { p.names[it] ?: it } ?: "默认模型", fontSize = 13.sp, color = C.muted)
                    }
                }
            }
            if (p.machine == true) {
                // On the machine's own login: whose it is is changed on that machine, not here.
                val runtime = MACHINE_RUNTIME[p.runtime] ?: p.runtime
                SectionHeader("账号", start = 24.dp)
                Card {
                    Text("${s.name} 上 $runtime 的登录", fontSize = 15.sp, color = C.ink)
                    Text("要换号、重新登录或登出，在这台机器的 $runtime 里做，这个 Profile 跟着它变；不想用了就停用（右上角菜单）。", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(top = 4.dp))
                }
            } else if (kind in KEYED) {
                val name = if (kind == "opencode-go") "OpenCode Go key" else "API key"
                SectionHeader("账号", start = 24.dp)
                ListCard {
                    ListRow(onClick = {
                        ask(app, if (kind == "opencode-go") "新的 OpenCode Go key" else "新的 API key", "", "粘贴 key", "保存", secret = true, hint = "保存后会重新检查。") { key ->
                            api.putProfile(p.id, buildJsonObject { putJsonObject("access") { put("kind", kind); put("key", key) } }); app.toast = "已保存，正在检查"
                        }
                    }) {
                        Column(Modifier.weight(1f)) {
                            Text(name, fontSize = 15.sp, color = C.ink)
                            Text(p.access.key.ifEmpty { "没有保存" }, fontSize = 13.sp, color = C.muted, fontFamily = FontFamily.Monospace)
                        }
                        Text("更换", fontSize = 14.sp, color = C.accent)
                    }
                }
            }
            if (kind == "env") {
                SectionHeader("环境变量", start = 24.dp)
                ListCard {
                    p.env.forEach { e ->
                        ListRow {
                            Column(Modifier.weight(1f)) {
                                Text(e.key, fontSize = 15.sp, color = C.ink, fontFamily = FontFamily.Monospace)
                                Text(e.value, fontSize = 13.sp, color = C.muted, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                        }
                    }
                    ListRow(onClick = { app.sheet = SheetSpec(0.8f, draggable = true) { EnvSheet(address, p) } }) { Text("编辑变量", fontSize = 15.sp, color = C.accent) }
                }
            }
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** The same core-provided diagnosis and next step as the mobile web. */
@Composable
private fun ProfileRecovery(station: StationView, p: Profile) {
    val app = LocalApp.current
    val issue = p.trouble ?: return
    val address = station.station
    val api = app.api(address)
    val checking = app.isDoing("profile.check", "station" to address, "id" to p.id)
    val refreshing = app.isDoing("profile.quota", "station" to address, "id" to p.id)
    SectionHeader(issue.title, start = 24.dp)
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(issue.detail, fontSize = 13.sp, color = C.ink)
            Text(issue.next, fontSize = 13.sp, color = C.muted)
            if (!station.online) Text("${station.name} 已离线，恢复连接后才能操作", fontSize = 13.sp, color = C.muted)
            if (issue.action == "command") CommandBox(p.loginCommand)
            if (issue.action != "login") Button(issue.label, primary = false, enabled = station.online, busy = checking || refreshing) {
                when (issue.action) {
                    "key" -> ask(app, "新的 key", "", "粘贴 key", "保存", secret = true, hint = "保存后会重新检查") { key ->
                        api.putProfile(p.id, buildJsonObject { putJsonObject("access") { put("kind", p.access.kind); put("key", key) } })
                    }
                    "env" -> app.sheet = SheetSpec(0.8f, draggable = true) { EnvSheet(address, p) }
                    "quota" -> app.act("查询额度", "已更新额度") { api.refreshQuota(p.id) }
                    else -> app.act("检查账号", "已检查") { api.checkProfile(p.id) }
                }
            }
            if (issue.action in setOf("key", "env")) Button("重新检查", primary = false, enabled = station.online, busy = checking) {
                app.act("检查账号", "已检查") { api.checkProfile(p.id) }
            }
            DoingMark(false, app.failedOf(setOf("profile.check", "profile.quota"), "station" to address, "id" to p.id))
        }
    }
}

/** Renaming, checking, deleting it (not while a connect uses it). */
private fun openProfileMenu(app: AppState, station: String, p: Profile) {
    val api = app.api(station)
    app.sheet = SheetSpec(0.5f) {
        // Goes on past the sheet; the profile's page shows it under way (a spinner by its state or its allowance).
        val run = { what: String, done: String, call: suspend () -> Unit -> app.sheet = null; app.act(what, done) { call() } }
        val checking = app.isDoing("profile.check", "station" to station, "id" to p.id)
        SheetGrab()
        SheetHead(p.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            if (p.machine != true) PickRow("改名") { ask(app, "Profile 的名字", p.name, "名字", "保存") { name -> api.putProfile(p.id, buildJsonObject { put("name", name) }); app.toast = "已改名" } }
            PickRow("重新检查", busy = checking, failed = app.failedOf("profile.check", "station" to station, "id" to p.id)) { run("检查", "已检查") { api.checkProfile(p.id) } }
            // One on the machine's login is stopped rather than deleted: the login stays the machine's, to be used again.
            val machine = p.machine == true
            PickRow((if (machine) "停用" else "删除 Profile") + if (p.usedBy.isNotEmpty()) "（还有连接在用）" else "", color = C.red, enabled = p.usedBy.isEmpty()) {
                if (machine) confirm(app, "停用「${p.name}」？", "${BuildConfig.APP_NAME} 不再用这台机器上 ${MACHINE_RUNTIME[p.runtime] ?: p.runtime} 的登录；这台机器上的登录不受影响，之后可以再用。", "停用", danger = true) {
                    api.deleteProfile(p.id); app.toast = "已停用"; app.pop()
                }
                else confirm(app, "删除「${p.name}」？", "只从 ${BuildConfig.APP_NAME} 的配置里移除；配置目录和里面的登录状态不会删除。", "删除 Profile", danger = true) {
                    api.deleteProfile(p.id); app.toast = "已删除 Profile"; app.pop()
                }
            }
        }
    }
}

/** Its allowance, window by window: what is left and when it refills; why it cannot be read, when the provider says. */
@Composable
private fun QuotaSection(station: String, p: Profile) {
    val app = LocalApp.current
    val refreshing = app.isDoing("profile.quota", "station" to station, "id" to p.id)
    val failed = app.failedOf("profile.quota", "station" to station, "id" to p.id)
    val windows = p.quota?.takeIf { it.state == "ok" }?.windows.orEmpty()
    val trouble = quotaTrouble(p.quota)
    val checked = if (refreshing) "正在刷新…" else p.quota?.time?.get("checkedAt")?.let { "${it.ago}查询" }
    Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(top = 14.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("额度", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
        Spacer(Modifier.weight(1f))
        Row(Modifier.clickable(enabled = !refreshing) {
            app.act("查询额度", "已更新额度") { app.api(station).refreshQuota(p.id) }
        }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DoingMark(refreshing, failed, 12.dp)
            Text(if (refreshing) "正在查询…" else "查询额度", fontSize = 14.sp, color = if (refreshing) C.muted else C.accent)
        }
    }
    if (checked != null && !refreshing) Text(checked, fontSize = 12.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, bottom = 8.dp))
    if (trouble != null) {
        val blocked = p.quota?.state == "blocked"
        ListCard {
            ListRow {
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        PresenceDot(if (blocked) "error" else "offline")
                        Text(if (blocked) "被停用" else "查不到额度", fontSize = 15.sp, color = C.ink)
                    }
                    Text(trouble, fontSize = 13.sp, color = C.muted)
                }
            }
        }
        return
    }
    if (windows.isEmpty() && p.quota?.creditsText == null && p.quota?.resetCount == null) {
        Text(p.quota?.detail?.ifBlank { null } ?: "还没有额度信息", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 10.dp))
        return
    }
    val resetting = app.isDoing("profile.resetQuota", "station" to station, "id" to p.id)
    ListCard {
        if (windows.isNotEmpty()) QuotaDials(p.quota, Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 14.dp))
        p.quota?.creditsText?.let { text -> ListRow {
            Text("积分余额", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
            Text(text, fontSize = 13.sp, color = C.muted)
        } }
        p.quota?.resetCount?.let { count -> ListRow(onClick = if (count <= 0 || resetting) null else ({
            confirm(app, "重置额度？", "将使用「${p.name}」的 1 次额度重置，${p.quota.resetText}", "使用一次重置") {
                app.api(station).resetQuota(p.id); app.toast = "已重置额度"
            }
        })) {
            Column(Modifier.weight(1f)) {
                Text("额度重置", fontSize = 15.sp, color = C.ink)
                Text(p.quota.resetText ?: "", fontSize = 13.sp, color = C.muted)
            }
            DoingMark(resetting, app.failedOf("profile.resetQuota", "station" to station, "id" to p.id), 14.dp)
            Text("重置额度", fontSize = 14.sp, color = if (count > 0) C.accent else C.muted)
        } }
    }
}

/** A check's state in its words on a soft pill of its tone (the core's: accent | green | blue | red | amber | neutral). */
@Composable
internal fun TonePill(text: String, tone: String, size: androidx.compose.ui.unit.TextUnit = 12.sp) {
    val color = when (tone) { "green" -> C.green; "red" -> C.red; "blue" -> C.blue; "accent" -> C.accentInk; "amber" -> C.warn; else -> C.muted }
    val bg = if (tone == "neutral") C.chip else color.copy(alpha = if (tone == "amber") 0.14f else 0.12f)
    Text(text, fontSize = size, color = color, maxLines = 1, modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(bg).padding(horizontal = 6.dp, vertical = 1.dp))
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
@Composable
internal fun ModelsSection(station: String, p: Profile, models: List<String>, saving: Boolean, onSave: (List<String>) -> Unit) {
    val app = LocalApp.current
    val checking = app.isDoing("profile.check", "station" to station, "id" to p.id)
    val checkFailed = app.failedOf("profile.check", "station" to station, "id" to p.id)
    var filter by remember { mutableStateOf("") }
    val all = (p.available ?: (p.check?.models.orEmpty() + p.models).distinct()).sorted()
    val shown = all.filter { m -> listOf(m, p.names[m] ?: m).any { it.contains(filter.trim(), ignoreCase = true) } }
    val save = { models: List<String> -> onSave(models.distinct().sorted()) }
    val suffix = if (filter.isBlank()) "" else "筛选结果"
    SectionHeader("模型 · 启用 ${models.size} / ${all.size}${if (saving) " · 正在保存…" else ""}", start = 24.dp)
    Text(
        if (all.isEmpty()) "检查过 Profile 后，这里会列出它能用的模型，勾选后才能使用。" else "只有勾选的模型能在新对话和连接里选。",
        fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 6.dp),
    )
    Row(Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.clickable(enabled = !checking) { app.act("刷新模型", "检查完成") { app.api(station).checkProfile(p.id) } },
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DoingMark(checking, checkFailed, 12.dp)
            Text(if (checking) "正在刷新…" else "刷新模型", fontSize = 14.sp, color = if (checking) C.muted else C.accent)
        }
        Spacer(Modifier.weight(1f))
        if (all.isNotEmpty()) {
            Text("全选$suffix", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable(enabled = !saving) { save(models + shown) })
            Text("全不选$suffix", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable(enabled = !saving) { save(models - shown.toSet()) })
        }
    }
    if (all.size > 10) Field(filter, { filter = it }, "筛选模型", modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp))
    // Plain rows on the page, no card behind them; by series, newest first (the core's).
    p.series.forEach { series ->
        val list = series.models.filter { it in shown }
        if (list.isNotEmpty()) Text(series.name, fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(top = 14.dp, bottom = 2.dp))
        list.forEach { m ->
            val on = m in models
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !saving) { save(if (on) models - m else models + m) }.padding(horizontal = 24.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Box(Modifier.size(20.dp).clip(RoundedCornerShape(6.dp)).background(if (on) C.accent else C.chip), contentAlignment = Alignment.Center) {
                    if (on) IconIn(Icons.Check, 13.dp, C.bg)
                }
                Text(p.names[m] ?: m, fontSize = 14.sp, color = C.ink, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                // Ticked here, not the station's yet.
                if (m in p.modelsSaving.orEmpty()) Spinner(12.dp)
            }
        }
    }
}

/** A subscription's sign-in: run on the station's machine, the browser steps relayed here. */
@Composable
private fun SignIn(station: String, p: Profile, needed: Boolean) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(station)
    val job = p.login
    val active = job != null && job.state in SIGNING_IN
    val provider = if (p.runtime == "claude") "Claude" else "ChatGPT"
    val busy = app.isDoing("profile.login", "station" to station, "id" to p.id)
    var manual by remember { mutableStateOf(false) }
    var previous by remember { mutableStateOf(job?.state) }
    LaunchedEffect(job?.state) {
        if (job?.state == "done" && previous != null && previous != "done") app.toast = "登录成功"
        previous = job?.state
    }
    SectionHeader(if (active) "正在登录 $provider" else if (needed) "还没登录 $provider 账号" else "$provider 订阅", start = 24.dp)
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            if (active) {
                LoginSteps(job, provider) { code -> api.loginCode(p.id, code) }
                Button("取消登录", primary = false, busy = app.isDoing("profile.cancelLogin", "station" to station, "id" to p.id)) { app.act("取消登录") { api.cancelLogin(p.id) } }
            } else {
                Text(
                    when (job?.state) { "failed" -> "上次登录没成功：${job.error}"; "done" -> "已登录。换账号的话重新登录一次。"; else -> "登录在运行 ${BuildConfig.APP_NAME} 的机器上完成，你只需要在浏览器里授权。" },
                    fontSize = 13.sp, color = C.muted,
                )
                Button(if (job?.state == "done" || !needed) "重新登录" else "登录", primary = needed, busy = busy) {
                    scope.launch { try { api.startLogin(p.id) } catch (e: CoreException) { app.toast = "没能开始登录：${errorText(e)}" } }
                }
                Text("也可以在那台机器上手动登录", fontSize = 13.sp, color = C.muted, modifier = Modifier.clickable { manual = !manual }.padding(vertical = 4.dp))
                if (manual) CommandBox(p.loginCommand)
            }
        }
    }
}

/**
 * What the person does in the browser for a sign-in under way: open the page and paste the code back (Claude), or copy
 * the code and open the page (Codex).
 */
@Composable
private fun LoginSteps(job: LoginJob?, provider: String, send: suspend (String) -> Unit) {
    val context = LocalContext.current
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    val operation = remember(app) { Action(app) }
        val busy = operation.busy
    val error = operation.error?.message
    var copied by remember { mutableStateOf(false) }
    val open = { url: String -> context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    val waiting = @Composable { text: String ->
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) { Spinner(12.dp); Text(text, fontSize = 13.sp, color = C.muted) }
    }
    when {
        job == null || job.state == "starting" -> waiting("正在生成 $provider 的登录链接…")
        job.state == "verifying" -> waiting("正在完成登录…")
        job.state == "done" -> waiting("已登录，正在添加…")
        job.state == "needs_approval" && job.url != null && job.userCode != null -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(job.userCode, fontSize = 22.sp, letterSpacing = 2.sp, fontFamily = FontFamily.Monospace, color = C.ink,
                modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(C.chip).padding(horizontal = 14.dp, vertical = 8.dp))
            Button(if (copied) "已复制，重新打开登录页" else "复制代码并打开登录页", primary = true) {
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("still.fail", job.userCode))
                copied = true; open(job.url)
            }
            Text("在打开的 OpenAI 页面用要给 ${BuildConfig.APP_NAME} 使用的 ChatGPT 账号登录，粘贴代码。完成后这里会自动继续。如果页面说设备码登录没开启，先在 ChatGPT 的安全设置里打开它。", fontSize = 13.sp, color = C.muted)
        }
        job.state == "needs_code" && job.url != null -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row {
                Text("1. ", fontSize = 13.sp, color = C.ink)
                Text("打开授权页面", fontSize = 13.sp, color = C.accent, modifier = Modifier.clickable { open(job.url) })
                Text("，用要给 ${BuildConfig.APP_NAME} 使用的 Claude 账号登录并同意。", fontSize = 13.sp, color = C.ink)
            }
            Text("2. 同意后页面上会显示一段授权码，复制过来：", fontSize = 13.sp, color = C.ink)
            Field(code, { code = it }, "粘贴授权码", mono = true)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Button("完成登录", primary = true, busy = busy, enabled = code.isNotBlank()) {

                operation.run { send(code.trim()); code = "" }
            }
        }
    }
}

/** A variable being edited: its row, name and value; a secret one saved before shows masked and is kept when left blank. */
private class EnvRow(val row: Int, key: String, value: String, val masked: String?, val original: String?) {
    var key by mutableStateOf(key)
    var value by mutableStateOf(value)
}

/** The variables a custom profile runs with: what reaches its runtime's model service, set by hand. */
@Composable
private fun ColumnScope.EnvSheet(station: String, p: Profile) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    var next by remember { mutableIntStateOf(1) }
    var rows by remember { mutableStateOf(p.env.mapIndexed { i, e -> EnvRow(-i - 1, e.key, if (e.secret) "" else e.value, if (e.secret) e.value else null, e.key) }) }
    val busy = app.isDoing("profile.put", "station" to station, "id" to p.id)
    val patch = {
        buildJsonObject {
            val kept = rows.map { it.key.trim() }.toSet()
            val out = LinkedHashMap<String, String?>()
            p.env.forEach { if (it.key !in kept) out[it.key] = null }
            rows.forEach { r ->
                val key = r.key.trim()
                if (key.isEmpty()) return@forEach
                if (r.original != null && r.original != key) out[r.original] = null
                if (r.masked != null && r.value.isEmpty() && r.original == key) return@forEach
                out[key] = r.value
            }
            out.forEach { (k, v) -> put(k, v?.let { JsonPrimitive(it) } ?: JsonNull) }
        }
    }
    SheetGrab()
    SheetHead("环境变量")
    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text("运行时启动时带上这些变量，用来接到你的模型服务。值里的 {route} 会换成会话的路由 ID。", fontSize = 12.sp, color = C.muted)
        rows.forEach { r ->
            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Field(r.key, { r.key = it }, "NAME", mono = true, modifier = Modifier.weight(1f))
                    Text("删除", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { rows = rows.filter { it.row != r.row } })
                }
                val placeholder = if (r.masked != null) "已保存 ${r.masked}，留空不变" else "值"
                if (r.masked != null || Regex("KEY|TOKEN|SECRET|PASSWORD|AUTH", RegexOption.IGNORE_CASE).containsMatchIn(r.key)) SecretField(r.value, { r.value = it }, placeholder)
                else Field(r.value, { r.value = it }, placeholder, mono = true)
            }
        }
        Text("＋ 添加变量", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { rows = rows + EnvRow(next++, "", "", null, null) })
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
            Button("取消", primary = false) { app.sheet = null }
            Button("保存", primary = true, busy = busy) {
                    scope.launch {
                    try { app.api(station).putProfile(p.id, buildJsonObject { put("env", patch()) }); app.toast = "已保存"; app.sheet = null }
                    catch (e: CoreException) { app.toast = e.message }
                }
            }
        }
    }
}

/**
 * A new profile on a station: a subscription is signed in first and the station makes the profile once that succeeds
 * (named by the account); a key is checked first and the profile made only if it works.
 */
@Composable
fun NewProfileScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val api = app.api(address)
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val s = stations.value?.firstOrNull { it.station == address }
    var choice by remember { mutableIntStateOf(0) }
    val picked = PROFILE_CHOICES[choice]
    var key by remember { mutableStateOf("") }
    var login by remember { mutableStateOf<String?>(null) }
    val busy = app.isDoing(setOf("login.new", "profile.add"), "station" to address)
    var error by remember { mutableStateOf<String?>(null) }
    val pending = login?.let { l -> s?.overview?.logins?.firstOrNull { it.id == l } }
    val go = { id: String, message: String -> app.toast = message; app.replace(Screen.Profile(address, id)) }
    // The sign-in made its profile: on to it.
    LaunchedEffect(pending?.created) { pending?.created?.let { go(it, "已登录，添加了 Profile") } }
    // Leaving before a sign-in made its profile leaves nothing behind.
    val leave = {
        val l = login
        if (l != null && pending?.created == null) app.scope.launch { try { api.dropLogin(l) } catch (_: CoreException) {} }
        app.pop()
    }
    androidx.activity.compose.BackHandler { leave() }
    val provider = if (picked.runtime == "claude") "Claude" else "ChatGPT"
    val job = pending?.job
    Column(Modifier.fillMaxSize()) {
        NavBar("取消", leave, "添加 Profile", sub = { Text(s?.name ?: "", fontSize = 11.sp, color = C.muted) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            val l = login
            if (l != null) {
                if (job?.state == "failed" || job?.state == "cancelled") {
                    Text(job.error ?: "登录没有完成。", fontSize = 13.sp, color = C.red)
                    Button("重新开始", primary = false) { app.act("重新开始") { api.dropLogin(l) }; login = null }
                } else LoginSteps(job, provider) { code -> api.newLoginCode(l, code) }
            } else {
                // The machine's own logins not used yet: a profile on one needs no sign-in.
                s?.overview?.let { o -> MachineLoginOffers(address, o, inset = 0.dp) { rt -> choice = PROFILE_CHOICES.indexOfFirst { it.kind == "subscription" && it.runtime == rt }.coerceAtLeast(0) } }
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                    PROFILE_CHOICES.forEachIndexed { i, c ->
                        PickRow(c.title, c.description, checked = choice == i, leading = { ProviderMark(c.runtime ?: "claude", c.kind, 18.dp) }) { choice = i }
                    }
                }
                if (picked.kind in KEYED) {
                    Text(if (picked.kind == "opencode-go") "OpenCode Go key" else "API key", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    SecretField(key, { key = it }, "先验证能用，再添加")
                }
                if (picked.kind == "subscription") Text("登录在运行 ${BuildConfig.APP_NAME} 的机器上完成，你只需要在浏览器里授权；登录成功后才会添加这个 Profile。", fontSize = 13.sp, color = C.muted)
                error?.let { Text(it, fontSize = 13.sp, color = C.red) }
                val run = { work: suspend () -> Unit -> error = null; scope.launch { try { work() } catch (e: CoreException) { error = e.message } }; Unit }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    if (picked.kind == "subscription") Button("登录 $provider", primary = true, busy = busy) { run { login = api.newLogin(picked.runtime!!) } }
                    else Button(if (picked.kind in KEYED) "验证并添加" else "添加", primary = true, busy = busy, enabled = picked.kind !in KEYED || key.isNotEmpty()) {
                        run { go(api.addProfile(picked.runtime, picked.kind, key.takeIf { picked.kind in KEYED }), "已验证并添加 Profile") }
                    }
                }
            }
        }
    }
}

/**
 * The accounts this station machine's own Claude Code and Codex are signed in with and no profile uses yet (the station
 * reads them), each with its plan beside its runtime, its state and allowance: one kept in a file is used as it is (a
 * profile on the machine's login, no sign-in); one only in the keychain is signed in again for still.fail; a refused one is
 * only said so. `inset`: the list's side margin (none inside a padded page). On the new-profile page (`onLogin`) the
 * profile made takes its place, and signing in again picks that runtime's subscription there.
 */
@Composable
fun MachineLoginOffers(station: String, overview: Overview, inset: androidx.compose.ui.unit.Dp = 12.dp, onLogin: ((String) -> Unit)? = null) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val offers = overview.machineLogins.orEmpty().filter { it.offered == true }
    if (offers.isEmpty()) return
    Text("这台机器上已经登录了", fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = inset + 12.dp, end = inset + 12.dp, top = 8.dp, bottom = 4.dp))
    Column(Modifier.padding(horizontal = inset).padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
        offers.forEach { l -> MachineLoginRow(l, app.isDoing("profile.useMachineLogin", "station" to station, "runtime" to l.runtime)) {
            if (l.usable == true) {
                scope.launch {
                    try {
                        val id = app.api(station).useMachineLogin(l.runtime)
                        app.toast = "已添加 Profile，用的是这台机器的登录"
                        if (onLogin != null) app.replace(Screen.Profile(station, id)) else app.push(Screen.Profile(station, id))
                    } catch (e: CoreException) { app.toast = e.message }
                }
            } else if (onLogin != null) onLogin(l.runtime) else app.push(Screen.NewProfile(station))
        } }
    }
}

/** A machine login as a profile could be made with it: its runtime and plan, a dot and its state, who, its allowance; and what to do. */
@Composable
private fun MachineLoginRow(l: MachineLogin, busy: Boolean, onUse: () -> Unit) {
    val blocked = l.quota?.state == "blocked"
    val plan = l.plan?.replaceFirstChar { it.uppercase() }
    ListRow {
        ProviderMark(l.runtime, "subscription", 18.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(MACHINE_RUNTIME[l.runtime] ?: l.runtime, fontSize = 15.sp, color = C.ink, maxLines = 1)
                plan?.let { Text(it, fontSize = 13.sp, color = C.muted, maxLines = 1) }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                StateDot(if (blocked) C.red else C.green, 6.dp)
                Text(if (blocked) "被停用" else "本机已登录", fontSize = 12.sp, color = if (blocked) C.red else C.muted)
                Text("· ${l.email ?: "已登录"}", fontSize = 12.sp, color = C.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            quotaTrouble(l.quota)?.let { Text(it, fontSize = 12.sp, color = if (blocked) C.red else C.muted) }
        }
        QuotaRings(l.quota)
        // A refused account is said so, with nothing to do with it here.
        if (!blocked) {
            if (busy) Spinner(14.dp)
            else Text(if (l.usable == true) "用这个账号" else "登录", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable(onClick = onUse))
        }
    }
}
