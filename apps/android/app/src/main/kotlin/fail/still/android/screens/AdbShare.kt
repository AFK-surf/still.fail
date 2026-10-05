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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
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
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.NavBar
import fail.still.android.ui.SectionHeader
import fail.still.android.ui.t
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
        NavBar("Station", app::pop, t("android-misc.adb.title"), sub = { Text(name, fontSize = 11.sp, color = C.muted, maxLines = 1) })
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(top = 12.dp)) {
            Text(
                t("android-misc.adb.about", "name" to name),
                fontSize = 13.sp, color = C.muted, modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 10.dp),
            )
            if (!AdbShare.supported) {
                ListCard { ListRow { Text(t("android-misc.adb.unsupported"), fontSize = 15.sp, color = C.muted) } }
                return@Column
            }
            ListCard {
                // Lent or not, as settings' switches are; what it is doing under the title.
                ListRow(onClick = { if (here) app.act(t("android-misc.adb.stopWhat")) { app.core.call("adb.stop") } else start() }) {
                    Column(Modifier.weight(1f)) {
                        Text(t("android-misc.adb.title"), fontSize = 15.sp, color = C.ink)
                        val sub = when {
                            here -> state(view!!, now)
                            elsewhere -> t("android-misc.adb.elsewhere")
                            // Why it stopped by itself (its hour up, the station too old).
                            view?.sharing == false && view.message != null -> view.message
                            else -> t("android-misc.adb.hour")
                        }
                        Text(sub, fontSize = 13.sp, color = if (here && view!!.adb in setOf("missing", "failed")) C.red else C.muted)
                    }
                    Switch(here)
                }
                if (here) {
                    view!!.serial?.takeIf { view.adb == "connected" }?.let { serial ->
                        ListRow {
                            Text(t("android-misc.adb.agentsUse"), fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                            SelectionContainer { Text("adb -s $serial", fontSize = 13.sp, fontFamily = FontFamily.Monospace, color = C.muted) }
                        }
                    }
                    // What the station said, when it says more than the line above.
                    if (view.adb != "connected") view.message?.takeIf { it.isNotBlank() && it != state(view, now) && !state(view, now).endsWith(it) }?.let {
                        ListRow { Text(it, fontSize = 13.sp, color = C.muted) }
                    }
                }
            }
            SectionHeader(t("android-misc.adb.phone"), start = 24.dp)
            ListCard {
                Need(t("android-misc.adb.developer"), phone.developer, if (phone.developer) t("android-misc.adb.on") else t("android-misc.adb.developer.how"))
                Need(t("android-misc.adb.wifi"), phone.wifi, if (phone.wifi) t("android-misc.adb.wifi.on") else t("android-misc.adb.wifi.needed"))
                ListRow(onClick = {
                    if (!phone.wireless && AdbShare.switchOn(context)) phone = phone.copy(wireless = true) else AdbShare.openWireless(context)
                }) {
                    Text(t("android-misc.adb.wireless"), fontSize = 15.sp, color = C.ink, modifier = Modifier.weight(1f))
                    Text(if (phone.wireless) t("android-misc.adb.on") else if (phone.canSwitch) t("android-misc.adb.wireless.turnOn") else t("android-misc.adb.wireless.settings"), fontSize = 14.sp, color = if (phone.wireless) C.muted else C.accent)
                }
            }
            if (here && view!!.adb == "unpaired") Pairing(view)
            if (here && view!!.adb == "connected" && !phone.canSwitch) {
                val busy = app.isDoing("adb.grant")
                SectionHeader(t("android-misc.adb.later"), start = 24.dp)
                ListCard {
                    ListRow(onClick = if (busy) null else ({
                        app.act(t("android-misc.adb.grantWhat"), t("android-misc.adb.granted")) {
                            app.core.call("adb.grant")
                            phone = phone.copy(canSwitch = AdbShare.canSwitch(context))
                        }
                    })) {
                        Column(Modifier.weight(1f)) {
                            Text(t("android-misc.adb.grant.title"), fontSize = 15.sp, color = C.ink)
                            Text(t("android-misc.adb.grant.note"), fontSize = 13.sp, color = C.muted)
                        }
                        DoingMark(busy, app.failedOf("adb.grant"), 14.dp)
                        Switch(false)
                    }
                }
            }
            Text(
                t("android-misc.adb.warning"),
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
    val busy = app.isDoing("adb.pair")
    SectionHeader(t("android-misc.adb.pair.title"), start = 24.dp)
    ListCard {
        ListRow(onClick = { AdbShare.openWireless(context, beside = true) }) {
            Column(Modifier.weight(1f)) {
                Text(t("android-misc.adb.pair.open"), fontSize = 15.sp, color = C.ink)
                Text(t("android-misc.adb.pair.open.note"), fontSize = 13.sp, color = C.muted)
            }
            Text(t("android-misc.adb.pair.go"), fontSize = 14.sp, color = C.accent)
        }
        // Split screen: the code typed here instead (in full screen, coming back here closes the dialog).
        ListRow(onClick = if (view.pairPort == null || busy) null else ({
            ask(app, t("android-misc.adb.pair.ask"), "", t("android-misc.adb.code"), t("android-misc.adb.pair.action"), hint = t("android-misc.adb.pair.hint")) { code ->
                app.core.call("adb.pair", buildJsonObject { put("code", code.filter(Char::isDigit)) })
                app.toast = t("android-misc.adb.paired")
            }
        })) {
            Column(Modifier.weight(1f)) {
                Text(t("android-misc.adb.pair.here"), fontSize = 15.sp, color = if (view.pairPort == null) C.subtle else C.ink)
                Text(if (view.pairPort == null) t("android-misc.adb.pair.here.wait") else t("android-misc.adb.pair.here.split"), fontSize = 13.sp, color = C.muted)
            }
            DoingMark(busy, app.failedOf("adb.pair"), 14.dp)
        }
    }
}

/** How the lending stands, in a line. */
private fun state(view: AdbShareView, now: Long): String = when {
    view.phase != "offered" -> view.message?.let { t("android-misc.adb.connecting.why", "why" to it) } ?: t("android-misc.adb.connecting")
    view.adb == "connected" -> view.until?.let { t("android-misc.adb.connected.left", "n" to ((it - now) / 60_000).coerceAtLeast(0)) } ?: t("android-misc.adb.connected")
    view.adb == "unpaired" -> t("android-misc.adb.unpaired")
    view.adb == "unauthorized" -> t("android-misc.adb.unauthorized")
    view.adb == "off" -> t("android-misc.adb.off")
    view.adb == "missing" -> t("android-misc.adb.missing")
    view.adb == "failed" -> t("android-misc.adb.failed")
    else -> t("android-misc.adb.attaching")
}
