// A connect's Slack app, edited from here (the desktop's web/src/pages/SlackApp.tsx): its name, description, colour,
// icon and permissions are written into the app's manifest with the viewer's app configuration token for its Slack
// workspace. When permissions change, Slack asks a person to approve them; that is the only step left in Slack. A new
// app's look (a picture picked from still.fail's buddies or the model makers, or uploaded, on its colour) is set the same
// way when it is made (Connects.kt → NewConnectScreen, as web/src/mobile/Connects.tsx → AppLook).
package fail.still.android.screens

import fail.still.android.BuildConfig
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Rect
import android.net.Uri
import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import fail.still.android.LocalApp
import fail.still.android.R
import fail.still.android.data.Buddy
import fail.still.android.data.StillFailJson
import fail.still.android.data.Topics
import fail.still.android.data.rememberTopic
import fail.still.android.ui.C
import fail.still.android.ui.IconIn
import fail.still.android.ui.Icons
import fail.still.android.ui.ListCard
import fail.still.android.ui.ListRow
import fail.still.android.ui.Loading
import fail.still.android.ui.NavBar
import fail.still.android.ui.SectionHeader
import fail.still.android.data.t
import fail.still.core.CoreException
import java.io.ByteArrayOutputStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject

// ── what Slack has ─────────────────────────────────────────────────────

@Serializable
internal class SlackAppLinksView(val settings: String = "", val install: String = "", val appToken: String = "", val oauth: String = "")

@Serializable
internal class SlackAppSettings(
    val name: String = "", val displayName: String = "", val description: String = "", val longDescription: String = "",
    val backgroundColor: String = "", val groups: Map<String, Boolean> = emptyMap(),
)

/** A connect's Slack app as the `slackApp` topic has it: no_app | no_config_token | ok | error. */
@Serializable
internal class SlackAppView(val state: String, val appId: String? = null, val links: SlackAppLinksView? = null, val settings: SlackAppSettings? = null, val error: String? = null)

/** Permission groups in plain words (web/src/pages/SlackApp.tsx → GROUPS; the station's SLACK_GROUPS), in their order. */
internal val SLACK_GROUP_WORDS: List<Pair<String, Pair<String, String>>>
    get() = listOf("base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras", "canvases", "lists", "topics", "usergroups", "search", "connect", "more")
        .map { it to (t("android-settings.slack.group.$it") to t("android-settings.slack.group.$it.note")) }

/** The groups in sections, as the form shows them (web/src/pages/SlackApp.tsx → SECTIONS). */
internal val SLACK_SECTIONS
    get() = listOf(
        t("android-settings.slack.section.messages") to listOf("base", "public", "dm", "customize", "reactions"),
        t("android-settings.slack.section.channels") to listOf("channels", "topics", "connect"),
        t("android-settings.slack.section.files") to listOf("files", "canvases", "lists"),
        t("android-settings.slack.section.people") to listOf("people", "usergroups", "search"),
        t("android-settings.slack.section.other") to listOf("extras", "more"),
    )

/** A Slack app's settings being edited: what its form shows, and what it started as. */
internal class AppDraft(start: SlackAppSettings, private val onEdit: (JsonObject) -> Unit = {}) {
    val start = start
    private var nameEcho by mutableStateOf(start.name)
    var name: String
        get() = nameEcho
        set(value) { nameEcho = value; onEdit(settings()) }
    private var descriptionEcho by mutableStateOf(start.description)
    var description: String
        get() = descriptionEcho
        set(value) { descriptionEcho = value; onEdit(settings()) }
    private var colorEcho by mutableStateOf(start.backgroundColor)
    var color: String
        get() = colorEcho
        set(value) { colorEcho = value; onEdit(settings()) }
    private var groupsEcho by mutableStateOf(SLACK_GROUP_WORDS.associate { (g, _) -> g to (start.groups[g] ?: false) })
    var groups: Map<String, Boolean>
        get() = groupsEcho
        set(value) { groupsEcho = value; onEdit(settings()) }

    /** The settings as the station takes them (the name in messages is the app's name). */
    fun settings(): JsonObject = buildJsonObject {
        put("name", name.trim()); put("displayName", name.trim()); put("description", description.trim()); put("longDescription", start.longDescription)
        put("backgroundColor", color); putJsonObject("groups") { groups.forEach { (g, on) -> put(g, on) } }
    }

    /** Only what changed, for a write to an app that exists. */
    fun changes(): JsonObject = buildJsonObject {
        if (name.trim() != start.name) { put("name", name.trim()); put("displayName", name.trim()) }
        if (description.trim() != start.description) put("description", description.trim())
        if (color != start.backgroundColor) put("backgroundColor", color)
        if (SLACK_GROUP_WORDS.any { (g, _) -> groups[g] != (start.groups[g] ?: false) }) putJsonObject("groups") { groups.forEach { (g, on) -> put(g, on) } }
    }
}

/** What a new app starts as: every permission on; its colour and icon come from its first avatar. */
internal val NEW_APP = SlackAppSettings(
    name = BuildConfig.APP_NAME, displayName = BuildConfig.APP_NAME, description = "Coding agent in your threads (${BuildConfig.APP_NAME})", backgroundColor = "#F3E3D3",
    groups = SLACK_GROUP_WORDS.associate { (g, _) -> g to true },
)

// ── avatars ────────────────────────────────────────────────────────────

/** A picture to start from: a buddy (assets/avatars/<id>.webp, the web's) or a model maker's mark, on a colour of its own. */
internal class AppAvatar(val id: String, val label: String, val bg: String, val mark: Int? = null, val mono: Boolean = false)

/** still.fail's buddy at the jobs a bot is made for, so people tell bots apart by what they do (the core's list, `buddies`). */
private suspend fun buddies(core: fail.still.core.StillFailCore): List<AppAvatar> = try {
    StillFailJson.decodeFromJsonElement(ListSerializer(Buddy.serializer()), core.call("buddies", kotlinx.serialization.json.JsonObject(emptyMap())))
        .map { AppAvatar(it.id, it.label, it.bg) }
} catch (_: CoreException) { emptyList() }

/** The model makers' marks, each on its own colour. */
private val MAKER_AVATARS get() = listOf(
    AppAvatar("anthropic", "Anthropic", "#D97757", R.drawable.maker_anthropic, mono = true),
    AppAvatar("openai", "OpenAI", "#0D0D0D", R.drawable.maker_openai, mono = true),
    AppAvatar("gemini", "Gemini", "#FFFFFF", R.drawable.maker_gemini),
    AppAvatar("deepseek", "DeepSeek", "#FFFFFF", R.drawable.maker_deepseek),
    AppAvatar("qwen", "Qwen", "#FFFFFF", R.drawable.maker_qwen),
    AppAvatar("zhipu", t("android-settings.slack.zhipu"), "#FFFFFF", R.drawable.maker_zhipu),
    AppAvatar("kimi", "Kimi", "#0D0D0D", R.drawable.maker_kimi, mono = true),
    AppAvatar("minimax", "MiniMax", "#FFFFFF", R.drawable.maker_minimax),
    AppAvatar("xai", "xAI", "#0D0D0D", R.drawable.maker_xai, mono = true),
)

private val HEX = Regex("^#[0-9a-fA-F]{6}$")

private fun parseColor(hex: String, fallback: Int = 0xFF7A2E0E.toInt()): Int = if (HEX.matches(hex)) android.graphics.Color.parseColor(hex) else fallback

/** A picture as Slack takes an icon: a JPEG, as a data URL. */
private fun dataUrl(bitmap: Bitmap): String {
    val out = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out)
    return "data:image/jpeg;base64," + Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
}

/** Where a picture has anything drawn (not transparent), in its own pixels. */
private fun drawnBox(image: Bitmap): Rect {
    val size = 256
    val small = Bitmap.createScaledBitmap(image, size, size, true)
    var left = size; var top = size; var right = -1; var bottom = -1
    for (y in 0 until size) for (x in 0 until size) {
        if ((small.getPixel(x, y) ushr 24) > 16) { left = minOf(left, x); right = maxOf(right, x); top = minOf(top, y); bottom = maxOf(bottom, y) }
    }
    if (right < 0) return Rect(0, 0, image.width, image.height)
    val k = image.width / size.toFloat()
    return Rect((left * k).toInt(), (top * k).toInt(), ((right + 1) * k).toInt(), ((bottom + 1) * k).toInt())
}

/** An avatar as the app's icon: 1024 px, its colour behind it, a buddy as large as fits (92%), a maker's mark smaller (white when mono). */
private suspend fun renderAvatar(context: Context, avatar: AppAvatar, bg: String): Bitmap = withContext(Dispatchers.Default) {
    val icon = Bitmap.createBitmap(1024, 1024, Bitmap.Config.ARGB_8888)
    val g = Canvas(icon)
    g.drawColor(parseColor(bg, parseColor(avatar.bg)))
    if (avatar.mark != null) {
        val mark = ContextCompat.getDrawable(context, avatar.mark)!!.mutate()
        if (avatar.mono) mark.setTint(android.graphics.Color.WHITE)
        val at = (1024 - 560) / 2
        mark.setBounds(at, at, at + 560, at + 560)
        mark.draw(g)
    } else {
        val image = context.assets.open("avatars/${avatar.id}.webp").use { BitmapFactory.decodeStream(it) }
        val box = drawnBox(image)
        val scale = 1024 * 0.92f / maxOf(box.width(), box.height())
        val w = box.width() * scale; val h = box.height() * scale
        g.drawBitmap(image, box, android.graphics.RectF((1024 - w) / 2, (1024 - h) / 2, (1024 + w) / 2, (1024 + h) / 2), android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
    }
    icon
}

/** A picked picture cropped to a centred square and scaled to 1024 px (Slack wants 512–2000); what was clear is white. */
private suspend fun toIcon(context: Context, uri: Uri): Bitmap? = withContext(Dispatchers.IO) {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
    var sample = 1
    while (minOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 1024) sample *= 2
    val image = context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) } ?: return@withContext null
    val side = minOf(image.width, image.height)
    val icon = Bitmap.createBitmap(1024, 1024, Bitmap.Config.ARGB_8888)
    val g = Canvas(icon)
    g.drawColor(android.graphics.Color.WHITE)
    val sx = (image.width - side) / 2; val sy = (image.height - side) / 2
    g.drawBitmap(image, Rect(sx, sy, sx + side, sy + side), Rect(0, 0, 1024, 1024), android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
    icon
}

/** The colour a picture sits on best: the average of its edge. */
private fun edgeColour(bitmap: Bitmap): String {
    val s = Bitmap.createScaledBitmap(bitmap, 32, 32, true)
    var r = 0L; var gr = 0L; var b = 0L; var n = 0
    for (i in 0 until 32) for ((x, y) in listOf(i to 0, i to 31, 0 to i, 31 to i)) {
        val p = s.getPixel(x, y)
        r += (p shr 16) and 0xFF; gr += (p shr 8) and 0xFF; b += p and 0xFF; n++
    }
    return String.format("#%02X%02X%02X", r / n, gr / n, b / n)
}

/** The icon picked for an app: the picture as shown, and as it goes to Slack. */
internal class IconPick(val bitmap: ImageBitmap, val data: String)

/**
 * An app's look, as the web's AppLook / AppFields have it: an avatar picked from still.fail's buddies or the model makers,
 * or uploaded, on its colour; the colour follows the avatar until it is set by hand (and can go back). `fresh`: a new
 * app, which starts as the general helper.
 */
@Composable
internal fun AppLook(draft: AppDraft, icon: IconPick?, onIcon: (IconPick?, String?) -> Unit, fresh: Boolean) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val core = LocalApp.current.core
    var buddyList by remember { mutableStateOf<List<AppAvatar>>(emptyList()) }
    LaunchedEffect(Unit) { buddyList = buddies(core) }
    // What was picked: an avatar (its id), or an upload (its edge's colour).
    var picked by remember { mutableStateOf<AppAvatar?>(null) }
    var uploadBg by remember { mutableStateOf<String?>(null) }
    var colourSet by remember { mutableStateOf(false) }
    val recommended = picked?.bg ?: uploadBg
    val draw = { a: AppAvatar?, bg: String ->
        if (a != null) scope.launch {
            try { val b = renderAvatar(context, a, bg); onIcon(IconPick(b.asImageBitmap(), dataUrl(b)), null) } catch (_: Exception) { onIcon(null, t("android-settings.slack.drawFailed")) }
        }
    }
    val pick = { a: AppAvatar ->
        picked = a; uploadBg = null
        val bg = if (colourSet) draft.color else a.bg
        draft.color = bg
        draw(a, bg)
    }
    val colour = { bg: String, byHand: Boolean ->
        colourSet = byHand
        draft.color = bg
        if (HEX.matches(bg)) draw(picked, bg)
    }
    // A new app starts as the general helper (else the first avatar), on its colour.
    LaunchedEffect(buddyList) { if (fresh && icon == null && picked == null) (buddyList.firstOrNull { it.id == "general-helper" } ?: buddyList.firstOrNull())?.let { pick(it) } }
    val upload = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val b = try { toIcon(context, uri) } catch (_: Exception) { null }
            if (b == null) onIcon(null, t("android-settings.slack.imageFailed"))
            else {
                val bg = edgeColour(b)
                picked = null; uploadBg = bg
                onIcon(IconPick(b.asImageBitmap(), dataUrl(b)), null)
                if (!colourSet) draft.color = bg
            }
        }
    }
    val openPicker = { upload.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        FormLabel(t("android-settings.slack.icon"))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Box(Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)).background(Color(parseColor(draft.color, C.chip.toArgbInt()))).clickable { openPicker() }, contentAlignment = Alignment.Center) {
                if (icon != null) Image(icon.bitmap, t("android-settings.slack.icon"), Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                else Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    IconIn(Icons.ImageUpload, 20.dp, C.muted)
                    Text(if (fresh) t("android-settings.slack.upload") else t("android-settings.slack.keep"), fontSize = 11.sp, color = C.muted)
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(t("android-settings.slack.iconNote"), fontSize = 13.sp, color = C.muted)
                Text(t("android-settings.slack.uploadImage"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { openPicker() })
            }
        }
        AvatarGrid(buddyList + MAKER_AVATARS, picked?.id) { pick(it) }
        FormLabel(t("android-settings.slack.background"))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(Color(parseColor(draft.color))))
            Field(draft.color, { colour(it.trim().uppercase(), true) }, "#RRGGBB", mono = true, modifier = Modifier.weight(1f))
            if (recommended != null && colourSet && !recommended.equals(draft.color, ignoreCase = true)) {
                Text(t("android-settings.slack.recommended"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { colour(recommended, false) })
            }
        }
    }
}

private fun Color.toArgbInt(): Int = android.graphics.Color.argb((alpha * 255).toInt(), (red * 255).toInt(), (green * 255).toInt(), (blue * 255).toInt())

/** The avatars in a full grid, tiles at least 48 across, 10 apart; the picked one ringed in the accent. */
@Composable
private fun AvatarGrid(list: List<AppAvatar>, picked: String?, onPick: (AppAvatar) -> Unit) {
    val context = LocalContext.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gap = 10.dp
        val columns = maxOf(1, ((maxWidth + gap) / (48.dp + gap)).toInt())
        val side = (maxWidth - gap * (columns - 1)) / columns
        Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            list.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                    row.forEach { a ->
                        val on = a.id == picked
                        Box(
                            Modifier.size(side).let { if (on) it.border(2.dp, C.accent, RoundedCornerShape(14.dp)).padding(4.dp) else it }
                                .clip(RoundedCornerShape(if (on) 9.dp else 12.dp)).background(Color(parseColor(a.bg))).clickable { onPick(a) },
                            contentAlignment = Alignment.Center,
                        ) {
                            if (a.mark != null) Image(painterResource(a.mark), a.label, Modifier.size(side * 0.55f), colorFilter = if (a.mono) ColorFilter.tint(Color.White) else null)
                            else {
                                val thumb = remember(a.id) {
                                    try { context.assets.open("avatars/${a.id}.thumb.webp").use { BitmapFactory.decodeStream(it) }?.asImageBitmap() } catch (_: Exception) { null }
                                }
                                if (thumb != null) Image(thumb, a.label, Modifier.fillMaxSize().graphicsLayer { scaleX = 1.18f; scaleY = 1.18f }, contentScale = ContentScale.Crop)
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
internal fun FormLabel(text: String) = Text(text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = C.ink)

// ── the page ───────────────────────────────────────────────────────────

/**
 * A connect's Slack app: read from Slack through the station (the `slackApp` topic); without the viewer's configuration
 * token for its Slack workspace, a way to add one; otherwise its look and permissions, applied to Slack at once.
 */
@Composable
fun SlackAppScreen(station: String, connect: String) {
    val app = LocalApp.current
    val topic by rememberTopic<SlackAppView>(app.core, Topics.slackApp(station, connect))
    val view = topic.value
    val context = LocalContext.current
    val open = { url: String -> context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    var adding by remember { mutableStateOf(false) }
    // What the last write said (Slack wants the new permissions approved; the icon did not take): kept here, as the
    // form below is made again from what Slack has after a write.
    val approve = remember(station, connect) { mutableStateOf(false) }
    val iconError = remember(station, connect) { mutableStateOf<String?>(null) }
    Column(Modifier.fillMaxSize()) {
        NavBar(if (adding) "Slack app" else t("android-settings.connects.title"), { if (adding) adding = false else app.pop() }, if (adding) t("android-settings.slack.addToken") else "Slack app", sub = { Text(t("android-settings.slack.sub"), fontSize = 11.sp, color = C.muted) })
        androidx.activity.compose.BackHandler(enabled = adding) { adding = false }
        if (view == null) return Loading(topic.error?.message ?: t("android-settings.slack.reading"))
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 18.dp).padding(top = 8.dp, bottom = 30.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (adding) {
                ConfigTokenSteps(station) { adding = false }
                return@Column
            }
            val settings = view.settings
            when {
                view.state == "no_app" -> Text(view.error?.let { t("android-settings.slack.noApp", "error" to it) } ?: t("android-settings.slack.notConnected"), fontSize = 14.sp, color = C.muted)
                view.state == "no_config_token" -> {
                    Text(t("android-settings.slack.needToken"), fontSize = 14.sp, color = C.muted)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button(t("android-settings.slack.addToken"), primary = true) { adding = true } }
                }
                view.state == "error" || settings == null -> {
                    Text(t("android-settings.slack.readFailed", "error" to (view.error ?: "")), fontSize = 14.sp, color = C.red)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button(t("android-settings.slack.changeToken"), primary = false) { adding = true } }
                }
                // Keyed by what Slack has: a change there (or a write from here) starts the form again from it.
                else -> androidx.compose.runtime.key(StillFailJson.encodeToString(SlackAppSettings.serializer(), settings)) {
                    AppForm(station, connect, settings, view.links, open, approve, iconError)
                }
            }
            view.links?.settings?.takeIf { it.isNotEmpty() }?.let { url ->
                Text(t("android-settings.slack.open"), fontSize = 14.sp, color = C.accent, modifier = Modifier.clickable { open(url) }.padding(vertical = 4.dp))
            }
        }
    }
}

@Composable
private fun AppForm(station: String, connect: String, settings: SlackAppSettings, links: SlackAppLinksView?, open: (String) -> Unit, approveState: MutableState<Boolean>, iconErrorState: MutableState<String?>) {
    val app = LocalApp.current
    val scope = rememberCoroutineScope()
    val draft = remember { AppDraft(settings) }
    var icon by remember { mutableStateOf<IconPick?>(null) }
    var iconError by iconErrorState
    var approve by approveState
    val busy = app.isDoing("connect.putSlackApp", "station" to station, "connect" to connect)
    var error by remember { mutableStateOf<String?>(null) }
    var perms by remember { mutableStateOf(false) }
    val changes = draft.changes()
    val dirty = changes.isNotEmpty() || icon != null
    if (approve && links != null) Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(C.blue.copy(alpha = 0.10f)).padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IconIn(Icons.ShieldCheck, 16.dp, C.blue)
            Text(t("android-settings.slack.approveNote"), fontSize = 13.sp, color = C.ink, modifier = Modifier.weight(1f))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) { Button(t("android-settings.slack.approve"), primary = true) { approve = false; open(links.install) } }
    }
    FormLabel(t("android-settings.slack.name"))
    Field(draft.name, { draft.name = it }, t("android-settings.slack.name"))
    FormLabel(t("android-settings.slack.description"))
    Field(draft.description, { draft.description = it.take(140) }, t("android-settings.slack.descriptionPlaceholder"))
    AppLook(draft, icon, { i, e -> icon = i; iconError = e }, fresh = false)
    iconError?.let { Text(it, fontSize = 13.sp, color = C.red) }
    // Permissions, folded: changed now and then.
    val on = draft.groups.count { it.value }
    Row(Modifier.fillMaxWidth().clickable { perms = !perms }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        IconIn(if (perms) Icons.ChevronDown else Icons.ChevronRight, 14.dp, C.muted)
        Text(t("android-settings.slack.perms", "on" to on, "n" to SLACK_GROUP_WORDS.size), fontSize = 14.sp, color = C.muted, modifier = Modifier.weight(1f))
        if (on < SLACK_GROUP_WORDS.size) Text(t("android-settings.slack.allOn"), fontSize = 14.sp, color = C.accent,
            modifier = Modifier.clickable { draft.groups = SLACK_GROUP_WORDS.associate { (g, _) -> g to true } })
    }
    val words = SLACK_GROUP_WORDS.toMap()
    // Names only, as the models of a profile are picked (Profiles.kt ModelsSection): what each allows is on the web's hover.
    if (perms) SLACK_SECTIONS.forEach { (title, groups) ->
        val all = groups.all { draft.groups[it] == true }
        Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(title, fontSize = 13.sp, color = C.muted)
            Text(if (all) t("android-settings.none") else t("android-settings.all"), fontSize = 13.sp, color = C.accent,
                modifier = Modifier.clickable { draft.groups = draft.groups + groups.associateWith { it == "base" || !all } })
        }
        groups.forEach { g ->
            val checked = draft.groups[g] ?: false
            val fixed = g == "base"
            Row(
                Modifier.fillMaxWidth().clickable(enabled = !fixed) { draft.groups = draft.groups + (g to !checked) }.padding(vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // Always on, no choice: a tick without a box.
                if (fixed) Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) { IconIn(Icons.Check, 16.dp, C.accent) }
                else Box(Modifier.size(20.dp).clip(RoundedCornerShape(6.dp)).background(if (checked) C.accent else C.chip), contentAlignment = Alignment.Center) {
                    if (checked) IconIn(Icons.Check, 13.dp, C.bg)
                }
                Text(words.getValue(g).first, fontSize = 14.sp, color = if (checked) C.ink else C.muted)
            }
        }
    }
    error?.let { Text(it, fontSize = 13.sp, color = C.red) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) {
        if (dirty) Button(t("android-settings.slack.revert"), primary = false) {
            draft.name = settings.name; draft.description = settings.description; draft.color = settings.backgroundColor
            draft.groups = SLACK_GROUP_WORDS.associate { (g, _) -> g to (settings.groups[g] ?: false) }; icon = null
        }
        Button(t("android-settings.slack.apply"), primary = true, busy = busy, enabled = dirty) {
            error = null
            val body = buildJsonObject { changes.forEach { (k, v) -> put(k, v) }; icon?.let { put("icon", it.data) } }
            scope.launch {
                try {
                    val r = app.api(station).putSlackApp(connect, body)
                    icon = null
                    iconError = (r["iconError"] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.content
                    val updated = (r["permissionsUpdated"] as? JsonPrimitive)?.booleanOrNull == true
                    approve = updated
                    // Changed permissions are approved in Slack: its page opens at once (the notice stays, to go back to it).
                    if (updated && links != null) open(links.install)
                    app.toast = if (updated) t("android-settings.slack.updatedApprove") else t("android-settings.slack.updated")
                } catch (e: CoreException) { error = e.message }
            }
        }
    }
}

/**
 * Adds a Slack workspace's app configuration token (by its refresh token); `onSaved` gets the workspace. The access
 * token Slack shows above it is told apart from the one wanted.
 */
@Composable
internal fun ConfigTokenSteps(station: String, flow: ConnectFlow? = null, onSaved: (String) -> Unit) {
    val app = LocalApp.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var config by remember { mutableStateOf("") }
    val busy = flow?.busy ?: app.isDoing("slack.addConfigToken", "station" to station)
    var error by remember { mutableStateOf<String?>(null) }
    Steps(listOf(
        t("android-settings.slack.step1") to { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://api.slack.com/apps"))) },
        t("android-settings.slack.step2") to null,
        t("android-settings.slack.step3", "app" to BuildConfig.APP_NAME) to null,
    ))
    SecretField(config, { config = it; flow?.edit { put("config", it) } }, "xoxe-1-…")
    if (flow != null) flow.view?.configError?.let { Text(it, fontSize = 13.sp, color = C.red) }
    else if (config.startsWith("xoxe.xoxp-")) Text(t("android-settings.slack.accessToken"), fontSize = 13.sp, color = C.red)
    else if (config.isNotEmpty() && !config.startsWith("xoxe-")) Text(t("android-settings.slack.refreshToken"), fontSize = 13.sp, color = C.red)
    error?.let { Text(it, fontSize = 13.sp, color = C.red) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
        Button(t("android-settings.slack.add"), primary = true, busy = busy, enabled = flow?.view?.configReady ?: (config.startsWith("xoxe-1-") && config.length > 20)) {
            if (flow != null) { flow.act("config"); return@Button }; error = null
            scope.launch {
                try { val team = app.api(station).addConfigToken(config); config = ""; app.toast = t("android-settings.slack.added"); onSaved(team) }
                catch (e: CoreException) { error = e.message }
            }
        }
    }
}
