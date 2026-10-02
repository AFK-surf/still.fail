// A station's 共享调试 (docs/adb-share.md): this phone's adb lent to the station's agents, how it stands, what the phone
// needs for it (Developer options, Wi-Fi, Wireless debugging), pairing the first time, and the app turning Wireless
// debugging on itself from then on. The lending itself is the core's and AdbShare.kt's; this page only shows and asks.
package fail.still.android.screens

import android.Manifest
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.LifecycleResumeEffect
import fail.still.android.AdbShare
import fail.still.android.LocalApp
import fail.still.android.Notifier
import fail.still.android.data.AdbShareView
import fail.still.android.data.StationView
import fail.still.android.data.Topics
import fail.still.android.data.WorkspaceEntry
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.Card
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.NavBar
import fail.still.android.ui.SectionHeader
import kotlinx.coroutines.delay
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** What the phone has for Wireless debugging, read again as the page comes back and as the setting changes. */
private data class Phone(val developer: Boolean, val wireless: Boolean, val wifi: Boolean, val canSwitch: Boolean)

@Composable
private fun rememberPhone(): MutableState<Phone> {
    val context = LocalContext.current
    val read = { Phone(AdbShare.developerOptions(context), AdbShare.wirelessOn(context), AdbShare.onWifi(context), AdbShare.canSwitch(context)) }
    val phone = remember { mutableStateOf(read()) }
    // Back from Settings.
    LifecycleResumeEffect(Unit) {
        phone.value = read()
        onPauseOrDispose {}
    }
    // Wireless debugging switched (by the app, or by Android as the Wi-Fi goes).
    DisposableEffect(Unit) {
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) { phone.value = read() }
        }
        context.contentResolver.registerContentObserver(AdbShare.wirelessUri(), false, observer)
        onDispose { context.contentResolver.unregisterContentObserver(observer) }
    }
    return phone
}

@Composable
fun AdbShareScreen(current: WorkspaceEntry, address: String) {
    val app = LocalApp.current
    val context = LocalContext.current
    val stations by rememberTopic<List<StationView>>(app.core, Topics.stations(current.workspace.id))
    val name = stations.value?.firstOrNull { it.station == address }?.name ?: stationName(address)
    val shared by rememberTopic<AdbShareView>(app.core, Topics.adbShare)
    val view = shared.value
    val here = view?.sharing == true && view.station == address
    val elsewhere = view?.sharing == true && view.station != address
    var phone by rememberPhone()
    // 还剩 N 分钟 as the minutes go.
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(here) { while (here) { delay(20_000); now = System.currentTimeMillis() } }
    // The pairing code is typed into the notification: it is asked for once, as the lending starts.
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { AdbShare.start(context, address, name) }
    val start = {
        if (!Notifier.allowed(context) && Build.VERSION.SDK_INT >= 33) ask.launch(Manifest.permission.POST_NOTIFICATIONS)
        else AdbShare.start(context, address, name)
    }
    Column(Modifier.fillMaxSize()) {
        NavBar("Station", app::pop, "共享调试", sub = { Text(name, fontSize = 11.sp, color = C.muted, maxLines = 1) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            Text(
                "把这台手机的 adb 借给「$name」上的 agent：它们在那台机器上用 adb 操作这台手机，像插着线一样。数据只走你和 station 之间已有的连接，一小时后自动停止。",
                fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 10.dp),
            )
            if (!AdbShare.supported) {
                Card { Text("需要 Android 11 及以上：这台手机没有无线调试。", fontSize = 14.sp, color = C.ink) }
                return@Column
            }
            Card {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (here) {
                        Text(state(view!!, now), fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = if (view.adb in setOf("missing", "failed")) C.red else C.ink)
                        view.serial?.takeIf { view.adb == "connected" }?.let { serial ->
                            SelectionContainer { Text("agent 用：adb -s $serial", fontSize = 13.sp, fontFamily = FontFamily.Monospace, color = C.muted) }
                        }
                        // What the station said, when it says more than the line above.
                        if (view.adb != "connected") view.message?.takeIf { it.isNotBlank() && it != state(view, now) && !state(view, now).endsWith(it) }?.let { Text(it, fontSize = 13.sp, color = C.muted) }
                        Button("停止共享", primary = false) { app.act("停止共享") { app.core.call("adb.stop") } }
                    } else {
                        Text(if (elsewhere) "正在共享给另一台 station；开始会换到这台。" else "没有在共享。", fontSize = 15.sp, color = C.ink)
                        // Why it stopped by itself (its hour up, the station too old).
                        if (view?.sharing == false) view.message?.let { Text(it, fontSize = 13.sp, color = C.muted) }
                        Button("开始共享", primary = true, onClick = start)
                    }
                }
            }
            SectionHeader("手机上", start = 24.dp)
            ListCard {
                Need("开发者选项", phone.developer, if (phone.developer) "已打开" else "设置 › 关于手机，连点「版本号」7 次")
                Need("WLAN", phone.wifi, if (phone.wifi) "已连接" else "无线调试要连着 WLAN")
                ListRow(onClick = {
                    if (!phone.wireless && AdbShare.switchOn(context)) phone = phone.copy(wireless = true) else AdbShare.openWireless(context)
                }) {
                    Text("无线调试", fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                    Text(if (phone.wireless) "已打开" else if (phone.canSwitch) "点这里打开" else "去设置里打开", fontSize = 14.sp, color = if (phone.wireless) C.muted else C.accent)
                }
            }
            if (here && view!!.adb == "unpaired") Pairing(view)
            if (here && view!!.adb == "connected" && !phone.canSwitch) {
                SectionHeader("以后", start = 24.dp)
                Card {
                    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Text("让 app 以后自己打开无线调试，就不用每次去设置里开。由 station 的 adb 给 app 授权（WRITE_SECURE_SETTINGS），卸载 app 后失效。", fontSize = 13.sp, color = C.muted)
                        Button("允许 app 打开无线调试", primary = false, busy = app.isDoing("adb.grant")) {
                            app.act("授权", "以后 app 会自己打开无线调试") {
                                app.core.call("adb.grant")
                                phone = phone.copy(canSwitch = AdbShare.canSwitch(context))
                            }
                        }
                    }
                }
            }
            Text(
                "共享期间，这台 station 上的所有 agent 都能通过 adb 操作这台手机：装 app、截屏、读应用数据。用完可以在开发者选项里「撤销 USB 调试授权」。",
                fontSize = 12.sp, color = C.subtle, modifier = Modifier.padding(start = 24.dp, end = 24.dp, top = 16.dp),
            )
            Spacer(Modifier.height(30.dp))
        }
    }
}

/** What the phone needs, and whether it has it. */
@Composable
private fun Need(title: String, ok: Boolean, value: String) {
    ListRow {
        Text(title, fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
        Text(value, fontSize = 14.sp, color = if (ok) C.muted else C.red)
    }
}

/** The first time with a station: its adb pairs with the phone through the pairing dialog's code. */
@Composable
private fun Pairing(view: AdbShareView) {
    val app = LocalApp.current
    val context = LocalContext.current
    var code by remember { mutableStateOf("") }
    SectionHeader("配对（每台 station 一次）", start = 24.dp)
    Card {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                "1. 进无线调试，点「使用配对码配对设备」。\n2. 别离开那个窗口：下拉通知，在「共享调试」里点「填配对码」，填上 6 位码。分屏的话也可以填在下面。",
                fontSize = 13.sp, color = C.muted,
            )
            Button("去无线调试", primary = false) { AdbShare.openWireless(context) }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Field(code, { code = it.filter(Char::isDigit).take(6) }, "6 位配对码", mono = true, modifier = Modifier.weight(1f))
                Button("配对", primary = true, enabled = code.length == 6 && view.pairPort != null, busy = app.isDoing("adb.pair")) {
                    app.act("配对", "配对好了") { app.core.call("adb.pair", buildJsonObject { put("code", code) }) }
                }
            }
            if (view.pairPort == null) Text("配对窗口打开后才能配对。", fontSize = 12.sp, color = C.subtle)
        }
    }
}

/** How the lending stands, in a line. */
private fun state(view: AdbShareView, now: Long): String = when {
    view.phase != "offered" -> view.message?.let { "正在连接 station：$it" } ?: "正在连接 station…"
    view.adb == "connected" -> "agent 可以用 adb 了" + (view.until?.let { " · 还剩 ${((it - now) / 60_000).coerceAtLeast(0)} 分钟" } ?: "")
    view.adb == "unpaired" -> "这台 station 还没和手机配对"
    view.adb == "unauthorized" -> "手机上弹出了「允许 USB 调试吗？」，点允许"
    view.adb == "off" -> "手机上的无线调试没开"
    view.adb == "missing" -> "station 上没有 adb"
    view.adb == "failed" -> "adb 没连上"
    else -> "正在接上 adb…"
}
