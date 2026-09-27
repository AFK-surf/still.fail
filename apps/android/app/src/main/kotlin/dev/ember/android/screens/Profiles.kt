// Profiles (as the narrow web's web/src/mobile/Profiles.tsx, from the desktop's pages/Accounts.tsx): a profile's page
// (whether it works, signing a subscription in, its allowance, which of its models may be used, who uses it, its key or
// variables; renaming, checking and deleting under "…"), and a new one.
package dev.ember.android.screens

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
import dev.ember.android.AppState
import dev.ember.android.LocalApp
import dev.ember.android.Screen
import dev.ember.android.data.ACCESS_LABEL
import dev.ember.android.data.KEYED
import dev.ember.android.data.LoginJob
import dev.ember.android.data.PROFILE_CHOICES
import dev.ember.android.data.Profile
import dev.ember.android.data.StationView
import dev.ember.android.data.Topics
import dev.ember.android.data.WorkspaceEntry
import dev.ember.android.data.rememberTopic
import dev.ember.android.ui.C
import dev.ember.android.ui.Card
import dev.ember.android.ui.IconIn
import dev.ember.android.ui.Icons
import dev.ember.android.ui.ListCard
import dev.ember.android.ui.ListRow
import dev.ember.android.ui.Loading
import dev.ember.android.ui.NavBar
import dev.ember.android.ui.NavButton
import dev.ember.android.ui.ProviderMark
import dev.ember.android.ui.QuotaRing
import dev.ember.android.ui.SectionHeader
import dev.ember.android.ui.SheetGrab
import dev.ember.android.ui.SheetHead
import dev.ember.android.ui.SheetSpec
import dev.ember.android.ui.SlackMark
import dev.ember.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.add
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject

private val SIGNING_IN = setOf("starting", "needs_code", "needs_approval", "verifying")

/** A check's tone as a colour (the core's: accent | green | blue | red | neutral). */
@Composable
private fun toneColor(tone: String): Color = when (tone) { "green" -> C.green; "red" -> C.red; "blue" -> C.blue; "accent" -> C.accent; else -> C.muted }

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
    val scope = rememberCoroutineScope()
    val save = { body: JsonObject, done: String -> scope.launch { try { api.putProfile(p.id, body); app.toast = done } catch (e: CoreException) { app.toast = e.message } }; Unit }
    val users = p.usedBy.mapNotNull { u -> s.overview?.connects?.firstOrNull { it.id == u } }
    val kind = p.access.kind
    Column(Modifier.fillMaxSize()) {
        NavBar(s.name, app::pop, p.name, sub = { Text(ACCESS_LABEL[kind] ?: kind, fontSize = 11.sp, color = C.muted) },
            trailing = { NavButton(Icons.More, { openProfileMenu(app, address, p) }) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            Card {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    ProviderMark(p.runtime, kind, 26.dp)
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        val tone = toneColor(p.checkTone)
                        Text(p.checkText, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = tone,
                            modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(tone.copy(alpha = 0.12f)).padding(horizontal = 8.dp, vertical = 2.dp))
                        Text(
                            (p.check?.detail?.replace(Regex("^可用[，,]\\s*"), "") ?: "还没检查过") + (p.check?.time?.get("checkedAt")?.let { " · ${it.ago}检查" } ?: ""),
                            fontSize = 13.sp, color = C.muted,
                        )
                    }
                }
            }
            if (kind == "subscription") SignIn(address, p, needed = p.check?.state == "login" || p.login?.state in SIGNING_IN)
            QuotaSection(p)
            ModelsSection(p) { models -> save(buildJsonObject { putJsonArray("models") { models.forEach { add(JsonPrimitive(it)) } } }, "已保存") }
            SectionHeader("使用它的连接", start = 24.dp)
            ListCard {
                if (users.isEmpty()) ListRow { Text("还没有连接使用这个 Profile。", fontSize = 15.sp, color = C.muted) }
                users.forEach { c ->
                    ListRow(onClick = { app.push(Screen.Connect(address, c.id)) }) {
                        SlackMark(15.dp)
                        Text(c.name, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(c.bind.model ?: p.model ?: "默认模型", fontSize = 13.sp, color = C.muted)
                    }
                }
            }
            if (kind in KEYED) {
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

/** Renaming, checking, refreshing its allowance, deleting it (not while a connect uses it). */
private fun openProfileMenu(app: AppState, station: String, p: Profile) {
    val api = app.api(station)
    app.sheet = SheetSpec(0.5f) {
        val scope = rememberCoroutineScope()
        val run = { done: String, call: suspend () -> Unit -> app.sheet = null; scope.launch { try { call(); app.toast = done } catch (e: CoreException) { app.toast = e.message } }; Unit }
        SheetGrab()
        SheetHead(p.name)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(bottom = 24.dp)) {
            PickRow("改名") { ask(app, "Profile 的名字", p.name, "名字", "保存") { name -> api.putProfile(p.id, buildJsonObject { put("name", name) }); app.toast = "已改名" } }
            PickRow("重新检查") { run("已检查") { api.checkProfile(p.id) } }
            PickRow("刷新额度") { run("已刷新额度") { api.refreshQuota(p.id) } }
            PickRow(if (p.usedBy.isNotEmpty()) "删除 Profile（还有连接在用）" else "删除 Profile", color = C.red, enabled = p.usedBy.isEmpty()) {
                confirm(app, "删除「${p.name}」？", "只从 ember 的配置里移除；配置目录和里面的登录状态不会删除。", "删除 Profile", danger = true) {
                    api.deleteProfile(p.id); app.toast = "已删除 Profile"; app.pop()
                }
            }
        }
    }
}

/** Its allowance, window by window: what is left and when it refills. */
@Composable
private fun QuotaSection(p: Profile) {
    val windows = p.quota?.takeIf { it.state == "ok" }?.windows.orEmpty()
    if (windows.isEmpty()) return
    SectionHeader("额度", p.quota?.time?.get("checkedAt")?.let { "${it.ago}查询" }, start = 24.dp)
    ListCard {
        windows.forEach { w ->
            ListRow {
                QuotaRing(w.left, w.level, 26.dp)
                Column(Modifier.weight(1f)) {
                    Text(w.label, fontSize = 15.sp, color = C.ink)
                    w.refills?.let { Text(it, fontSize = 13.sp, color = C.muted) }
                }
                Text("剩 ${w.left}%", fontSize = 13.sp, color = C.muted)
            }
        }
    }
}

/** Which of its models may be used: one per line, a filter when there are many, and all / none of what is shown. */
@Composable
private fun ModelsSection(p: Profile, onSave: (List<String>) -> Unit) {
    var filter by remember { mutableStateOf("") }
    val all = ((p.check?.models ?: emptyList()) + p.models).distinct().sorted()
    val shown = all.filter { it.contains(filter.trim(), ignoreCase = true) }
    val save = { models: List<String> -> onSave(models.distinct().sorted()) }
    val suffix = if (filter.isBlank()) "" else "筛选结果"
    SectionHeader("模型 · 启用 ${p.models.size} / ${all.size}", start = 24.dp)
    Text(
        if (all.isEmpty()) "检查过 Profile 后，这里会列出它能用的模型，勾选后才能使用。" else "只有勾选的模型能在新对话和连接里选。",
        fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 6.dp),
    )
    if (all.isNotEmpty()) Row(Modifier.padding(horizontal = 12.dp).padding(bottom = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        if (all.size > 10) Field(filter, { filter = it }, "筛选模型", modifier = Modifier.weight(1f)) else Spacer(Modifier.weight(1f))
        Text("全选$suffix", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { save(p.models + shown) })
        Text("全不选$suffix", fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { save(p.models - shown.toSet()) })
    }
    // Plain rows on the page, no card behind them.
    shown.forEach { m ->
        val on = m in p.models
        Row(
            Modifier.fillMaxWidth().clickable { save(if (on) p.models - m else p.models + m) }.padding(horizontal = 24.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(Modifier.size(20.dp).clip(RoundedCornerShape(6.dp)).background(if (on) C.accent else C.chip), contentAlignment = Alignment.Center) {
                if (on) IconIn(Icons.Check, 13.dp, C.bg)
            }
            Text(m, fontSize = 14.sp, fontFamily = FontFamily.Monospace, color = C.ink, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
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
    var busy by remember { mutableStateOf(false) }
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
                Button("取消登录", primary = false) { scope.launch { try { api.cancelLogin(p.id) } catch (e: CoreException) { app.toast = e.message } } }
            } else {
                Text(
                    when (job?.state) { "failed" -> "上次登录没成功：${job.error}"; "done" -> "已登录。换账号的话重新登录一次。"; else -> "登录在运行 ember 的机器上完成，你只需要在浏览器里授权。" },
                    fontSize = 13.sp, color = C.muted,
                )
                Button(if (job?.state == "done" || !needed) "重新登录" else "登录", primary = needed, busy = busy) {
                    busy = true
                    scope.launch { try { api.startLogin(p.id) } catch (e: CoreException) { app.toast = e.message } finally { busy = false } }
                }
                Text("也可以在那台机器上手动登录", fontSize = 13.sp, color = C.accent, modifier = Modifier.clickable { manual = !manual })
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
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
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
                (context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("ember", job.userCode))
                copied = true; open(job.url)
            }
            Text("在打开的 OpenAI 页面用要给 ember 使用的 ChatGPT 账号登录，粘贴代码。完成后这里会自动继续。如果页面说设备码登录没开启，先在 ChatGPT 的安全设置里打开它。", fontSize = 13.sp, color = C.muted)
        }
        job.state == "needs_code" && job.url != null -> Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row {
                Text("1. ", fontSize = 13.sp, color = C.ink)
                Text("打开授权页面", fontSize = 13.sp, color = C.accent, modifier = Modifier.clickable { open(job.url) })
                Text("，用要给 ember 使用的 Claude 账号登录并同意。", fontSize = 13.sp, color = C.ink)
            }
            Text("2. 同意后页面上会显示一段授权码，复制过来：", fontSize = 13.sp, color = C.ink)
            Field(code, { code = it }, "粘贴授权码", mono = true)
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Button("完成登录", primary = true, busy = busy, enabled = code.isNotBlank()) {
                busy = true; error = null
                scope.launch { try { send(code.trim()); code = "" } catch (e: CoreException) { error = e.message } finally { busy = false } }
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
    var busy by remember { mutableStateOf(false) }
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
                busy = true
                scope.launch {
                    try { app.api(station).putProfile(p.id, buildJsonObject { put("env", patch()) }); app.toast = "已保存"; app.sheet = null }
                    catch (e: CoreException) { app.toast = e.message } finally { busy = false }
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
    var busy by remember { mutableStateOf(false) }
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
                    Button("重新开始", primary = false) { scope.launch { try { api.dropLogin(l) } catch (_: CoreException) {} }; login = null }
                } else LoginSteps(job, provider) { code -> api.newLoginCode(l, code) }
            } else {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(C.surface)) {
                    PROFILE_CHOICES.forEachIndexed { i, c ->
                        PickRow(c.title, c.description, checked = choice == i, leading = { ProviderMark(c.runtime ?: "claude", c.kind, 18.dp) }) { choice = i }
                    }
                }
                if (picked.kind in KEYED) {
                    Text(if (picked.kind == "opencode-go") "OpenCode Go key" else "API key", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
                    SecretField(key, { key = it }, "先验证能用，再添加")
                }
                if (picked.kind == "subscription") Text("登录在运行 ember 的机器上完成，你只需要在浏览器里授权；登录成功后才会添加这个 Profile。", fontSize = 13.sp, color = C.muted)
                error?.let { Text(it, fontSize = 13.sp, color = C.red) }
                val run = { work: suspend () -> Unit -> busy = true; error = null; scope.launch { try { work() } catch (e: CoreException) { error = e.message } finally { busy = false } }; Unit }
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
