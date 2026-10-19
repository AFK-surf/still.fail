// The Feishu (Lark) side of connects, as the narrow web's web/src/mobile/FeishuConnect.tsx and Connects.tsx: the new
// connect's platform step and its Feishu path (the core's `connectFlow`), a step a screen; a Feishu connect's App Secret
// replaced; the QR code a Feishu bot is made by.
package fail.still.android.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import fail.still.android.AppState
import fail.still.android.LocalApp
import fail.still.android.Screen
import fail.still.android.data.Connect
import fail.still.android.data.ConnectFlowView
import fail.still.android.data.QrCode
import fail.still.android.data.errorText
import fail.still.android.data.t
import fail.still.android.ui.Button
import fail.still.android.ui.C
import fail.still.android.ui.Field
import fail.still.android.ui.PickRow
import fail.still.android.ui.RowsCard
import fail.still.android.ui.SheetGrab
import fail.still.android.ui.SheetHead
import fail.still.android.ui.SheetSpec
import fail.still.android.ui.SlackMark
import fail.still.android.ui.Smooth
import fail.still.android.ui.Spinner
import fail.still.core.CoreException
import kotlinx.coroutines.launch
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

/** The wizard's steps drawn here; the rest are Slack's (Connects.kt). */
internal val FEISHU_STEPS = setOf("platform", "feishuBind", "feishuWay", "feishuScan", "feishuApp", "done")

/** Where a connect is, by name: its workspace or tenant, else its platform. */
internal fun placeOf(c: Connect): String =
    c.team ?: if (c.kind == "feishu") (if (c.feishu?.domain == "lark") "Lark" else t("web-mobile.connects.feishu.name")) else "Slack"

/**
 * One of the steps drawn here; `bind`: the model and mode pickers, as Slack's last step has them. Its connect added
 * (step `done`), its page replaces this one.
 */
@Composable
internal fun FeishuSteps(station: String, view: ConnectFlowView, flow: ConnectFlow, bind: @Composable () -> Unit) {
    val app = LocalApp.current
    val context = LocalContext.current
    val open = { url: String ->
        try { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
        catch (_: android.content.ActivityNotFoundException) { app.toast = t("android-chat.link.failed") }
    }
    val made = if (view.step == "done") view.feishu?.connect else null
    LaunchedEffect(made) {
        if (made == null) return@LaunchedEffect
        app.toast = t("web-mobile.connects.feishu.added")
        app.replace(Screen.Connect(station, made))
    }
    val f = view.feishu ?: return
    val busy = flow.busy
    when (view.step) {
        "platform" -> {
            val platform = view.platform ?: "slack"
            val feishu = "feishu" in view.platforms
            RowsCard {
                PickRow("Slack", t("web-mobile.connects.feishu.slackNote"), checked = platform == "slack", leading = { SlackMark(20.dp) }) { flow.edit { put("platform", "slack") } }
                PickRow(
                    t("web-mobile.connects.feishu.name"), if (feishu) t("web-mobile.connects.feishu.feishuNote") else t("web-mobile.connects.feishu.update"),
                    checked = platform == "feishu", enabled = feishu, leading = { SlackMark(20.dp, "feishu") },
                ) { flow.edit { put("platform", "feishu") } }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(t("android-settings.flow.next"), primary = true) { flow.go(if (platform == "feishu" && feishu) "feishuBind" else "team") }
            }
        }
        "feishuBind" -> {
            bind()
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(t("android-settings.flow.next"), primary = true, enabled = view.canCreate) { flow.go("feishuWay") }
            }
        }
        "feishuWay" -> {
            RowsCard {
                PickRow(t("web-mobile.connects.feishu.scan"), t("web-mobile.connects.feishu.scanNote"), checked = f.way == "scan") { flow.edit { putJsonObject("feishu") { put("way", "scan") } } }
                PickRow(t("web-mobile.connects.feishu.app"), t("web-mobile.connects.feishu.appNote"), checked = f.way == "app") { flow.edit { putJsonObject("feishu") { put("way", "app") } } }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(t("android-settings.flow.next"), primary = true, busy = busy) { if (f.way == "app") flow.go("feishuApp") else flow.act("register") }
            }
        }
        "feishuApp" -> OwnApp(flow, view)
        // Scanning, or its connect added (its page on the way).
        else -> if (view.step == "feishuScan" || f.registration != null) {
            val r = f.registration
            val waiting = r?.state == "waiting"
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (f.creating || (r?.state == "done" && f.error == null && f.connect == null)) Spinner(inline = true)
                f.stateText?.let { Text(it, fontSize = 14.sp, color = if (f.failed || f.error != null) C.red else C.muted) }
            }
            if (waiting) {
                Text(t("web-mobile.connects.feishu.openInFeishu"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { open(r!!.url) })
                f.qr?.let { code -> Box(Modifier.fillMaxWidth().padding(vertical = 4.dp), contentAlignment = Alignment.Center) { Qr(code, 220.dp, t("web-mobile.connects.feishu.qr")) } }
                Text(t("web-mobile.connects.feishu.scanHint"), fontSize = 12.sp, color = C.muted)
            }
            f.error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            if (f.failed) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(t("web-mobile.connects.feishu.newQr"), primary = true, busy = busy) { flow.act("register") }
            }
            else if (f.error != null) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                Button(t("web-mobile.connects.feishu.retry"), primary = true, busy = busy || f.creating) { flow.act("create") }
            }
        }
    }
}

/** An app of one's own: its App ID and Secret (Lark or not), verified, then the connect added with it. */
@Composable
private fun OwnApp(flow: ConnectFlow, view: ConnectFlowView) {
    val f = view.feishu ?: return
    // What was typed, echoed at once; the draft and whether it verified are the core's.
    var appId by remember(flow) { mutableStateOf<String?>(null) }
    var appSecret by remember(flow) { mutableStateOf<String?>(null) }
    Text(t("web-mobile.connects.feishu.appHint"), fontSize = 13.sp, color = C.muted)
    FormLabel("App ID")
    Field(appId ?: f.appId, { appId = it; flow.edit { putJsonObject("feishu") { put("appId", it) } } }, "cli_…", mono = true, max = 64)
    FormLabel("App Secret")
    SecretField(appSecret ?: f.appSecret, { appSecret = it; flow.edit { putJsonObject("feishu") { put("appSecret", it) } } }, "")
    Row(
        Modifier.fillMaxWidth().clip(Smooth(14.dp)).background(C.chip).clickable { flow.edit { putJsonObject("feishu") { put("lark", !f.lark) } } }.padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(t("web-mobile.connects.feishu.lark"), fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = C.ink)
            Text(t("web-mobile.connects.feishu.larkNote"), fontSize = 13.sp, color = C.muted)
        }
        Switch(f.lark)
    }
    val identity = f.identity
    if (f.verified && identity != null) {
        val tenant = identity.tenant?.name
        Text(if (tenant != null) t("web-mobile.connects.feishu.verified", "bot" to identity.botName, "tenant" to tenant) else t("web-mobile.connects.feishu.verifiedBot", "bot" to identity.botName), fontSize = 12.sp, color = C.green)
    }
    f.errors.forEach { Text(it, fontSize = 13.sp, color = C.red) }
    f.error?.let { Text(it, fontSize = 13.sp, color = C.red) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        if (f.verified) Button(t("android-settings.flow.create"), primary = true, busy = flow.busy || f.creating) { flow.act("create") }
        else Button(t("web-mobile.connects.feishu.verify"), primary = true, busy = flow.busy, enabled = f.canVerify) { flow.act("verify") }
    }
}

/** A QR code the core made (its dark modules row by row), on white whatever the theme, four modules of quiet zone around. */
@Composable
internal fun Qr(code: QrCode, size: Dp, label: String) {
    val quiet = 4
    Canvas(Modifier.size(size).clip(Smooth(12.dp)).background(Color.White).semantics { contentDescription = label }) {
        val n = code.size.toInt() + quiet * 2
        // Whole pixels a module, centred: no seams between them.
        val cell = kotlin.math.floor(this.size.width / n)
        val start = (this.size.width - cell * n) / 2 + cell * quiet
        code.rows.forEachIndexed { y, row ->
            var x = 0
            while (x < row.length) {
                if (row[x] != '1') { x++; continue }
                var end = x
                while (end + 1 < row.length && row[end + 1] == '1') end++
                drawRect(Color.Black, Offset(start + x * cell, start + y * cell), Size((end - x + 1) * cell, cell))
                x = end + 1
            }
        }
    }
}

/** Replaces a Feishu connect's App Secret: verified by its station before it is kept (so the sheet waits), then it reconnects. */
internal fun openFeishuSecret(app: AppState, station: String, connect: Connect) {
    app.sheet = SheetSpec(0.5f, draggable = true) {
        var secret by remember { mutableStateOf("") }
        var error by remember { mutableStateOf<String?>(null) }
        val busy = app.isDoing("feishu.putSecret", "station" to station, "id" to connect.id)
        SheetGrab()
        SheetHead(t("web-mobile.connects.feishu.replace"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(t("web-mobile.connects.feishu.replaceNote"), fontSize = 12.sp, color = C.muted)
            FormLabel("App Secret")
            SecretField(secret, { secret = it; error = null }, connect.feishu?.appSecret.orEmpty())
            error?.let { Text(it, fontSize = 13.sp, color = C.red) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
                Button(t("common.cancel"), primary = false) { app.sheet = null }
                Button(t("android-settings.tokens.save"), primary = true, busy = busy, enabled = secret.isNotBlank()) {
                    val value = secret.trim()
                    app.scope.launch {
                        try {
                            app.api(station).putFeishuSecret(connect.id, value)
                            app.toast = t("web-mobile.connects.feishu.secretSaved")
                            app.sheet = null
                        } catch (e: CoreException) { error = errorText(e) }
                    }
                }
            }
        }
    }
}
